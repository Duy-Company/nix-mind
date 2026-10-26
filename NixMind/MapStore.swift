import AppKit
import Combine

enum EditorMode: String { case mindMap, outliner }
struct OutlineItem: Identifiable { let node: Topic; let depth: Int; var id: String { node.id } }
struct OutlineRevealRequest: Equatable { let id: String; let token = UUID() }

@MainActor final class CanvasViewport: ObservableObject {
    @Published var zoom = 1.0
}

@MainActor final class MapStore: ObservableObject {
    @Published var workbook: MindBook {
        didSet { mapRevision &+= 1; cachedOutline = nil; cachedTopicIndices = nil }
    }
    private(set) var mapRevision: UInt64 = 0
    private var cachedOutline: [OutlineItem]?
    private var cachedTopicIndices: [String: Int]?
    let viewport = CanvasViewport()
    @Published var selectedID: String
    @Published var mcpSettingsVisible = false
    @Published var searchVisible = false
    @Published var searchFocusRequest = UUID()
    @Published var outlineRevealRequest: OutlineRevealRequest?
    var zoom: Double { get { viewport.zoom } set { viewport.zoom = newValue } }
    @Published var sidebarVisible = true
    @Published var inspectorVisible = true
    @Published var mode = EditorMode.mindMap
    @Published var toast: String?
    @Published var editingOutlineID: String?
    weak var document: MapDocument?
    weak var canvas: MindMapCanvas?
    private var viewports: [String: (CGPoint, CGFloat)] = [:]
    init(map: MindMap = .blank()) { workbook = MindBook(map: map); selectedID = map.root.id }
    var map: MindMap { get { workbook.activeMap } set { workbook.activeMap = newValue } }
    var activeSheet: MapSheet { workbook.sheets[workbook.activeIndex] }
    private var topicIndices: [String: Int] {
        if let cachedTopicIndices { return cachedTopicIndices }
        let value = Dictionary(uniqueKeysWithValues: map.topics.indices.map { (map.topics[$0].id, $0) })
        cachedTopicIndices = value; return value
    }
    var selected: Topic { topicIndices[selectedID].map { map.topics[$0] } ?? map.root }
    var outline: [OutlineItem] {
        if let cachedOutline { return cachedOutline }
        let children = map.adjacency
        var rows: [OutlineItem] = []
        func visit(_ node: Topic, _ depth: Int) {
            rows.append(OutlineItem(node: node, depth: depth))
            for child in children[node.id] ?? [] { visit(child, depth + 1) }
        }
        visit(map.root, 0); cachedOutline = rows; return rows
    }
    func load(_ book: MindBook) {
        workbook = book; selectedID = book.activeMap.root.id; viewports = [:]
    }
    func applyBook(_ next: MindBook, action: String) {
        guard next != workbook else { return }
        let previous = workbook
        let manager = document?.undoManager
        manager?.beginUndoGrouping()
        manager?.registerUndo(withTarget: self) { store in store.applyBook(previous, action: action) }
        manager?.setActionName(action)
        manager?.endUndoGrouping()
        let changedSheet = workbook.activeSheetID != next.activeSheetID
        workbook = next
        if map.topic(selectedID) == nil { selectedID = map.root.id }
        if changedSheet { DispatchQueue.main.async { [weak self] in self?.canvas?.fit() } }
    }
    func apply(_ next: MindMap, action: String) {
        var book = workbook; book.activeMap = next; applyBook(book, action: action)
    }
    func applyAI(_ next: MindMap, sheetID: String? = nil) {
        var book = workbook
        if let id = sheetID, let index = book.sheets.firstIndex(where: { $0.id == id }) { book.sheets[index].map = next }
        else { book.activeMap = next }
        applyBook(book, action: "Apply MCP changes")
    }
    func switchSheet(_ id: String) {
        guard id != workbook.activeSheetID, workbook.sheets.contains(where: { $0.id == id }) else { return }
        canvas?.finishEditing()
        if let canvas { viewports[workbook.activeSheetID] = (canvas.pan, canvas.scale) }
        workbook.activeSheetID = id; selectedID = map.root.id; editingOutlineID = nil
        if let viewport = viewports[id] { canvas?.restoreViewport(pan: viewport.0, scale: viewport.1) }
        else { canvas?.fit() }
    }
    @discardableResult func addSheet(title: String? = nil) -> String {
        guard workbook.sheets.count < 500 else { showToast("This file has reached its sheet capacity."); return activeSheet.id }
        canvas?.finishEditing()
        let sheet = MapSheet(title: title ?? "Sheet \(workbook.sheets.count + 1)", map: .blank())
        var book = workbook; book.sheets.append(sheet); book.activeSheetID = sheet.id
        applyBook(book, action: "Add sheet"); selectedID = sheet.map.root.id; editingOutlineID = nil
        return sheet.id
    }
    func renameSheet(_ id: String, title: String) {
        let title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !title.isEmpty, let index = workbook.sheets.firstIndex(where: { $0.id == id }) else { return }
        var book = workbook; book.sheets[index].title = title
        applyBook(book, action: "Rename sheet")
    }
    func deleteSheet(_ id: String) {
        guard workbook.sheets.count > 1 else { showToast("Keep at least one sheet in this file."); return }
        canvas?.finishEditing()
        var book = workbook; book.sheets.removeAll { $0.id == id }
        if book.activeSheetID == id { book.activeSheetID = book.sheets[0].id }
        applyBook(book, action: "Delete sheet"); selectedID = map.root.id; editingOutlineID = nil
    }
    func select(_ id: String, center: Bool = false) {
        guard topicIndices[id] != nil else { return }
        canvas?.finishEditing(); selectedID = id
        if mode == .mindMap { if center { canvas?.center(on: id) }; canvas?.window?.makeFirstResponder(canvas) }
    }
    func showSearch() {
        canvas?.finishEditing(); editingOutlineID = nil
        canvas?.window?.makeFirstResponder(nil)
        searchVisible = true; searchFocusRequest = UUID()
    }
    func dismissSearch() {
        searchVisible = false
        if mode == .mindMap { canvas?.window?.makeFirstResponder(canvas) }
    }
    func ancestorIDs(of id: String) -> Set<String> {
        var result: Set<String> = [], parent = topicIndices[id].flatMap { map.topics[$0].parentID }
        while let id = parent, result.insert(id).inserted {
            parent = topicIndices[id].flatMap { map.topics[$0].parentID }
        }
        return result
    }
    @discardableResult func revealSearchResult(_ result: TopicSearchResult) -> Bool {
        guard let sheet = workbook.sheets.first(where: { $0.id == result.sheetID }), sheet.map.topic(result.topicID) != nil else {
            showToast("That topic changed. Search again for the latest results."); return false
        }
        canvas?.finishEditing(); switchSheet(result.sheetID)
        selectedID = result.topicID; editingOutlineID = nil
        dismissSearch()
        if mode == .outliner { outlineRevealRequest = OutlineRevealRequest(id: result.topicID) }
        else if let canvas {
            canvas.setZoom(max(0.75, canvas.scale)); canvas.center(on: result.topicID)
        }
        return true
    }
    func editSelected() {
        if mode == .outliner { editingOutlineID = selectedID }
        else { canvas?.editSelected() }
    }
    func addChild(_ id: String? = nil) { addTopic(parent: id ?? selectedID) }
    func addSibling(_ id: String? = nil) { let id = id ?? selectedID; addTopic(parent: map.topic(id)?.parentID ?? id) }
    private func addTopic(parent: String) {
        canvas?.finishEditing()
        var next = map
        guard let id = next.addChild(to: parent) else { showToast("This sheet has reached its document capacity."); return }
        apply(next, action: "Add topic"); selectedID = id
        if mode == .outliner { editingOutlineID = id }
        else { canvas?.editSelected() }
    }
    func rename(_ id: String, title: String) {
        var next = map
        guard let index = next.topics.firstIndex(where: { $0.id == id }) else { return }
        next.topics[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Idea" : String(title.prefix(10000))
        apply(next, action: "Rename topic")
    }
    func setNote(_ text: String) {
        var next = map
        guard let index = next.topics.firstIndex(where: { $0.id == selectedID }) else { return }
        next.topics[index].note = String(text.prefix(1_000_000)); apply(next, action: "Edit notes")
    }
    func setColor(_ color: Int) {
        var next = map; let ids = map.descendants(of: selectedID)
        for index in next.topics.indices where ids.contains(next.topics[index].id) { next.topics[index].color = color }
        apply(next, action: "Change branch color")
    }
    func setStyle(_ change: (inout TopicStyle) -> Void) {
        canvas?.finishEditing()
        var next = map
        guard let index = next.topics.firstIndex(where: { $0.id == selectedID }) else { return }
        var style = next.topics[index].appearance; change(&style)
        guard (try? style.validate()) != nil else { return }
        next.topics[index].style = style
        apply(next, action: "Format topic")
    }
    func setStructure(_ structure: NodeStructure) {
        canvas?.finishEditing()
        var next = map; let id = selectedID
        guard let index = next.topics.firstIndex(where: { $0.id == id }) else { return }
        next.topics[index].structure = structure; next.arrange()
        apply(next, action: "Change structure"); canvas?.fit(onlyShrink: true)
    }
    func arrange() {
        canvas?.finishEditing(); var next = map; next.arrange()
        apply(next, action: "Arrange sheet"); canvas?.fit()
    }
    func setMode(_ value: EditorMode) {
        canvas?.finishEditing(); editingOutlineID = nil; mode = value
        if value == .mindMap { canvas?.window?.makeFirstResponder(canvas) }
    }
    func deleteSelection() {
        canvas?.finishEditing()
        guard selectedID != map.root.id else { showToast("Keep the central topic. Rename it or start a new sheet."); return }
        let parent = selected.parentID!
        var next = map; next.remove(selectedID)
        apply(next, action: "Delete branch"); selectedID = parent; editingOutlineID = nil
    }
    func indent(_ id: String) {
        guard let node = map.topic(id), let parent = node.parentID else { return }
        let siblings = map.children(of: parent)
        guard let i = siblings.firstIndex(where: { $0.id == id }), i > 0 else { return }
        reparent(id, under: siblings[i - 1].id)
    }
    func outdent(_ id: String) {
        guard let parent = map.topic(id)?.parentID, let grandparent = map.topic(parent)?.parentID else { return }
        reparent(id, under: grandparent)
    }
    func reparent(_ id: String, under parent: String) {
        guard id != map.root.id, map.topic(parent) != nil, !map.descendants(of: id).contains(parent), let index = map.topics.firstIndex(where: { $0.id == id }) else { return }
        var next = map; next.topics[index].parentID = parent; next.topics[index].slot = nil
        guard (try? next.validate()) != nil else { showToast("This move exceeds the maximum topic depth."); return }
        next.arrange()
        apply(next, action: "Move topic in outline")
    }
    func showToast(_ message: String) {
        toast = message
        Task { try? await Task.sleep(for: .seconds(4)); if toast == message { toast = nil } }
    }
}
