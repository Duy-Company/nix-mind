import AppKit

/// A bounding-volume tree: each rectangle is stored once, including very long links.
/// Pan/zoom queries visit intersecting branches instead of scanning every topic.
struct CanvasSpatialIndex {
    private struct Branch {
        let bounds: CGRect
        let range: Range<Int>
        var left = -1
        var right = -1
    }
    private let rectangles: [CGRect]
    private var order: [Int]
    private var branches: [Branch] = []
    init(_ rectangles: [CGRect]) {
        self.rectangles = rectangles; order = Array(rectangles.indices)
        if !order.isEmpty { _ = build(order.startIndex..<order.endIndex) }
    }
    private mutating func build(_ range: Range<Int>) -> Int {
        let bounds = order[range].reduce(CGRect.null) { $0.union(rectangles[$1]) }
        let index = branches.count
        branches.append(Branch(bounds: bounds, range: range))
        if range.count > 12 {
            let boxes = rectangles, horizontal = bounds.width >= bounds.height
            let sorted = order[range].sorted { horizontal ? boxes[$0].midX < boxes[$1].midX : boxes[$0].midY < boxes[$1].midY }
            order.replaceSubrange(range, with: sorted)
            let middle = range.lowerBound + range.count / 2
            let left = build(range.lowerBound..<middle)
            let right = build(middle..<range.upperBound)
            branches[index].left = left; branches[index].right = right
        }
        return index
    }
    func query(_ rect: CGRect) -> [Int] {
        guard !branches.isEmpty, !rect.isNull else { return [] }
        var stack = [0], result: [Int] = []
        while let index = stack.popLast() {
            let branch = branches[index]
            guard branch.bounds.intersects(rect) else { continue }
            if branch.left >= 0 { stack.append(branch.left); stack.append(branch.right) }
            else {
                for offset in branch.range where rectangles[order[offset]].intersects(rect) { result.append(order[offset]) }
            }
        }
        return result
    }
}

@MainActor final class CanvasTextLayout {
    let title: String
    let style: TopicStyle
    let isRoot: Bool
    let size: CGSize
    let text: NSAttributedString
    let textRect: CGRect // Relative to the topic's upper-left corner, in world coordinates.
    init(_ topic: Topic) {
        title = topic.title; style = topic.appearance; isRoot = topic.parentID == nil
        size = topic.layoutSize
        text = NSAttributedString(string: topic.title, attributes: topic.textAttributes())
        let box = CGRect(origin: .zero, size: size)
        let area: CGRect
        switch style.shape {
        case .diamond: area = box.insetBy(dx: box.width * 0.25, dy: box.height * 0.25)
        case .ellipse: area = box.insetBy(dx: box.width * 0.16, dy: box.height * 0.16)
        default: area = box.insetBy(dx: 18, dy: 12)
        }
        let height = min(area.height, ceil(text.boundingRect(with: area.size, options: [.usesLineFragmentOrigin, .usesFontLeading]).height))
        textRect = CGRect(x: area.minX, y: box.midY - height / 2, width: area.width, height: height)
    }
    func matches(_ topic: Topic) -> Bool { title == topic.title && style == topic.appearance && isRoot == (topic.parentID == nil) }
}

@MainActor struct CanvasRenderNode {
    let topic: Topic
    let layout: CanvasTextLayout
    let bounds: CGRect
    let path: NSBezierPath
    let fill: NSColor
    let border: NSColor
    let textColor: NSColor
}

@MainActor struct CanvasRenderEdge {
    let parentID: String
    let childID: String
    let start: CGPoint
    let end: CGPoint
    let path: NSBezierPath
    let bounds: CGRect
    let color: NSColor
    let style: ConnectionStyle
    let markers: [NSBezierPath]
    let label: NSAttributedString?
    let labelRect: CGRect
    let labelTextRect: CGRect

    init(parentID: String, childID: String, start: CGPoint, end: CGPoint, style: ConnectionStyle, color: NSColor, label: NSAttributedString? = nil, right: Bool? = nil) {
        self.parentID = parentID; self.childID = childID; self.start = start; self.end = end; self.style = style; self.color = color
        let right = right ?? (end.x >= start.x)
        path = CanvasScene.connection(from: start, to: end, right: right, shape: style.shape)
        style.apply(to: path)
        let delta = CGPoint(x: end.x - start.x, y: end.y - start.y)
        let tangent: CGPoint
        if style.shape == .curved { tangent = CGPoint(x: right ? 1 : -1, y: 0) }
        else if style.shape == .straight || delta.x == 0 { tangent = delta }
        else { tangent = CGPoint(x: delta.x >= 0 ? 1 : -1, y: 0) }
        var endings: [NSBezierPath] = []
        func arrow(at tip: CGPoint, direction: CGPoint) -> NSBezierPath {
            let length = hypot(direction.x, direction.y)
            let unit = length > 0 ? CGPoint(x: direction.x / length, y: direction.y / length) : CGPoint(x: 1, y: 0)
            let size = max(9, style.width * 3)
            let base = CGPoint(x: tip.x - unit.x * size, y: tip.y - unit.y * size)
            let arrow = NSBezierPath(); arrow.move(to: tip)
            arrow.line(to: CGPoint(x: base.x - unit.y * size * 0.45, y: base.y + unit.x * size * 0.45))
            arrow.line(to: CGPoint(x: base.x + unit.y * size * 0.45, y: base.y - unit.x * size * 0.45)); arrow.close()
            return arrow
        }
        if style.start == .arrow { endings.append(arrow(at: start, direction: CGPoint(x: -tangent.x, y: -tangent.y))) }
        if style.end == .arrow { endings.append(arrow(at: end, direction: tangent)) }
        markers = endings
        if style.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { self.label = nil; labelRect = .null; labelTextRect = .null }
        else {
            let text = label ?? NSAttributedString(string: style.label, attributes: style.labelAppearance.textAttributes(color: style.labelColor.flatMap(NSColor.init(hex:)) ?? Palette.ink))
            self.label = text
            let natural = text.boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
            let contentWidth = style.labelWidth.map { CGFloat($0) } ?? max(1, ceil(natural.width))
            let textHeight = ceil(style.labelWidth == nil ? natural.height : text.boundingRect(with: CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
            let contentHeight = style.labelHeight.map { CGFloat($0) } ?? textHeight
            labelRect = CGRect(x: (start.x + end.x) / 2 - contentWidth / 2 - 7, y: (start.y + end.y) / 2 - contentHeight / 2 - 4, width: contentWidth + 14, height: contentHeight + 8)
            let visibleHeight = min(contentHeight, textHeight)
            labelTextRect = CGRect(x: labelRect.minX + 7, y: labelRect.midY - visibleHeight / 2, width: contentWidth, height: visibleHeight)
        }
        var box = path.controlPointBounds.insetBy(dx: -style.width / 2 - 1, dy: -style.width / 2 - 1)
        for marker in markers { box = box.union(marker.bounds) }
        bounds = box.union(labelRect)
    }

    func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        if labelRect.contains(point) || markers.contains(where: { $0.contains(point) }) { return true }
        return path.cgPath.copy(strokingWithWidth: max(style.width, tolerance * 2), lineCap: .round, lineJoin: .round, miterLimit: 10).contains(point)
    }
}

@MainActor final class CanvasScene {
    private(set) var nodes: [CanvasRenderNode] = []
    private(set) var edges: [CanvasRenderEdge] = []
    private(set) var byID: [String: Int] = [:]
    private(set) var incomingEdge: [String: Int] = [:]
    private(set) var bounds = CGRect.null
    private(set) var measuredTextCount = 0
    private(set) var nodeIndex = CanvasSpatialIndex([])
    private(set) var edgeIndex = CanvasSpatialIndex([])
    let root: Topic
    init(map: MindMap, previous: CanvasScene? = nil) {
        root = map.root
        nodes.reserveCapacity(map.topics.count)
        for topic in map.topics {
            let old = previous?.node(topic.id)?.layout
            let layout: CanvasTextLayout
            if let old, old.matches(topic) { layout = old }
            else { layout = CanvasTextLayout(topic); measuredTextCount += 1 }
            let rect = CGRect(x: topic.x - layout.size.width / 2, y: topic.y - layout.size.height / 2, width: layout.size.width, height: layout.size.height)
            byID[topic.id] = nodes.count
            nodes.append(CanvasRenderNode(topic: topic, layout: layout, bounds: rect, path: Self.shapePath(topic.appearance.shape, rect: rect), fill: topic.resolvedFill, border: topic.resolvedBorder, textColor: topic.resolvedText))
            bounds = bounds.union(rect)
        }
        for child in nodes {
            guard let parentID = child.topic.parentID, let parent = node(parentID) else { continue }
            let right = child.topic.x >= parent.topic.x
            let start = CGPoint(x: right ? parent.bounds.maxX : parent.bounds.minX, y: parent.bounds.midY)
            let end = CGPoint(x: right ? child.bounds.minX : child.bounds.maxX, y: child.bounds.midY)
            incomingEdge[child.topic.id] = edges.count
            let style = child.topic.connectionAppearance
            let old = previous?.incomingEdge[child.topic.id].map { previous!.edges[$0] }
            let edge = CanvasRenderEdge(parentID: parentID, childID: child.topic.id, start: start, end: end, style: style, color: child.topic.resolvedConnectionColor, label: old?.style == style ? old?.label : nil, right: right)
            edges.append(edge); bounds = bounds.union(edge.bounds)
        }
        nodeIndex = CanvasSpatialIndex(nodes.map(\.bounds))
        edgeIndex = CanvasSpatialIndex(edges.map(\.bounds))
    }
    func node(_ id: String) -> CanvasRenderNode? { byID[id].map { nodes[$0] } }
    func direction(of id: String) -> Double {
        guard var topic = node(id)?.topic else { return 1 }
        while true {
            if topic.structure == .leftToRight { return 1 }
            if topic.structure == .rightToLeft { return -1 }
            if let parent = topic.parentID, parent != root.id, let ancestor = node(parent)?.topic { topic = ancestor; continue }
            if root.structure == .leftToRight { return 1 }
            if root.structure == .rightToLeft { return -1 }
            return topic.x < root.x ? -1 : 1
        }
    }
    static func connection(from start: CGPoint, to end: CGPoint, right: Bool, shape: ConnectionShape = .curved) -> NSBezierPath {
        let bend = max(42, abs(end.x - start.x) * 0.5)
        let path = NSBezierPath(); path.move(to: start)
        switch shape {
        case .curved:
            path.curve(to: end, controlPoint1: CGPoint(x: start.x + (right ? bend : -bend), y: start.y), controlPoint2: CGPoint(x: end.x + (right ? -bend : bend), y: end.y))
        case .straight: path.line(to: end)
        case .orthogonal:
            let middle = (start.x + end.x) / 2
            path.line(to: CGPoint(x: middle, y: start.y)); path.line(to: CGPoint(x: middle, y: end.y)); path.line(to: end)
        }
        return path
    }
    static func shapePath(_ shape: NodeShape, rect: CGRect, radius: CGFloat = 14) -> NSBezierPath {
        switch shape {
        case .rounded: return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        case .rectangle: return NSBezierPath(rect: rect)
        case .capsule: return NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        case .ellipse: return NSBezierPath(ovalIn: rect)
        case .diamond:
            let path = NSBezierPath(); path.move(to: CGPoint(x: rect.midX, y: rect.minY)); path.line(to: CGPoint(x: rect.maxX, y: rect.midY)); path.line(to: CGPoint(x: rect.midX, y: rect.maxY)); path.line(to: CGPoint(x: rect.minX, y: rect.midY)); path.close(); return path
        }
    }
}
