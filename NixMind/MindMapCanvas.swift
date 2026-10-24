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
        subscription = store.objectWillChange.sink { [weak self] _ in self?.needsDisplay = true }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); window?.makeFirstResponder(self) }
    override func layout() {
        super.layout()
        if lastSize == .zero { pan = CGPoint(x: bounds.midX, y: bounds.midY) }
        else { pan.x += (bounds.width - lastSize.width) / 2; pan.y += (bounds.height - lastSize.height) / 2 }
        lastSize = bounds.size; positionEditor()
    }
    func screen(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x * scale + pan.x, y: point.y * scale + pan.y) }
    func world(_ point: CGPoint) -> CGPoint { CGPoint(x: (point.x - pan.x) / scale, y: (point.y - pan.y) / scale) }
    func nodeSize(_ node: Topic) -> CGSize { node.layoutSize }
    func rect(_ node: Topic) -> CGRect {
        let size = nodeSize(node); let p = screen(node.point)
        return CGRect(x: p.x - size.width * scale / 2, y: p.y - size.height * scale / 2, width: size.width * scale, height: size.height * scale)
    }
    struct Handle { var rect: CGRect; var sibling: Bool }
    func handles(_ node: Topic) -> [Handle] {
        let r = rect(node); let size: CGFloat = 23
        if node.parentID == nil {
            let x = (store.map.direction(of: node.id) > 0 ? r.maxX : r.minX) - size / 2
            return [Handle(rect: CGRect(x: x, y: r.minY - size / 2, width: size, height: size), sibling: false)]
        }
        let right = store.map.direction(of: node.id) > 0
        let x = (right ? r.maxX : r.minX) - size / 2
        return [Handle(rect: CGRect(x: x, y: r.minY - size / 2, width: size, height: size), sibling: false), Handle(rect: CGRect(x: x, y: r.maxY - size / 2, width: size, height: size), sibling: true)]
    }
    override func draw(_ dirtyRect: NSRect) {
        Palette.background.setFill(); bounds.fill()
        drawDots()
        for node in store.map.topics {
            guard let parentID = node.parentID, let parent = store.map.topic(parentID) else { continue }
            let a = rect(parent), b = rect(node)
            let right = node.x >= parent.x
            let start = CGPoint(x: right ? a.maxX : a.minX, y: a.midY)
            let end = CGPoint(x: right ? b.minX : b.maxX, y: b.midY)
            let bend = max(42 * scale, abs(end.x - start.x) * 0.5)
            let path = NSBezierPath(); path.move(to: start)
            path.curve(to: end, controlPoint1: CGPoint(x: start.x + (right ? bend : -bend), y: start.y), controlPoint2: CGPoint(x: end.x + (right ? -bend : bend), y: end.y))
            Palette.color(node.color).withAlphaComponent(0.55).setStroke(); path.lineWidth = 2.2 * scale; path.stroke()
        }
        for node in store.map.topics where rect(node).insetBy(dx: -30, dy: -30).intersects(bounds) { drawNode(node) }
        if let selected = store.map.topic(store.selectedID) {
            for handle in handles(selected) { drawHandle(handle, node: selected) }
        }
        discardCursorRects(); resetCursorRects()
    }
    func drawDots() {
        let spacing = 24 * scale
        guard spacing >= 10 else { return }
        let path = NSBezierPath()
        var x = pan.x.truncatingRemainder(dividingBy: spacing)
        while x < bounds.width {
            var y = pan.y.truncatingRemainder(dividingBy: spacing)
            while y < bounds.height {
                path.appendOval(in: CGRect(x: x, y: y, width: 1.5, height: 1.5)); y += spacing
            }
            x += spacing
        }
        NSColor(srgbRed: 0.83, green: 0.82, blue: 0.80, alpha: 0.6).setFill(); path.fill()
    }
    func shapePath(_ shape: NodeShape, rect: CGRect) -> NSBezierPath {
        switch shape {
        case .rounded: return NSBezierPath(roundedRect: rect, xRadius: 14 * scale, yRadius: 14 * scale)
        case .rectangle: return NSBezierPath(rect: rect)
        case .capsule: return NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        case .ellipse: return NSBezierPath(ovalIn: rect)
        case .diamond:
            let path = NSBezierPath(); path.move(to: CGPoint(x: rect.midX, y: rect.minY)); path.line(to: CGPoint(x: rect.maxX, y: rect.midY)); path.line(to: CGPoint(x: rect.midX, y: rect.maxY)); path.line(to: CGPoint(x: rect.minX, y: rect.midY)); path.close(); return path
        }
    }
    func textRect(_ node: Topic) -> CGRect {
        let r = rect(node)
        if node.appearance.shape == .diamond { return r.insetBy(dx: r.width * 0.25, dy: r.height * 0.25) }
        if node.appearance.shape == .ellipse { return r.insetBy(dx: r.width * 0.16, dy: r.height * 0.16) }
        return r.insetBy(dx: 18 * scale, dy: 12 * scale)
    }
    func drawNode(_ node: Topic) {
        let r = rect(node); let selected = node.id == store.selectedID
        let style = node.appearance
        let path = shapePath(style.shape, rect: r)
        if selected {
            let outer = shapePath(style.shape, rect: r.insetBy(dx: -5, dy: -5))
            Palette.purple.withAlphaComponent(0.13).setFill(); outer.fill()
        }
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.05); shadow.shadowBlurRadius = 10; shadow.shadowOffset = NSSize(width: 0, height: 3); shadow.set()
        node.resolvedFill.setFill(); path.fill()
        NSGraphicsContext.restoreGraphicsState()
        if style.borderWidth > 0 { node.resolvedBorder.setStroke(); path.lineWidth = style.borderWidth * scale; path.stroke() }
        if selected { Palette.purple.withAlphaComponent(0.65).setStroke(); path.lineWidth = 1.2; path.stroke() }
        if editingID != node.id {
            let attributes = node.textAttributes(scale: scale)
            let area = textRect(node)
            let textBounds = (node.title as NSString).boundingRect(with: area.size, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
            let drawRect = CGRect(x: area.minX, y: r.midY - min(area.height, textBounds.height) / 2, width: area.width, height: min(area.height, textBounds.height))
            (node.title as NSString).draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine], attributes: attributes)
        }
        if !node.note.isEmpty {
            node.resolvedText.withAlphaComponent(0.7).setFill()
            NSBezierPath(ovalIn: CGRect(x: r.maxX - 12 * scale, y: r.maxY - 12 * scale, width: 4 * scale, height: 4 * scale)).fill()
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
            for node in store.map.topics { addCursorRect(rect(node), cursor: .openHand) }
            if let selected = store.map.topic(store.selectedID) { for handle in handles(selected) { addCursorRect(handle.rect, cursor: .pointingHand) } }
        }
    }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let node = store.map.topic(store.selectedID), !spaceDown {
            for handle in handles(node) where handle.rect.insetBy(dx: -3, dy: -3).contains(p) {
                if handle.sibling { store.addSibling(node.id) } else { store.addChild(node.id) }; return
            }
        }
        finishEditing(); window?.makeFirstResponder(self)
        dragStart = p; panStart = pan; dragging = false; dragMap = nil; dragID = nil
        if !spaceDown, let node = store.map.topics.reversed().first(where: { rect($0).contains(p) }) {
            store.selectedID = node.id
            if event.clickCount == 2 { editSelected(); return }
            dragID = node.id; dragMap = store.map
        }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard editor == nil else { return }
        let p = convert(event.locationInWindow, from: nil)
        let dx = p.x - dragStart.x, dy = p.y - dragStart.y
        guard hypot(dx, dy) > 3 else { return }
        dragging = true
        if let id = dragID, var map = dragMap {
            map.moveSubtree(id, dx: dx / scale, dy: dy / scale); store.map = map
        } else { pan = CGPoint(x: panStart.x + dx, y: panStart.y + dy) }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if dragging, let original = dragMap {
            let final = store.map; store.map = original; store.apply(final, action: "Move branch")
        }
        dragID = nil; dragMap = nil; dragging = false
    }
    override func scrollWheel(with event: NSEvent) {
        finishEditing()
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            setZoom(scale * exp(event.scrollingDeltaY * 0.012), anchor: convert(event.locationInWindow, from: nil))
        } else {
            let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
            pan.x += event.scrollingDeltaX * multiplier; pan.y += event.scrollingDeltaY * multiplier; needsDisplay = true
        }
    }
    override func magnify(with event: NSEvent) { finishEditing(); setZoom(scale * (1 + event.magnification), anchor: convert(event.locationInWindow, from: nil)) }
    func setZoom(_ value: CGFloat, anchor: CGPoint? = nil) {
        let anchor = anchor ?? CGPoint(x: bounds.midX, y: bounds.midY); let original = world(anchor)
        scale = min(2.5, max(0.03, value)); pan = CGPoint(x: anchor.x - original.x * scale, y: anchor.y - original.y * scale)
        store.zoom = scale; positionEditor(); needsDisplay = true
    }
    func restoreViewport(pan: CGPoint, scale: CGFloat) {
        finishEditing(); self.pan = pan; self.scale = scale; store.zoom = scale; needsDisplay = true
    }
    func center(on id: String) {
        guard let node = store.map.topic(id) else { return }
        pan = CGPoint(x: bounds.midX - node.x * scale, y: bounds.midY - node.y * scale); needsDisplay = true
    }
    func reveal(_ id: String) {
        guard let node = store.map.topic(id) else { return }
        if !bounds.insetBy(dx: 70, dy: 70).contains(rect(node)) { center(on: id) }
    }
    func fit(onlyShrink: Bool = false) {
        finishEditing()
        let union = store.map.topics.reduce(CGRect.null) { total, node in
            let size = nodeSize(node)
            return total.union(CGRect(x: node.x - size.width / 2, y: node.y - size.height / 2, width: size.width, height: size.height))
        }.insetBy(dx: -90, dy: -90)
        let fitted = min(1.1, max(0.03, min(bounds.width / union.width, bounds.height / union.height)))
        scale = onlyShrink ? min(scale, fitted) : fitted
        pan = CGPoint(x: bounds.midX - union.midX * scale, y: bounds.midY - union.midY * scale); store.zoom = scale; needsDisplay = true
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
        let validIDs = Set(store.map.topics.map(\.id)).union(["handle-child", "handle-sibling"])
        accessibleNodes = accessibleNodes.filter { validIDs.contains($0.key) }
        for node in store.map.topics where rect(node).intersects(bounds) {
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
