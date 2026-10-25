import AppKit
import SwiftUI
import Combine

struct CanvasHost: NSViewRepresentable {
    @ObservedObject var store: MapStore
    func makeNSView(context: Context) -> MindMapCanvas { MindMapCanvas(store: store) }
    func updateNSView(_ view: MindMapCanvas, context: Context) { view.setAccessibilityLabel("Mind map canvas"); view.needsDisplay = true }
}

@MainActor final class CanvasAccessibleElement: NSAccessibilityElement {
    override func isAccessibilityElement() -> Bool { true }
    var press: (() -> Void)?
    override func accessibilityPerformPress() -> Bool { press?(); return true }
}

@MainActor final class MindMapCanvas: NSView, NSTextFieldDelegate {
    let store: MapStore
    var scale: CGFloat = 1
    var pan = CGPoint.zero
    var lastSize = CGSize.zero
    var dragID: String?
    var dragStart = CGPoint.zero
    var panStart = CGPoint.zero
    var dragMap: MindMap?
    var dragging = false
    var spaceDown = false
    var editor: NSTextField?
    var editingID: String?
    private var fieldEditorBackground: (NSTextView, Bool, NSColor)?
    var accessibleNodes: [String: CanvasAccessibleElement] = [:]
    var subscription: AnyCancellable?
    private var scene: CanvasScene?
    private var sceneRevision: UInt64?
    private var movingIDs: Set<String> = []
    private var dragOffset = CGPoint.zero
    private var dragRevision: UInt64 = 0
    private var dotsPath: NSBezierPath?
    private var dotsSize = CGSize.zero
    private var dotsSpacing: CGFloat = 0
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(store: MapStore) {
        self.store = store
        super.init(frame: .zero)
        wantsLayer = true
        clipsToBounds = true
        layer?.masksToBounds = true
        store.canvas = self
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Mind map canvas")
        subscription = store.objectWillChange.sink { [weak self] _ in
            self?.needsDisplay = true
            if let self { self.window?.invalidateCursorRects(for: self) }
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); window?.makeFirstResponder(self) }
    override func layout() {
        super.layout()
        if lastSize == .zero { pan = CGPoint(x: bounds.midX, y: bounds.midY) }
        else { pan.x += (bounds.width - lastSize.width) / 2; pan.y += (bounds.height - lastSize.height) / 2 }
        lastSize = bounds.size; viewportDidChange()
    }
    func screen(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x * scale + pan.x, y: point.y * scale + pan.y) }
    func world(_ point: CGPoint) -> CGPoint { CGPoint(x: (point.x - pan.x) / scale, y: (point.y - pan.y) / scale) }
    @discardableResult func prepareScene() -> CanvasScene {
        if sceneRevision != store.mapRevision || scene == nil {
            if dragMap != nil && dragRevision != store.mapRevision { cancelDrag() }
            scene = CanvasScene(map: store.map, previous: scene)
            sceneRevision = store.mapRevision
        }
        return scene!
    }
    private func offset(for id: String) -> CGPoint { movingIDs.contains(id) ? dragOffset : .zero }
    private func worldRect(_ node: CanvasRenderNode) -> CGRect {
        let delta = offset(for: node.topic.id)
        return node.bounds.offsetBy(dx: delta.x, dy: delta.y)
    }
    private func screenRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * scale + pan.x, y: rect.minY * scale + pan.y, width: rect.width * scale, height: rect.height * scale)
    }
    func nodeSize(_ node: Topic) -> CGSize { prepareScene().node(node.id)?.layout.size ?? node.layoutSize }
    func rect(_ node: Topic) -> CGRect {
        guard let entry = prepareScene().node(node.id) else { return .zero }
        return screenRect(worldRect(entry))
    }
    private var visibleWorldRect: CGRect {
        CGRect(x: -pan.x / scale, y: -pan.y / scale, width: bounds.width / scale, height: bounds.height / scale)
    }
    private func visibleNodes(in area: CGRect, scene: CanvasScene) -> [Int] {
        let normal = scene.nodeIndex.query(area)
        guard !movingIDs.isEmpty else { return normal.sorted() }
        let moved = scene.nodeIndex.query(area.offsetBy(dx: -dragOffset.x, dy: -dragOffset.y))
        return (normal.filter { !movingIDs.contains(scene.nodes[$0].topic.id) } + moved.filter { movingIDs.contains(scene.nodes[$0].topic.id) }).sorted()
    }
    private func visibleEdges(in area: CGRect, scene: CanvasScene) -> [Int] {
        let normal = scene.edgeIndex.query(area)
        guard !movingIDs.isEmpty else { return normal }
        let moved = scene.edgeIndex.query(area.offsetBy(dx: -dragOffset.x, dy: -dragOffset.y))
        var result = normal.filter { !movingIDs.contains(scene.edges[$0].childID) }
        result += moved.filter { movingIDs.contains(scene.edges[$0].parentID) }
        if let dragID, let incoming = scene.incomingEdge[dragID] { result.append(incoming) }
        return result
    }
    private func viewportDidChange() {
        positionEditor(); needsDisplay = true; window?.invalidateCursorRects(for: self)
    }
    struct Handle { var rect: CGRect; var sibling: Bool }
    func handles(_ node: Topic) -> [Handle] {
        let r = rect(node); let size: CGFloat = 23
        if node.parentID == nil {
            let x = (prepareScene().direction(of: node.id) > 0 ? r.maxX : r.minX) - size / 2
            return [Handle(rect: CGRect(x: x, y: r.minY - size / 2, width: size, height: size), sibling: false)]
        }
        let right = prepareScene().direction(of: node.id) > 0
        let x = (right ? r.maxX : r.minX) - size / 2
        return [Handle(rect: CGRect(x: x, y: r.minY - size / 2, width: size, height: size), sibling: false), Handle(rect: CGRect(x: x, y: r.maxY - size / 2, width: size, height: size), sibling: true)]
    }
    override func draw(_ dirtyRect: NSRect) {
        Palette.background.setFill(); bounds.fill()
        drawDots()
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let scene = prepareScene()
        let area = visibleWorldRect.insetBy(dx: -32 / scale, dy: -32 / scale)
        let visible = visibleNodes(in: area, scene: scene)
        context.saveGState()
        context.translateBy(x: pan.x, y: pan.y); context.scaleBy(x: scale, y: scale)
        for index in visibleEdges(in: area, scene: scene) { drawEdge(scene.edges[index], in: area, scene: scene, context: context) }
        for index in visible { drawNode(scene.nodes[index], showShadow: scale >= 0.5 && visible.count < 250, context: context) }
        context.restoreGState()
        if let selected = scene.node(store.selectedID)?.topic {
            for handle in handles(selected) where handle.rect.intersects(bounds) { drawHandle(handle, node: selected) }
        }
    }
    func drawDots() {
        let spacing = 24 * scale
        guard spacing >= 10, let context = NSGraphicsContext.current?.cgContext else { return }
        if dotsPath == nil || dotsSpacing != spacing || dotsSize != bounds.size {
            let path = NSBezierPath()
            var x: CGFloat = 0
            while x <= bounds.width + spacing {
                var y: CGFloat = 0
                while y <= bounds.height + spacing {
                    path.appendOval(in: CGRect(x: x, y: y, width: 1.5, height: 1.5)); y += spacing
                }
                x += spacing
            }
            dotsPath = path; dotsSpacing = spacing; dotsSize = bounds.size
        }
        context.saveGState()
        context.translateBy(x: pan.x.truncatingRemainder(dividingBy: spacing) - spacing, y: pan.y.truncatingRemainder(dividingBy: spacing) - spacing)
        NSColor(srgbRed: 0.83, green: 0.82, blue: 0.80, alpha: 0.6).setFill(); dotsPath?.fill()
        context.restoreGState()
    }
    private func drawEdge(_ edge: CanvasRenderEdge, in area: CGRect, scene: CanvasScene, context: CGContext) {
        let parentMoves = movingIDs.contains(edge.parentID), childMoves = movingIDs.contains(edge.childID)
        edge.color.setStroke()
        if parentMoves != childMoves, let parent = scene.node(edge.parentID), let child = scene.node(edge.childID) {
            let a = worldRect(parent), b = worldRect(child), right = b.midX >= a.midX
            let start = CGPoint(x: right ? a.maxX : a.minX, y: a.midY), end = CGPoint(x: right ? b.minX : b.maxX, y: b.midY)
            let path = CanvasScene.connection(from: start, to: end, right: right)
            if path.controlPointBounds.insetBy(dx: -2, dy: -2).intersects(area) { path.lineWidth = 2.2; path.stroke() }
        } else {
            // Connections smaller than a couple of pixels add no readable detail.
            guard max(edge.bounds.width, edge.bounds.height) * scale >= 2 else { return }
            if parentMoves { context.saveGState(); context.translateBy(x: dragOffset.x, y: dragOffset.y) }
            edge.path.lineWidth = 2.2; edge.path.stroke()
            if parentMoves { context.restoreGState() }
        }
    }
    func shapePath(_ shape: NodeShape, rect: CGRect) -> NSBezierPath { CanvasScene.shapePath(shape, rect: rect, radius: 14 * scale) }
    func textRect(_ node: Topic) -> CGRect {
        let r = rect(node)
        if node.appearance.shape == .diamond { return r.insetBy(dx: r.width * 0.25, dy: r.height * 0.25) }
        if node.appearance.shape == .ellipse { return r.insetBy(dx: r.width * 0.16, dy: r.height * 0.16) }
        return r.insetBy(dx: 18 * scale, dy: 12 * scale)
    }
    private func drawNode(_ entry: CanvasRenderNode, showShadow: Bool, context: CGContext) {
        let node = entry.topic, style = entry.layout.style
        let selected = node.id == store.selectedID
        let delta = offset(for: node.id)
        if delta != .zero { context.saveGState(); context.translateBy(x: delta.x, y: delta.y) }
        defer { if delta != .zero { context.restoreGState() } }
        if selected {
            let outer = CanvasScene.shapePath(style.shape, rect: entry.bounds.insetBy(dx: -5 / scale, dy: -5 / scale))
            Palette.purple.withAlphaComponent(0.13).setFill(); outer.fill()
        }
        if showShadow {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.05); shadow.shadowBlurRadius = 10 / scale; shadow.shadowOffset = NSSize(width: 0, height: 3 / scale); shadow.set()
            entry.fill.setFill(); entry.path.fill()
            NSGraphicsContext.restoreGraphicsState()
        } else { entry.fill.setFill(); entry.path.fill() }
        if style.borderWidth > 0 && style.borderWidth * scale >= 0.4 { entry.border.setStroke(); entry.path.lineWidth = style.borderWidth; entry.path.stroke() }
        if selected { Palette.purple.withAlphaComponent(0.65).setStroke(); entry.path.lineWidth = 1.2 / scale; entry.path.stroke() }
        // Keep overview rendering cheap; the same cached, full-quality text returns on zoom-in.
        if editingID != node.id && style.fontSize * scale >= 6 {
            let drawRect = entry.layout.textRect.offsetBy(dx: entry.bounds.minX, dy: entry.bounds.minY)
            entry.layout.text.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])
        }
        if !node.note.isEmpty && scale >= 0.35 {
            entry.textColor.withAlphaComponent(0.7).setFill()
            NSBezierPath(ovalIn: CGRect(x: entry.bounds.maxX - 12, y: entry.bounds.maxY - 12, width: 4, height: 4)).fill()
        }
    }
    func drawHandle(_ handle: Handle, node: Topic) {
        let circle = NSBezierPath(ovalIn: handle.rect)
        NSColor.white.setFill(); circle.fill()
        Palette.color(node.color).withAlphaComponent(0.4).setStroke(); circle.lineWidth = 1; circle.stroke()
        let center = CGPoint(x: handle.rect.midX, y: handle.rect.midY)
        let plus = NSBezierPath(); plus.move(to: CGPoint(x: center.x - 4, y: center.y)); plus.line(to: CGPoint(x: center.x + 4, y: center.y)); plus.move(to: CGPoint(x: center.x, y: center.y - 4)); plus.line(to: CGPoint(x: center.x, y: center.y + 4))
        Palette.color(node.color).setStroke(); plus.lineWidth = 1.5; plus.stroke()
    }
    override func resetCursorRects() {
        if spaceDown { addCursorRect(bounds, cursor: .openHand) }
        else {
            let scene = prepareScene()
            for index in visibleNodes(in: visibleWorldRect, scene: scene) { addCursorRect(screenRect(worldRect(scene.nodes[index])).intersection(bounds), cursor: .openHand) }
            if let selected = scene.node(store.selectedID)?.topic {
                for handle in handles(selected) where handle.rect.intersects(bounds) { addCursorRect(handle.rect.intersection(bounds), cursor: .pointingHand) }
            }
        }
    }
    private func cancelDrag() { dragID = nil; dragMap = nil; movingIDs = []; dragOffset = .zero; dragging = false }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let scene = prepareScene()
        if let selected = scene.node(store.selectedID)?.topic, !spaceDown {
            for handle in handles(selected) where handle.rect.insetBy(dx: -3, dy: -3).contains(p) {
                if handle.sibling { store.addSibling(selected.id) } else { store.addChild(selected.id) }; return
            }
        }
        finishEditing(); window?.makeFirstResponder(self)
        dragStart = p; panStart = pan; cancelDrag()
        let point = world(p)
        let hits = prepareScene().nodeIndex.query(CGRect(x: point.x, y: point.y, width: 0.001, height: 0.001))
        if !spaceDown, let index = hits.max() {
            let node = prepareScene().nodes[index].topic
            store.selectedID = node.id
            if event.clickCount == 2 { editSelected(); return }
            dragID = node.id; dragMap = store.map; dragRevision = store.mapRevision
            movingIDs = store.map.descendants(of: node.id)
        }
        needsDisplay = true; window?.invalidateCursorRects(for: self)
    }
    override func mouseDragged(with event: NSEvent) {
        guard editor == nil else { return }
        if dragMap != nil && dragRevision != store.mapRevision { cancelDrag(); needsDisplay = true; return }
        let p = convert(event.locationInWindow, from: nil)
        let dx = p.x - dragStart.x, dy = p.y - dragStart.y
        guard hypot(dx, dy) > 3 else { return }
        dragging = true
        if dragID != nil { dragOffset = CGPoint(x: dx / scale, y: dy / scale) }
        else { pan = CGPoint(x: panStart.x + dx, y: panStart.y + dy) }
        viewportDidChange()
    }
    override func mouseUp(with event: NSEvent) {
        let original = dragMap, delta = dragOffset, ids = movingIDs
        let shouldCommit = dragging && dragRevision == store.mapRevision
        cancelDrag()
        if shouldCommit, var final = original {
            for index in final.topics.indices where ids.contains(final.topics[index].id) {
                final.topics[index].x += delta.x; final.topics[index].y += delta.y
            }
            store.apply(final, action: "Move branch")
        }
        viewportDidChange()
    }
    override func scrollWheel(with event: NSEvent) {
        finishEditing()
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            setZoom(scale * exp(event.scrollingDeltaY * 0.012), anchor: convert(event.locationInWindow, from: nil))
        } else {
            let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
            pan.x += event.scrollingDeltaX * multiplier; pan.y += event.scrollingDeltaY * multiplier; viewportDidChange()
        }
    }
    override func magnify(with event: NSEvent) { finishEditing(); setZoom(scale * (1 + event.magnification), anchor: convert(event.locationInWindow, from: nil)) }
    func setZoom(_ value: CGFloat, anchor: CGPoint? = nil) {
        let anchor = anchor ?? CGPoint(x: bounds.midX, y: bounds.midY); let original = world(anchor)
        scale = min(2.5, max(0.03, value)); pan = CGPoint(x: anchor.x - original.x * scale, y: anchor.y - original.y * scale)
        store.zoom = scale; viewportDidChange()
    }
    func restoreViewport(pan: CGPoint, scale: CGFloat) {
        finishEditing(); self.pan = pan; self.scale = scale; store.zoom = scale; viewportDidChange()
    }
    func center(on id: String) {
        guard let node = store.map.topic(id) else { return }
        pan = CGPoint(x: bounds.midX - node.x * scale, y: bounds.midY - node.y * scale); viewportDidChange()
    }
    func reveal(_ id: String) {
        guard let node = store.map.topic(id) else { return }
        if !bounds.insetBy(dx: 70, dy: 70).contains(rect(node)) { center(on: id) }
    }
    func fit(onlyShrink: Bool = false) {
        finishEditing()
        let union = prepareScene().bounds.insetBy(dx: -90, dy: -90)
        let fitted = min(1.1, max(0.03, min(bounds.width / union.width, bounds.height / union.height)))
        scale = onlyShrink ? min(scale, fitted) : fitted
        pan = CGPoint(x: bounds.midX - union.midX * scale, y: bounds.midY - union.midY * scale); store.zoom = scale; viewportDidChange()
    }
    func editSelected() {
        finishEditing()
        let node = store.selected
        let field = NSTextField(string: node.title); field.delegate = self
        field.font = node.font(scale: scale)
        field.alignment = node.appearance.alignment.native; field.isBordered = false; field.focusRingType = .none
        field.drawsBackground = false; field.backgroundColor = .clear; field.textColor = node.resolvedText
        field.attributedStringValue = NSAttributedString(string: node.title, attributes: node.textAttributes(scale: scale))
        field.cell?.wraps = true; field.cell?.isScrollable = false
        field.setAccessibilityLabel("Topic title")
        editor = field; editingID = node.id; addSubview(field); positionEditor()
        field.selectText(nil)
        if let textView = window?.fieldEditor(true, for: field) as? NSTextView { configureFieldEditor(textView) }
        needsDisplay = true
    }
    func positionEditor() {
        guard let editor, let id = editingID, let node = store.map.topic(id) else { return }
        let area = textRect(node)
        let lineHeight = node.font(scale: scale).ascender - node.font(scale: scale).descender + 4 * scale
        let measured = (editor.stringValue as NSString).boundingRect(with: area.size, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: node.textAttributes(scale: scale)).height + 4 * scale
        let height = min(area.height, max(lineHeight, measured))
        editor.frame = CGRect(x: area.minX, y: area.midY - height / 2, width: area.width, height: height)
    }
    func snapshotForSaving() -> MindMap {
        var map = store.map
        if let editor, let id = editingID, let index = map.topics.firstIndex(where: { $0.id == id }) {
            let text = editor.stringValue
            map.topics[index].title = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Idea" : String(text.prefix(10000))
        }
        return map
    }
    func finishEditing(cancel: Bool = false) {

        guard let editor, let id = editingID else { return }
        let value = editor.stringValue
        self.editor = nil; editingID = nil; editor.delegate = nil; editor.removeFromSuperview()
        if let (textView, drawsBackground, backgroundColor) = fieldEditorBackground {
            textView.drawsBackground = drawsBackground; textView.backgroundColor = backgroundColor
            fieldEditorBackground = nil
        }
        if !cancel { store.rename(id, title: value) }
        needsDisplay = true
    }
    func controlTextDidChange(_ obj: Notification) { positionEditor() }
    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let editor, let textView = (editor.currentEditor() ?? window?.fieldEditor(true, for: editor)) as? NSTextView else { return }
        configureFieldEditor(textView)
    }
    private func configureFieldEditor(_ textView: NSTextView) {
        if fieldEditorBackground == nil { fieldEditorBackground = (textView, textView.drawsBackground, textView.backgroundColor) }
        textView.drawsBackground = false; textView.backgroundColor = .clear
        textView.insertionPointColor = store.selected.resolvedText
        textView.typingAttributes = store.selected.textAttributes(scale: scale)
    }
    func controlTextDidEndEditing(_ obj: Notification) {
        finishEditing()
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) { finishEditing(cancel: true); window?.makeFirstResponder(self); return true }
        if selector == #selector(NSResponder.insertNewline(_:)) { finishEditing(); window?.makeFirstResponder(self); return true }
        if selector == #selector(NSResponder.insertTab(_:)) { finishEditing(); store.addChild(); return true }
        return false
    }
    override func keyDown(with event: NSEvent) {
        // SwiftUI can leave the hidden NSView as first responder briefly while
        // switching modes or presenting Search. Never edit through that stale focus.
        guard store.mode == .mindMap, !store.searchVisible else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 48: store.addChild()
        case 36, 76: store.addSibling()
        case 51, 117: store.deleteSelection()
        case 49: spaceDown = true; window?.invalidateCursorRects(for: self)
        case 53: finishEditing(cancel: true); store.selectedID = store.map.root.id; needsDisplay = true
        default:
            if event.charactersIgnoringModifiers == "e" { editSelected() }
            else { super.keyDown(with: event) }
        }
    }
    override func keyUp(with event: NSEvent) { if event.keyCode == 49 { spaceDown = false; window?.invalidateCursorRects(for: self) } else { super.keyUp(with: event) } }
    override func flagsChanged(with event: NSEvent) { super.flagsChanged(with: event) }
    override func accessibilityChildren() -> [Any]? {
        var elements: [Any] = []
        if let editor { elements.append(editor) }
        let scene = prepareScene()
        let visible = visibleNodes(in: visibleWorldRect, scene: scene)
        let validIDs = Set(visible.map { scene.nodes[$0].topic.id }).union(["handle-child", "handle-sibling"])
        accessibleNodes = accessibleNodes.filter { validIDs.contains($0.key) }
        for index in visible {
            let node = scene.nodes[index].topic
            let item = accessibleNodes[node.id] ?? CanvasAccessibleElement()
            accessibleNodes[node.id] = item
            item.setAccessibilityParent(self); item.setAccessibilityRole(.button); item.setAccessibilityEnabled(true); item.setAccessibilityLabel(node.title)
            item.setAccessibilityHelp("Click to select. Double-click to rename. Drag to move the branch.")
            item.setAccessibilityFrame(window?.convertToScreen(convert(rect(node).intersection(bounds), to: nil)) ?? .zero)
            item.press = { [weak self] in self?.store.select(node.id) }
            elements.append(item)
        }
        for handle in handles(store.selected) where handle.rect.intersects(bounds) {
            let key = handle.sibling ? "handle-sibling" : "handle-child"
            let item = accessibleNodes[key] ?? CanvasAccessibleElement()
            accessibleNodes[key] = item
            item.setAccessibilityParent(self); item.setAccessibilityRole(.button); item.setAccessibilityEnabled(true)
            item.setAccessibilityLabel(handle.sibling ? "Add sibling topic" : "Add child topic")
            item.setAccessibilityFrame(window?.convertToScreen(convert(handle.rect.intersection(bounds), to: nil)) ?? .zero)
            item.press = { [weak self] in if handle.sibling { self?.store.addSibling() } else { self?.store.addChild() } }
            elements.append(item)
        }
        return elements
    }
}
