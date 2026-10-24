import Foundation
import CoreGraphics

struct Topic: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var parentID: String?
    var title: String
    var note = ""
    var x: Double
    var y: Double
    var color: Int = 0
    var slot: Int?
    var style: TopicStyle?
    var structure: NodeStructure?
    var point: CGPoint { CGPoint(x: x, y: y) }
}

struct MindMap: Codable, Equatable {
    static let capacity = 50_000
    var version = 1
    var topics: [Topic]
    static func blank() -> MindMap { MindMap(topics: [Topic(title: "Central topic", x: 0, y: 0)]) }
    var root: Topic { topics.first(where: { $0.parentID == nil })! }
    func children(of id: String) -> [Topic] { topics.filter { $0.parentID == id } }
    func topic(_ id: String) -> Topic? { topics.first { $0.id == id } }
    var adjacency: [String: [Topic]] { Dictionary(grouping: topics.filter { $0.parentID != nil }, by: { $0.parentID! }) }
    func descendants(of id: String) -> Set<String> {
        let children = adjacency
        var result: Set<String> = [id]; var queue = [id]
        while let current = queue.popLast() {
            for child in children[current] ?? [] where result.insert(child.id).inserted { queue.append(child.id) }
        }
        return result
    }
    func direction(of id: String) -> Double {
        guard let node = topic(id) else { return 1 }
        switch node.structure ?? .automatic {
        case .leftToRight: return 1
        case .rightToLeft: return -1
        case .automatic:
            if let parent = node.parentID, parent != root.id { return direction(of: parent) }
            if root.structure == .leftToRight { return 1 }
            if root.structure == .rightToLeft { return -1 }
            return node.x < root.x ? -1 : 1
        }
    }
    // Used only as a fallback when importing old exchange files without positions.
    static let slots: [CGPoint] = [CGPoint(x: 300, y: -175), CGPoint(x: 330, y: 0), CGPoint(x: 300, y: 175), CGPoint(x: -300, y: -175), CGPoint(x: -330, y: 0), CGPoint(x: -300, y: 175)]
    @discardableResult mutating func addChild(to id: String) -> String? {
        guard let parent = topic(id), topics.count < Self.capacity else { return nil }
        var depth = 0, ancestor: Topic? = parent
        while let node = ancestor {
            depth += 1
            guard depth < 128 else { return nil }
            ancestor = node.parentID.flatMap { topic($0) }
        }
        let siblings = children(of: id)
        let rootChild = id == root.id
        let side: Double = rootChild && (parent.structure ?? .automatic) == .automatic ? (siblings.count.isMultiple(of: 2) ? 1 : -1) : direction(of: id)
        let node = Topic(parentID: id, title: rootChild ? "Branch \(siblings.count + 1)" : "New idea", x: parent.x + side * 300, y: parent.y + Double(siblings.count) * 90, color: rootChild ? siblings.count % 6 : parent.color, slot: rootChild ? siblings.count : nil)
        topics.append(node)
        arrange()
        return node.id
    }
    @discardableResult mutating func addSibling(to id: String) -> String? {
        addChild(to: topic(id)?.parentID ?? id)
    }
    mutating func moveSubtree(_ id: String, dx: Double, dy: Double) {
        let ids = descendants(of: id)
        for index in topics.indices where ids.contains(topics[index].id) { topics[index].x += dx; topics[index].y += dy }
    }
    mutating func remove(_ id: String) {
        guard id != root.id else { return }
        let ids = descendants(of: id); topics.removeAll { ids.contains($0.id) }
    }
    /// Deterministic, size-aware tree layout. It never shrinks a user's chosen font size.
    mutating func arrange(around requestedID: String? = nil) {
        let start = requestedID ?? root.id
        guard let startNode = topic(start) else { return }
        let children = adjacency
        let indices = Dictionary(uniqueKeysWithValues: topics.indices.map { (topics[$0].id, $0) })
        let sizes = Dictionary(uniqueKeysWithValues: topics.map { ($0.id, $0.layoutSize) })
        var heights: [String: Double] = [:]
        func height(_ id: String) -> Double {
            if let value = heights[id] { return value }
            let list = children[id] ?? []
            let value = max(sizes[id]!.height, list.reduce(0) { $0 + height($1.id) } + Double(max(0, list.count - 1)) * 36)
            heights[id] = value; return value
        }
        func place(_ id: String, _ center: CGPoint, _ inherited: Double) {
            let index = indices[id]!
            topics[index].x = center.x; topics[index].y = center.y
            let side: Double = topics[index].structure == .leftToRight ? 1 : (topics[index].structure == .rightToLeft ? -1 : inherited)
            let list = children[id] ?? []
            let total = list.reduce(0.0) { $0 + height($1.id) } + Double(max(0, list.count - 1)) * 36
            var top = center.y - total / 2
            for child in list {
                let h = height(child.id)
                let x = center.x + side * (sizes[id]!.width / 2 + sizes[child.id]!.width / 2 + 110)
                place(child.id, CGPoint(x: x, y: top + h / 2), side)
                top += h + 36
            }
        }
        if start != root.id { place(start, startNode.point, direction(of: start)); return }
        let list = children[start] ?? []
        let structure = startNode.structure ?? .automatic
        var left: [Topic] = [], right: [Topic] = []
        for (index, child) in list.enumerated() {
            let explicit = child.structure ?? .automatic
            let side: Double = structure == .leftToRight ? 1 : (structure == .rightToLeft ? -1 : (explicit == .leftToRight ? 1 : (explicit == .rightToLeft ? -1 : (index.isMultiple(of: 2) ? 1 : -1))))
            if side > 0 { right.append(child) } else { left.append(child) }
        }
        for (side, group) in [(-1.0, left), (1.0, right)] {
            let total = group.reduce(0.0) { $0 + height($1.id) } + Double(max(0, group.count - 1)) * 36
            var top = startNode.y - total / 2
            for child in group {
                let h = height(child.id)
                let x = startNode.x + side * (sizes[start]!.width / 2 + sizes[child.id]!.width / 2 + 120)
                place(child.id, CGPoint(x: x, y: top + h / 2), side)
                top += h + 36
            }
        }
    }
    func validate() throws {
        guard version == 1, !topics.isEmpty, topics.count <= Self.capacity, topics.filter({ $0.parentID == nil }).count == 1,
              Set(topics.map(\.id)).count == topics.count,
              topics.allSatisfy({ !$0.id.isEmpty && $0.x.isFinite && $0.y.isFinite && abs($0.x) < 100_000_000 && abs($0.y) < 100_000_000 && $0.title.count <= 10000 && $0.note.count <= 1_000_000 }) else { throw MapError.invalid }
        let ids = Set(topics.map(\.id))
        guard topics.allSatisfy({ $0.parentID == nil || ids.contains($0.parentID!) }) else { throw MapError.invalid }
        let children = adjacency
        var frontier = [root.id], visited: Set<String> = [], depth = 0
        while !frontier.isEmpty {
            guard depth < 128 else { throw MapError.invalid }
            var next: [String] = []
            for id in frontier {
                guard visited.insert(id).inserted else { throw MapError.invalid }
                next.append(contentsOf: (children[id] ?? []).map(\.id))
            }
            frontier = next; depth += 1
        }
        guard visited.count == topics.count else { throw MapError.invalid }
        for node in topics { try node.style?.validate() }
    }
}

struct MapSheet: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var title: String
    var map: MindMap
}
struct MindBook: Codable, Equatable {
    var version = 2
    var sheets: [MapSheet]
    var activeSheetID: String
    init(map: MindMap = .blank(), title: String = "Sheet 1") {
        let sheet = MapSheet(title: title, map: map); sheets = [sheet]; activeSheetID = sheet.id
    }
    var activeIndex: Int { sheets.firstIndex { $0.id == activeSheetID } ?? 0 }
    var activeMap: MindMap { get { sheets[activeIndex].map } set { sheets[activeIndex].map = newValue } }
    func validate() throws {
        guard version == 2, !sheets.isEmpty, sheets.count <= 500, Set(sheets.map(\.id)).count == sheets.count,
              sheets.contains(where: { $0.id == activeSheetID }), sheets.allSatisfy({ !$0.id.isEmpty && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.title.count <= 500 }) else { throw MapError.invalid }
        for sheet in sheets { try sheet.map.validate() }
    }
}

enum MapError: LocalizedError {
    case invalid, unsupported(String), archive
    var errorDescription: String? {
        switch self {
        case .invalid: return "This mind map is invalid or exceeds the document size limits."
        case .unsupported(let detail): return detail
        case .archive: return "Unable to read or create this mind map archive. A modern JSON-based archive is required."
        }
    }
}
