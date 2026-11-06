import AppKit

/// Stored on the child topic: this formats its incoming parent-to-child connection.
struct ConnectionStyle: Codable, Equatable {
    var shape = ConnectionShape.curved
    var pattern = ConnectionPattern.solid
    var width = 2.2
    var color: String?
    var start = ConnectionEnding.none
    var end = ConnectionEnding.none
    var label = ""
    var labelFontSize = 13.0
    var labelColor: String?
    var labelFontFamily: String?
    var labelBold: Bool?
    var labelItalic: Bool?
    var labelUnderline: Bool?
    var labelStrikethrough: Bool?
    var labelAlignment: TextAlignment?
    /// Content width in world points; nil fits the longest explicit line without wrapping.
    var labelWidth: Double?
    /// Content height in world points; nil grows to fit the wrapped text.
    var labelHeight: Double?
    static let labelWidthRange = 24.0...10000.0
    static let labelHeightRange = 8.0...10000.0

    var arrowPosition: ConnectionArrowPosition {
        get {
            switch (start, end) {
            case (.none, .none): return .none
            case (.arrow, .none): return .start
            case (.none, .arrow): return .end
            case (.arrow, .arrow): return .both
            }
        }
        set {
            start = newValue == .start || newValue == .both ? .arrow : .none
            end = newValue == .end || newValue == .both ? .arrow : .none
        }
    }

    var labelAppearance: TopicStyle {
        get {
            var text = TopicStyle()
            text.fontFamily = labelFontFamily ?? "System"; text.fontSize = labelFontSize
            text.bold = labelBold ?? false; text.italic = labelItalic ?? false
            text.underline = labelUnderline ?? false; text.strikethrough = labelStrikethrough ?? false
            text.alignment = labelAlignment ?? .center; text.textColor = labelColor
            return text
        }
        set {
            labelFontFamily = newValue.fontFamily; labelFontSize = newValue.fontSize
            labelBold = newValue.bold; labelItalic = newValue.italic
            labelUnderline = newValue.underline; labelStrikethrough = newValue.strikethrough
            labelAlignment = newValue.alignment; labelColor = newValue.textColor
        }
    }

    func validate() throws {
        guard width.isFinite, (0.5...12).contains(width), label.count <= 500,
              labelWidth == nil || (labelWidth!.isFinite && Self.labelWidthRange.contains(labelWidth!)),
              labelHeight == nil || (labelHeight!.isFinite && Self.labelHeightRange.contains(labelHeight!)),
              [color, labelColor].allSatisfy({ $0 == nil || NSColor(hex: $0!) != nil }) else { throw MapError.invalid }
        try labelAppearance.validate()
    }
    var naturalLabelWidth: Double {
        ceil((label as NSString).size(withAttributes: labelAppearance.textAttributes(color: Palette.ink)).width)
    }
    var fittedLabelHeight: Double {
        let text = NSAttributedString(string: label, attributes: labelAppearance.textAttributes(color: Palette.ink))
        return ceil(text.boundingRect(with: CGSize(width: CGFloat(labelWidth ?? max(1, naturalLabelWidth)), height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
    }
    func apply(to path: NSBezierPath) {
        path.lineWidth = width; path.lineCapStyle = .round; path.lineJoinStyle = .round
        let dash: [CGFloat]
        switch pattern {
        case .solid: dash = []
        case .dashed: dash = [width * 4, width * 3]
        case .dotted: dash = [0.01, width * 2.6]
        }
        path.setLineDash(dash, count: dash.count, phase: 0)
    }
}

enum ConnectionShape: String, Codable, CaseIterable {
    case curved, straight, orthogonal
    var title: String { switch self { case .curved: return "Curved"; case .straight: return "Straight"; case .orthogonal: return "Elbow" } }
}
enum ConnectionPattern: String, Codable, CaseIterable {
    case solid, dashed, dotted
    var title: String { switch self { case .solid: return "Solid"; case .dashed: return "Dashed"; case .dotted: return "Dotted" } }
}
enum ConnectionEnding: String, Codable, CaseIterable {
    case none, arrow
    var title: String { self == .none ? "None" : "Arrow" }
}
enum ConnectionArrowPosition: String, CaseIterable {
    case none, start, end, both
    var title: String {
        switch self {
        case .none: return "None"
        case .start: return "Start"
        case .end: return "End"
        case .both: return "Both ends"
        }
    }
}

extension Topic {
    var connectionAppearance: ConnectionStyle { connectionStyle ?? ConnectionStyle() }
    var resolvedConnectionColor: NSColor { connectionAppearance.color.flatMap(NSColor.init(hex:)) ?? Palette.color(color).withAlphaComponent(0.55) }
}
