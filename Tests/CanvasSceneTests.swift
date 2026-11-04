import AppKit
import Combine
import SwiftUI

@main struct CanvasSceneTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1; print("✓ \(message)")
        }
        var boxes: [CGRect] = []
        for i in 0..<5000 {
            let x = CGFloat((i % 100) * 120 - 6000), y = CGFloat((i / 100) * 90 - 2200)
            boxes.append(CGRect(x: x, y: y, width: 90, height: 60))
        }
        boxes.append(CGRect(x: -100000, y: -2, width: 200000, height: 4))
        let index = CanvasSpatialIndex(boxes)
        for step in 0..<120 {
            let viewport = CGRect(x: CGFloat(step * 137 - 8000), y: CGFloat(step * 61 - 4000), width: 970, height: 730)
            let expected = Set(boxes.indices.filter { boxes[$0].intersects(viewport) })
            precondition(Set(index.query(viewport)) == expected, "Spatial query disagrees with brute force")
        }
        check(true, "Spatial queries match brute force for 120 viewports and long crossing edges")
        check(CanvasSpatialIndex([]).query(.zero).isEmpty, "Empty spatial index is safe")
        let originView = CGRect(x: -50, y: -50, width: 100, height: 100)
        check(index.query(originView).contains(5000), "A link crossing the viewport is found with both endpoints outside")

        var map = MindMap.blank()
        let child = map.addChild(to: map.root.id)!
        let grandchild = map.addChild(to: child)!
        let sibling = map.addChild(to: map.root.id)!
        map.topics[map.topics.firstIndex { $0.id == child }!].connectionStyle = ConnectionStyle(shape: .orthogonal, pattern: .dashed, width: 5, end: .arrow, label: "Tap button 1")
        let document = MapDocument(), store = document.store
        store.load(MindBook(map: map))
        let canvas = MindMapCanvas(store: store)
        canvas.frame = CGRect(x: 0, y: 0, width: 1100, height: 740)
        let window = NSWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = canvas; canvas.layout(); canvas.fit()
        let scene = canvas.prepareScene()
        var modelNotifications = 0
        let subscription = store.objectWillChange.sink { modelNotifications += 1 }
        canvas.pan.x += 40; canvas.setZoom(0.75)
        check(canvas.prepareScene() === scene, "Pan and zoom reuse the scene without measuring text again")
        check(modelNotifications == 0, "Zoom does not publish a document/sidebar/inspector refresh")
        check(store.map == map, "Viewport movement never changes saved topic positions")
        let cachedRoot = scene.node(map.root.id)!.layout
        store.rename(child, title: "Changed title")
        let renamed = canvas.prepareScene()
        check(renamed.measuredTextCount == 1, "A rename only measures the changed topic")
        check(renamed.node(map.root.id)!.layout === cachedRoot, "Unchanged topics keep their cached text layout")
        check(store.outline.first(where: { $0.id == child })?.node.title == "Changed title", "Cached outline updates after a rename")
        let beforeMove = store.map
        var moved = beforeMove; moved.moveSubtree(child, dx: 150, dy: -30)
        store.apply(moved, action: "Test move")
        check(canvas.prepareScene().measuredTextCount == 0, "Moving a subtree reuses all font metrics")
        store.apply(beforeMove, action: "Restore test map")
        canvas.setZoom(0.75); canvas.center(on: child)
        func event(_ kind: NSEvent.EventType, at point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: kind, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        }
        func checkAddingKeepsViewport(_ source: MindMap, label: String) {
            let doc = MapDocument(), target = doc.store
            target.load(MindBook(map: source))
            let view = MindMapCanvas(store: target)
            view.frame = CGRect(x: 0, y: 0, width: 1100, height: 740)
            let host = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
            host.contentView = view; view.layout()
            let branch = source.topics.first { $0.parentID == source.root.id }!
            let scenarios: [(String, Bool)] = [(branch.id, false), (branch.id, true), (source.root.id, false)]
            for (selected, sibling) in scenarios {
                target.load(MindBook(map: source)); target.selectedID = selected
                view.setZoom(1.25); view.center(on: selected)
                // Test an intentional pan as well as zoom, rather than a fitted viewport.
                view.restoreViewport(pan: CGPoint(x: view.pan.x + 37, y: view.pan.y - 29), scale: view.scale)
                let pan = view.pan, zoom = view.scale, anchor = view.world(CGPoint(x: view.bounds.midX, y: view.bounds.midY))
                let parent = sibling ? source.topic(selected)!.parentID! : selected
                let handle = view.handles(target.selected!).first { $0.sibling == sibling }!
                let point = CGPoint(x: handle.rect.midX, y: handle.rect.midY)
                let click = NSEvent.mouseEvent(with: .leftMouseDown, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0, windowNumber: host.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
                view.mouseDown(with: click)
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
                let added = target.selected!
                check(target.map.topics.count == source.topics.count + 1 && added.parentID == parent, "\(label): plus adds the correct \(sibling ? "sibling" : "child") branch")
                check(view.scale == zoom && target.zoom == zoom && view.pan == pan && view.world(CGPoint(x: view.bounds.midX, y: view.bounds.midY)) == anchor,
                      "\(label): \(sibling ? "sibling" : "child") plus preserves zoom, pan, and the viewed world point")
                check(view.editingID == added.id && view.editor?.font?.pointSize == added.font(scale: zoom).pointSize,
                      "\(label): new branch still opens inline editing at the current zoom")
                view.finishEditing(cancel: true)
            }
        }
        checkAddingKeepsViewport(map, label: "Synthetic map")
        let startRect = canvas.rect(store.map.topic(child)!)
        let start = CGPoint(x: startRect.midX, y: startRect.midY)
        let end = CGPoint(x: start.x + 75, y: start.y + 45)
        let snapshot = store.workbook
        canvas.mouseDown(with: event(.leftMouseDown, at: start))
        canvas.mouseDragged(with: event(.leftMouseDragged, at: end))
        check(store.workbook == snapshot, "Dragging is a local preview until mouse-up")
        check(abs(canvas.rect(store.map.topic(child)!).midX - start.x - 75) < 0.01, "Preview geometry follows the pointer")
        check(canvas.prepareScene().measuredTextCount == 0, "Dragging does not rebuild the scene")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03)); document.undoManager?.removeAllActions()
        canvas.mouseUp(with: event(.leftMouseUp, at: end))
        let result = store.map
        check(abs(result.topic(child)!.x - beforeMove.topic(child)!.x - 100) < 0.01, "Mouse-up commits the correct world-space displacement")
        check(abs(result.topic(grandchild)!.x - beforeMove.topic(grandchild)!.x - 100) < 0.01 && result.topic(sibling) == beforeMove.topic(sibling), "Drag moves descendants and preserves unrelated branches")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
        document.undoManager?.undo()
        check(store.map == beforeMove, "One Undo restores the complete branch drag")
        check(canvas.prepareScene().edges.first { $0.childID == child }?.style.label == "Tap button 1", "Connection styling and labels survive a drag and Undo")
        canvas.center(on: child)
        let rect = canvas.rect(store.map.topic(child)!), point = CGPoint(x: rect.midX, y: rect.midY)
        canvas.mouseDown(with: event(.leftMouseDown, at: point))
        canvas.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: point.x + 40, y: point.y + 30)))
        var external = store.map; external.topics[0].title = "Concurrent MCP edit"
        store.applyAI(external)
        canvas.mouseUp(with: event(.leftMouseUp, at: point))
        check(store.map == external, "A concurrent MCP edit cancels the stale drag instead of overwriting it")
        let sheet = store.addSheet(title: "Cache check")
        check(canvas.prepareScene().nodes.count == 1, "Switching to a new sheet invalidates the render cache")
        store.deleteSheet(sheet)
        check(canvas.prepareScene().nodes.count == map.topics.count, "Returning to another sheet rebuilds its own cache")
        subscription.cancel()

        // Geometry, line/label selection, culling and native rendering for every style.
        let sampleRoot = Topic(id: "connection-root", title: "Screen A", x: -300, y: 0)
        var samples = MindMap(topics: [sampleRoot])
        for (shapeIndex, shape) in ConnectionShape.allCases.enumerated() {
            for (patternIndex, pattern) in ConnectionPattern.allCases.enumerated() {
                let row = shapeIndex * 3 + patternIndex
                var topic = Topic(id: "connection-\(row)", parentID: sampleRoot.id, title: "\(shape.title) · \(pattern.title)", x: 320, y: Double(row - 4) * 95, color: row % 6)
                topic.connectionStyle = ConnectionStyle(shape: shape, pattern: pattern, width: Double(patternIndex + 1) * 1.5, end: .arrow, label: row == 7 ? "Tap button 1" : (row.isMultiple(of: 2) ? "Yes" : "No"), labelFontSize: 14)
                if row == 7 {
                    topic.connectionStyle?.label = "Open settings\nAfter login"
                    topic.connectionStyle?.labelAppearance.fontFamily = "Georgia"
                    topic.connectionStyle?.labelAppearance.bold = true; topic.connectionStyle?.labelAppearance.italic = true
                    topic.connectionStyle?.labelAppearance.underline = true; topic.connectionStyle?.labelAppearance.strikethrough = true
                    topic.connectionStyle?.labelAppearance.alignment = .left; topic.connectionStyle?.labelColor = "#234080FF"
                }
                samples.topics.append(topic)
            }
        }
        let sampleStore = MapStore(map: samples), sampleCanvas = MindMapCanvas(store: sampleStore)
        sampleCanvas.frame = CGRect(x: 0, y: 0, width: 1100, height: 950)
        let sampleWindow = NSWindow(contentRect: sampleCanvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
        sampleWindow.contentView = sampleCanvas; sampleCanvas.layout(); sampleCanvas.fit()
        let styledScene = sampleCanvas.prepareScene()
        check(styledScene.edges.count == 9, "All nine shape and pattern combinations build a scene")
        let formattedLabel = styledScene.edges[7].label!
        let attributes = formattedLabel.attributes(at: 0, effectiveRange: nil)
        check(formattedLabel.string == "Open settings\nAfter login" && (attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains([.bold, .italic]) == true, "Arbitrary multiline label text renders with bold and italic font traits")
        check(attributes[.underlineStyle] as? Int == 1 && attributes[.strikethroughStyle] as? Int == 1 && (attributes[.paragraphStyle] as? NSParagraphStyle)?.alignment == .left, "Native labels render underline, strikethrough and paragraph alignment")
        sampleStore.selectConnection("connection-7"); sampleStore.setConnectionStyle { $0.labelAppearance.fontSize = 26 }
        let reformattedScene = sampleCanvas.prepareScene()
        check(reformattedScene.edges[7].labelRect.height > styledScene.edges[7].labelRect.height && (reformattedScene.edges[7].label?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 26, "Changing label text style invalidates cached rendering and updates its bounds")
        check(reformattedScene.edges[0].label === styledScene.edges[0].label && reformattedScene.measuredTextCount == 0, "Label formatting reuses other labels and all node text metrics")
        sampleStore.apply(samples, action: "Restore preview styles")
        var largeLabelStyle = ConnectionStyle(label: String(repeating: "W", count: 500), labelFontSize: 96)
        largeLabelStyle.labelAppearance.bold = true
        largeLabelStyle.labelWidth = 460
        try largeLabelStyle.validate()
        let largeLabel = CanvasRenderEdge(parentID: "a", childID: "b", start: .zero, end: CGPoint(x: 300, y: 180), style: largeLabelStyle, color: .red)
        check(largeLabel.labelRect.height > 2000 && largeLabel.bounds.contains(largeLabel.labelRect), "Maximum-size text uses complete label bounds without a fixed-height crop")
        let longWord = "SupercalifragilisticexpialidociousWithoutAnyAutomaticBreaks"
        let naturalStyle = ConnectionStyle(label: longWord, labelFontSize: 18)
        let naturalLabel = CanvasRenderEdge(parentID: "a", childID: "b", start: .zero, end: CGPoint(x: 500, y: 0), style: naturalStyle, color: .red)
        let oneLine = CanvasRenderEdge(parentID: "a", childID: "b", start: .zero, end: CGPoint(x: 500, y: 0), style: ConnectionStyle(label: "Word", labelFontSize: 18), color: .red)
        check(naturalLabel.labelRect.height == oneLine.labelRect.height && naturalLabel.labelRect.width - 14 >= naturalStyle.naturalLabelWidth, "An automatic text box fits the full word without splitting it across lines")
        var narrowStyle = naturalStyle; narrowStyle.labelWidth = 120
        let narrowLabel = CanvasRenderEdge(parentID: "a", childID: "b", start: .zero, end: CGPoint(x: 500, y: 0), style: narrowStyle, color: .red)
        check(narrowLabel.labelRect.width == 134 && narrowLabel.labelRect.height > naturalLabel.labelRect.height && narrowLabel.labelRect.midX == naturalLabel.labelRect.midX, "A chosen container width wraps text, grows in height and stays centered on the line")
        var tallStyle = naturalStyle; tallStyle.labelHeight = 120
        let tallLabel = CanvasRenderEdge(parentID: "a", childID: "b", start: .zero, end: CGPoint(x: 500, y: 0), style: tallStyle, color: .red)
        check(tallLabel.labelRect.height == 128 && tallLabel.labelRect.width == naturalLabel.labelRect.width && tallLabel.labelTextRect.height == naturalLabel.labelTextRect.height && tallLabel.labelTextRect.midY == tallLabel.labelRect.midY, "A manual height changes the container independently and keeps the text vertically centered")
        tallStyle.labelHeight = 8
        let clippedLabel = CanvasRenderEdge(parentID: "a", childID: "b", start: .zero, end: CGPoint(x: 500, y: 0), style: tallStyle, color: .red)
        check(clippedLabel.labelRect.height == 16 && clippedLabel.labelTextRect.height == 8 && clippedLabel.label?.string == longWord, "A short container clips its display area while preserving the full label text")
        for edge in styledScene.edges {
            check(styledScene.bounds.contains(edge.bounds), "Fit bounds include the complete line, arrow and label: \(edge.childID)")
            check(edge.markers.count == 1 && edge.label?.string == edge.style.label, "Arrows and labels are present: \(edge.childID)")
            check(edge.contains(CGPoint(x: edge.labelRect.midX, y: edge.labelRect.midY), tolerance: 1), "The label is selectable: \(edge.childID)")
            if edge.style.shape == .straight { check(edge.path.elementCount == 2, "Straight connections contain only their endpoints") }
            if edge.style.shape == .orthogonal {
                var points = [CGPoint](repeating: .zero, count: 3), previous = edge.start
                for i in 1..<edge.path.elementCount {
                    let kind = edge.path.element(at: i, associatedPoints: &points)
                    check(kind == .lineTo && (points[0].x == previous.x || points[0].y == previous.y), "Elbow segments stay horizontal or vertical")
                    previous = points[0]
                }
            }
        }
        let horizontal = styledScene.edges.first { $0.childID == "connection-4" }!
        let labelOnlyArea = CGRect(x: horizontal.labelRect.midX - 1, y: horizontal.labelRect.minY + 1, width: 2, height: 2)
        check(!horizontal.path.controlPointBounds.intersects(labelOnlyArea) && styledScene.edgeIndex.query(labelOnlyArea).contains(4), "Labels remain visible when the stroke itself is outside the viewport")
        for zoom in [0.4, 1.0, 2.0] {
            sampleCanvas.setZoom(zoom)
            let clickPoint = sampleCanvas.screen(CGPoint(x: horizontal.labelRect.midX, y: horizontal.labelRect.midY))
            check(sampleCanvas.connection(at: clickPoint)?.childID == horizontal.childID, "Connection label hit testing follows zoom: \(zoom)")
            let click = NSEvent.mouseEvent(with: .leftMouseDown, location: sampleCanvas.convert(clickPoint, to: nil), modifierFlags: [], timestamp: 0, windowNumber: sampleWindow.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
            sampleCanvas.mouseDown(with: click)
            check(sampleStore.inspectingConnection && sampleStore.selectedID == horizontal.childID, "Clicking a label opens Connection controls")
            if zoom >= 1 { check(sampleCanvas.editingConnectionID == horizontal.childID && sampleCanvas.editor != nil, "A single click on readable label text starts inline editing") }
        }
        let rightToLeft = CanvasRenderEdge(parentID: "a", childID: "b", start: CGPoint(x: 200, y: 30), end: CGPoint(x: -200, y: -60), style: ConnectionStyle(shape: .orthogonal, start: .arrow, end: .arrow, label: "No"), color: .red)
        check(rightToLeft.markers.count == 2 && rightToLeft.contains(CGPoint(x: 0, y: -15), tolerance: 2), "Right-to-left elbow lines support two arrows and a centered label")
        let curved = CanvasRenderEdge(parentID: "a", childID: "b", start: .zero, end: CGPoint(x: 300, y: 180), style: ConnectionStyle(), color: .red)
        check(curved.contains(CGPoint(x: 150, y: 90), tolerance: 2) && !curved.contains(CGPoint(x: 150, y: 160), tolerance: 2), "Curve hit testing follows the curve instead of its bounding rectangle")
        var overlapMap = samples
        overlapMap.topics = [sampleRoot, Topic(id: "overlap-child", parentID: sampleRoot.id, title: "Nearby child", x: -200, y: 180)]
        let overlapEdge = CanvasScene(map: overlapMap).edges[0]
        var controls = [CGPoint](repeating: .zero, count: 3)
        _ = overlapEdge.path.element(at: 1, associatedPoints: &controls)
        check(controls[0].x > overlapEdge.start.x, "Curves preserve their attachment direction when node bounds overlap horizontally")
        sampleCanvas.fit()
        func capture(_ view: NSView, to path: String) throws {
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        }
        // A transparent glyph color isolates the label gap from the text itself.
        let gapRoot = Topic(id: "gap-root", title: "Start", x: -300, y: 0)
        var gapChild = Topic(id: "gap-child", parentID: gapRoot.id, title: "End", x: 300, y: 0)
        gapChild.connectionStyle = ConnectionStyle(shape: .straight, width: 6, color: "#000000FF", label: "Transparent label", labelFontSize: 18, labelColor: "#00000000")
        let gapMap = MindMap(topics: [gapRoot, gapChild]), gapStore = MapStore(map: gapMap)
        let gapCanvas = MindMapCanvas(store: gapStore)
        gapCanvas.frame = CGRect(x: 0, y: 0, width: 800, height: 400)
        let gapWindow = NSWindow(contentRect: gapCanvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
        gapWindow.contentView = gapCanvas; gapCanvas.layout()
        func rasterizeGap() -> NSBitmapImageRep {
            let bitmap = gapCanvas.bitmapImageRepForCachingDisplay(in: gapCanvas.bounds)!
            gapCanvas.cacheDisplay(in: gapCanvas.bounds, to: bitmap)
            return bitmap
        }
        let gapEdge = gapCanvas.prepareScene().edges[0], gapImage = rasterizeGap()
        gapStore.apply(MindMap(topics: [gapRoot]), action: "Render background baseline")
        let backdrop = rasterizeGap()
        let topLeft = gapCanvas.screen(gapEdge.labelRect.origin), factor = CGFloat(gapImage.pixelsWide) / gapCanvas.bounds.width
        let region = CGRect(x: topLeft.x, y: topLeft.y, width: gapEdge.labelRect.width, height: gapEdge.labelRect.height).insetBy(dx: 2, dy: 2)
        let backdropColor = backdrop.colorAt(x: 5, y: 5)!.hexString
        var differentPixels = 0, visibleDotPixels = 0
        for y in Int(region.minY * factor)..<Int(region.maxY * factor) {
            for x in Int(region.minX * factor)..<Int(region.maxX * factor) {
                let original = backdrop.colorAt(x: x, y: y)!.hexString
                if gapImage.colorAt(x: x, y: y)!.hexString != original { differentPixels += 1 }
                if original != backdropColor { visibleDotPixels += 1 }
            }
        }
        check(visibleDotPixels > 0 && differentPixels == 0, "Label gaps preserve the canvas dots pixel-for-pixel with no painted background or line underneath")
        gapStore.apply(gapMap, action: "Check selected connection rendering"); gapStore.selectConnection("gap-child")
        let selectedGapImage = rasterizeGap()
        let besideLine = gapCanvas.screen(CGPoint(x: gapEdge.start.x + 20, y: 5))
        check(selectedGapImage.colorAt(x: Int(besideLine.x * factor), y: Int(besideLine.y * factor))!.hexString != backdrop.colorAt(x: Int(besideLine.x * factor), y: Int(besideLine.y * factor))!.hexString, "Selecting a connection retains its thick halo")
        func haloStrength(at point: CGPoint) -> Double {
            let p = gapCanvas.screen(point), x = Int(p.x * factor), y = Int(p.y * factor)
            let color = selectedGapImage.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!, base = backdrop.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
            return Double(abs(color.redComponent - base.redComponent) + abs(color.greenComponent - base.greenComponent) + abs(color.blueComponent - base.blueComponent))
        }
        check(haloStrength(at: CGPoint(x: gapEdge.labelRect.minX - 8, y: 5)) < haloStrength(at: CGPoint(x: gapEdge.labelRect.minX - 24, y: 5)), "The halo fades before the label instead of ending at a hard rectangular cut")
        let outsideGap = gapCanvas.screen(CGPoint(x: gapEdge.start.x + 20, y: 0))
        check(gapImage.colorAt(x: Int(outsideGap.x * factor), y: Int(outsideGap.y * factor))!.hexString != backdrop.colorAt(x: Int(outsideGap.x * factor), y: Int(outsideGap.y * factor))!.hexString, "The connection remains visible outside the label gap")
        gapChild.connectionStyle?.label = ""
        gapStore.apply(MindMap(topics: [gapRoot, gapChild]), action: "Remove connection label")
        let uninterrupted = rasterizeGap(), middle = gapCanvas.screen(CGPoint(x: gapEdge.labelRect.midX, y: 0))
        check(uninterrupted.colorAt(x: Int(middle.x * factor), y: Int(middle.y * factor))!.hexString != backdrop.colorAt(x: Int(middle.x * factor), y: Int(middle.y * factor))!.hexString, "Clearing the label restores the continuous connection")

        gapStore.apply(gapMap, action: "Restore blank-canvas fixture")
        func blankEvent(_ kind: NSEvent.EventType, at p: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: kind, location: gapCanvas.convert(p, to: nil), modifierFlags: [], timestamp: 0, windowNumber: gapWindow.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        }
        let blankPoint = CGPoint(x: 40, y: 40), blankDragEnd = CGPoint(x: 120, y: 90)
        gapStore.select(gapChild.id)
        let beforeBlankClick = gapStore.map, blankPan = gapCanvas.pan, blankZoom = gapCanvas.scale
        gapCanvas.mouseDown(with: blankEvent(.leftMouseDown, at: blankPoint))
        check(gapStore.selectedID == gapChild.id, "A blank mouse-down waits to distinguish a click from a pan")
        gapCanvas.mouseUp(with: blankEvent(.leftMouseUp, at: blankPoint))
        check(gapStore.selected == nil && gapStore.map == beforeBlankClick && gapCanvas.pan == blankPan && gapCanvas.scale == blankZoom, "Clicking empty canvas deselects a topic without moving or editing it")
        gapStore.selectConnection(gapChild.id)
        gapCanvas.mouseDown(with: blankEvent(.leftMouseDown, at: blankPoint))
        gapCanvas.mouseDragged(with: blankEvent(.leftMouseDragged, at: blankDragEnd))
        gapCanvas.mouseUp(with: blankEvent(.leftMouseUp, at: blankDragEnd))
        check(gapStore.selectedID == gapChild.id && gapStore.inspectingConnection && gapStore.map == beforeBlankClick && gapCanvas.pan == CGPoint(x: blankPan.x + 80, y: blankPan.y + 50), "Dragging empty canvas pans while preserving the current connection selection")
        gapCanvas.restoreViewport(pan: blankPan, scale: blankZoom)
        gapCanvas.spaceDown = true
        gapCanvas.mouseDown(with: blankEvent(.leftMouseDown, at: blankPoint)); gapCanvas.mouseUp(with: blankEvent(.leftMouseUp, at: blankPoint))
        gapCanvas.spaceDown = false
        check(gapStore.selectedID == gapChild.id, "A Space-pan click preserves selection")
        gapCanvas.editConnectionLabel(gapChild.id); gapCanvas.editor?.stringValue = "Edited before deselect"
        gapCanvas.mouseDown(with: blankEvent(.leftMouseDown, at: blankPoint)); gapCanvas.mouseUp(with: blankEvent(.leftMouseUp, at: blankPoint))
        check(gapStore.selectedID == nil && gapCanvas.editor == nil && gapStore.map.topic(gapChild.id)?.connectionAppearance.label == "Edited before deselect", "Clicking empty space commits the current label edit before removing its selection")

        var resizeChild = gapChild
        resizeChild.connectionStyle = ConnectionStyle(label: "Open the account settings screen", labelFontSize: 18)
        let resizeMap = MindMap(topics: [gapRoot, resizeChild]), resizeDocument = MapDocument()
        let resizeStore = resizeDocument.store, resizeCanvas = MindMapCanvas(store: resizeDocument.store)
        resizeCanvas.frame = CGRect(x: 0, y: 0, width: 800, height: 500)
        let resizeWindow = NSWindow(contentRect: resizeCanvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
        resizeWindow.contentView = resizeCanvas; resizeCanvas.layout()
        func resizeEvent(_ kind: NSEvent.EventType, at p: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: kind, location: resizeCanvas.convert(p, to: nil), modifierFlags: [], timestamp: 0, windowNumber: resizeWindow.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        }
        let resizePositions: [(MindMapCanvas.LabelResizePosition, CGFloat)] = [(.right, 0.75), (.left, 1.5), (.top, 0.75), (.bottom, 1.5), (.topLeft, 1), (.topRight, 1), (.bottomLeft, 1), (.bottomRight, 1)]
        for (position, zoom) in resizePositions {
            let horizontal = position.horizontalDirection, vertical = position.verticalDirection
            resizeStore.load(MindBook(map: resizeMap)); resizeStore.selectConnection(resizeChild.id)
            resizeCanvas.restoreViewport(pan: CGPoint(x: 400, y: 250), scale: zoom)
            let before = resizeStore.map, pan = resizeCanvas.pan, originalEdge = resizeCanvas.prepareScene().edges[0]
            let originalWidth = originalEdge.labelRect.width - 14, originalHeight = originalEdge.labelRect.height - 8
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03)); resizeDocument.undoManager?.removeAllActions()
            let handle = resizeCanvas.labelResizeRegions().first { $0.position == position }!
            let start = CGPoint(x: handle.rect.midX, y: handle.rect.midY)
            let end = CGPoint(x: start.x - 50 * horizontal * zoom, y: start.y + 30 * vertical * zoom)
            resizeCanvas.mouseDown(with: resizeEvent(.leftMouseDown, at: start))
            resizeCanvas.mouseDragged(with: resizeEvent(.leftMouseDragged, at: end))
            check(resizeStore.map == before, "Dragging the \(position) text-box boundary previews width without mutating the document")
            let previewHandles = resizeCanvas.labelResizeRegions()
            let previewWidth = (previewHandles[1].rect.midX - previewHandles[0].rect.midX) / zoom - 14
            let expectedWidth = horizontal == 0 ? originalWidth : originalWidth - 100
            check(abs(previewWidth - expectedWidth) < 0.01, "\(position): preview width follows the horizontal drag component at zoom \(zoom)")
            if vertical != 0 {
                let previewHeight = (previewHandles[3].rect.midY - previewHandles[2].rect.midY) / zoom - 8
                check(abs(previewHeight - (originalHeight + 60)) < 0.01, "\(position): preview height follows the vertical drag component")
            }
            resizeCanvas.mouseUp(with: resizeEvent(.leftMouseUp, at: end))
            let after = resizeStore.map, resized = resizeCanvas.prepareScene().edges[0]
            let resizedStyle = resizeStore.selected!.connectionAppearance
            if horizontal != 0 {
                check(abs(resizedStyle.labelWidth! - expectedWidth) < 0.01, "\(position): dropping the border saves the new width")
            } else {
                check(resizedStyle.labelWidth == nil && resized.labelRect.width == originalEdge.labelRect.width, "Vertical resizing preserves automatic width and text wrapping")
            }
            if vertical != 0 {
                check(abs(resizedStyle.labelHeight! - (originalHeight + 60)) < 0.01 && resized.labelRect.height > originalEdge.labelRect.height, "\(position): dropping the border saves the new height")
            } else {
                check(resizedStyle.labelHeight == nil && resized.labelRect.height > originalEdge.labelRect.height, "Horizontal-only resizing retains automatic height for wrapped text")
            }
            check(resized.labelRect.midX == originalEdge.labelRect.midX && resized.labelRect.midY == originalEdge.labelRect.midY, "Two-dimensional resizing keeps the label centered on the connection")
            check(resizeCanvas.pan == pan && resizeCanvas.scale == zoom && after.topic(resizeChild.id)?.title == before.topic(resizeChild.id)?.title, "Resizing a label preserves the viewport and node contents")
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03)); resizeDocument.undoManager?.undo()
            check(resizeStore.map == before, "One Undo restores both automatic text-box dimensions")
            resizeDocument.undoManager?.redo()
            check(resizeStore.map == after, "Redo restores both chosen text-box dimensions")
        }
        resizeStore.setConnectionLabelSize(resizeChild.id, width: nil, height: nil)
        check(resizeCanvas.prepareScene().edges[0].labelRect.height == oneLine.labelRect.height, "Automatic fit removes wrapping after a manual resize")
        resizeCanvas.editConnectionLabel(resizeChild.id)
        let insertionBeforeResize = (resizeCanvas.editor?.currentEditor() as? NSTextView)?.selectedRange()
        func editorLineCount() -> Int {
            guard let textView = resizeCanvas.editor?.currentEditor() as? NSTextView, let manager = textView.layoutManager, let container = textView.textContainer else { return 0 }
            manager.ensureLayout(for: container)
            var count = 0
            manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) { _, _, _, _, _ in count += 1 }
            return count
        }
        check(editorLineCount() == 1, "The native inline editor initially fits the complete label on one line")
        let corner = resizeCanvas.labelResizeRegions().first { $0.position == .topLeft }!
        let cornerPoint = resizeCanvas.convert(CGPoint(x: corner.rect.midX, y: corner.rect.midY), to: resizeCanvas.superview)
        check(resizeCanvas.hitTest(cornerPoint) === resizeCanvas, "The resize corner receives pointer input while the text editor is active")
        let textPoint = resizeCanvas.convert(CGPoint(x: resizeCanvas.editor!.frame.midX, y: resizeCanvas.editor!.frame.midY), to: resizeCanvas.superview)
        check(resizeCanvas.hitTest(textPoint) !== resizeCanvas, "The center of the label keeps native text editing instead of starting a resize")
        let inlineHandle = resizeCanvas.labelResizeRegions().last!, inlineStart = CGPoint(x: inlineHandle.rect.midX, y: inlineHandle.rect.midY)
        let inlineEnd = CGPoint(x: inlineStart.x - 75, y: inlineStart.y)
        resizeCanvas.mouseDown(with: resizeEvent(.leftMouseDown, at: inlineStart))
        resizeCanvas.mouseDragged(with: resizeEvent(.leftMouseDragged, at: inlineEnd))
        resizeCanvas.mouseUp(with: resizeEvent(.leftMouseUp, at: inlineEnd))
        check(resizeCanvas.editingConnectionID == resizeChild.id && (resizeCanvas.editor?.currentEditor() as? NSTextView)?.selectedRange() == insertionBeforeResize, "Resizing an active text editor resumes editing at the same insertion point")
        check(editorLineCount() > 1, "The native inline editor wraps its text after the container is narrowed")
        resizeCanvas.finishEditing()
        let cancelHandle = resizeCanvas.labelResizeRegions().first!, cancelStart = CGPoint(x: cancelHandle.rect.midX, y: cancelHandle.rect.midY)
        let beforeCanceledResize = resizeStore.map
        resizeCanvas.mouseDown(with: resizeEvent(.leftMouseDown, at: cancelStart))
        resizeCanvas.mouseDragged(with: resizeEvent(.leftMouseDragged, at: CGPoint(x: cancelStart.x + 50, y: cancelStart.y)))
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: resizeWindow.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        resizeCanvas.keyDown(with: escape); resizeCanvas.mouseUp(with: resizeEvent(.leftMouseUp, at: cancelStart))
        check(resizeStore.map == beforeCanceledResize, "Escape cancels a text-box resize without changing the map")
        resizeCanvas.mouseDown(with: resizeEvent(.leftMouseDown, at: cancelStart))
        resizeCanvas.mouseDragged(with: resizeEvent(.leftMouseDragged, at: CGPoint(x: cancelStart.x + 50, y: cancelStart.y)))
        var concurrent = resizeStore.map; concurrent.topics[0].title = "External title"
        resizeStore.applyAI(concurrent)
        resizeCanvas.mouseUp(with: resizeEvent(.leftMouseUp, at: cancelStart))
        check(resizeStore.map == concurrent, "A concurrent map change cancels a stale label resize")
        try capture(sampleCanvas, to: "build/connection-canvas-preview.png")
        check(true, "Native canvas renders all line combinations to a preview image")
        if ProcessInfo.processInfo.environment["NIX_CONNECTION_PREVIEW"] == "1" {
            sampleStore.sidebarVisible = false; sampleStore.selectConnection("connection-7")
            let host = NSHostingView(rootView: ContentView(store: sampleStore))
            host.frame = CGRect(x: 0, y: 0, width: 1440, height: 1050)
            let previewWindow = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
            previewWindow.contentView = host; host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3)); sampleStore.canvas?.fit()
            try capture(host, to: "build/connection-inspector-preview.png")
            try MapFormats.encode(samples, type: MapFormats.nativeType).write(to: URL(fileURLWithPath: "build/connection-styles.nixmap"))
            sampleStore.clearSelection(); host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
            try capture(host, to: "build/canvas-deselected-preview.png")
        }

        if CommandLine.arguments.count > 1 {
            let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let fixture = try MapFormats.decodeBook(data, type: MapFormats.nativeType)
            let realScene = CanvasScene(map: fixture.activeMap)
            check(realScene.nodes.count == fixture.activeMap.topics.count, "User fixture preserves every node")
            check(realScene.edges.count == realScene.nodes.count - 1, "User fixture preserves every tree connection")
            let fullArea = realScene.bounds.insetBy(dx: -1, dy: -1)
            check(Set(realScene.nodeIndex.query(fullArea)).count == realScene.nodes.count, "The full fixture is reachable through the spatial index")
            for step in 0..<40 {
                let area = CGRect(x: realScene.bounds.minX + CGFloat(step) * realScene.bounds.width / 40, y: realScene.bounds.minY + CGFloat(step) * realScene.bounds.height / 40, width: 1200, height: 800)
                let expected = Set(realScene.nodes.indices.filter { realScene.nodes[$0].bounds.intersects(area) })
                precondition(Set(realScene.nodeIndex.query(area)) == expected)
                let links = Set(realScene.edges.indices.filter { realScene.edges[$0].bounds.intersects(area) })
                precondition(Set(realScene.edgeIndex.query(area)) == links)
            }
            check(true, "User fixture node/link culling agrees with brute force across 40 viewports")
            let reuse = CanvasScene(map: fixture.activeMap, previous: realScene)
            check(reuse.measuredTextCount == 0, "Unchanged real-world fixture reuses every measured title")
            checkAddingKeepsViewport(fixture.activeMap, label: "User fixture")
        }
        print("PASS: \(checks) canvas checks")
    }
}
