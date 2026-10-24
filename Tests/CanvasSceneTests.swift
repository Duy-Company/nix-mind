import AppKit
import Combine

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
        }
        print("PASS: \(checks) canvas checks")
    }
}
