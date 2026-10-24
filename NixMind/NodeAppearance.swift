import AppKit

// Optional on Topic so documents created before styling remain readable.
struct TopicStyle: Codable, Equatable {
    var fontFamily = "System"
    var fontSize = 16.0
    var bold = false
    var italic = false
    var underline = false
    var strikethrough = false
    var alignment = TextAlignment.center
    var shape = NodeShape.rounded
    var fillColor: String?
    var textColor: String?
    var borderColor: String?
    var borderWidth = 1.0

    static func standard(root: Bool) -> TopicStyle {
        var style = TopicStyle()
        if root { style.fontSize = 21; style.bold = true }
        return style
    }
    func validate() throws {
        guard fontSize.isFinite, (8...96).contains(fontSize), borderWidth.isFinite, (0...12).contains(borderWidth), !fontFamily.isEmpty, fontFamily.count <= 200,
              [fillColor, textColor, borderColor].allSatisfy({ $0 == nil || NSColor(hex: $0!) != nil }) else { throw MapError.invalid }
    }
}

enum TextAlignment: String, Codable, CaseIterable { case left, center, right
    var native: NSTextAlignment { switch self { case .left: return .left; case .center: return .center; case .right: return .right } }
}
enum NodeShape: String, Codable, CaseIterable { case rounded, rectangle, capsule, ellipse, diamond
    var title: String { switch self { case .rounded: return "Rounded rectangle"; case .rectangle: return "Rectangle"; case .capsule: return "Capsule"; case .ellipse: return "Ellipse"; case .diamond: return "Diamond" } }
}
enum NodeStructure: String, Codable, CaseIterable { case automatic, leftToRight, rightToLeft
    var title: String { switch self { case .automatic: return "Automatic"; case .leftToRight: return "Left to right"; case .rightToLeft: return "Right to left" } }
}

extension Topic {
    var appearance: TopicStyle { style ?? .standard(root: parentID == nil) }
    func font(scale: CGFloat = 1) -> NSFont {
        let style = appearance
        let size = CGFloat(style.fontSize) * scale
        let base = style.fontFamily == "System" ? NSFont.systemFont(ofSize: size) : (NSFont(descriptor: NSFontDescriptor().withFamily(style.fontFamily), size: size) ?? NSFont.systemFont(ofSize: size))
        var traits = base.fontDescriptor.symbolicTraits
        if style.bold { traits.insert(.bold) }; if style.italic { traits.insert(.italic) }
        return NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: size) ?? base
    }
    var layoutSize: CGSize {
        let font = font()
        let measured = (title as NSString).size(withAttributes: [.font: font]).width
        let width = min(460, max(parentID == nil ? 220 : 148, measured + 44))
        let text = (title as NSString).boundingRect(with: CGSize(width: width - 36, height: 2000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        var size = CGSize(width: width, height: max(parentID == nil ? 72 : 52, min(250, ceil(text.height) + 30)))
        if appearance.shape == .diamond { size.width *= 2; size.height *= 2 }
        if appearance.shape == .ellipse { size.width *= 1.5; size.height *= 1.5 }
        return size
    }
    var resolvedFill: NSColor { appearance.fillColor.flatMap(NSColor.init(hex:)) ?? (parentID == nil ? Palette.color(color) : Palette.fill(color)) }
    var resolvedText: NSColor { appearance.textColor.flatMap(NSColor.init(hex:)) ?? (parentID == nil ? .white : Palette.ink) }
    var resolvedBorder: NSColor { appearance.borderColor.flatMap(NSColor.init(hex:)) ?? Palette.color(color).withAlphaComponent(0.5) }
    func textAttributes(scale: CGFloat = 1) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = appearance.alignment.native; paragraph.lineBreakMode = .byWordWrapping
        var result: [NSAttributedString.Key: Any] = [.font: font(scale: scale), .foregroundColor: resolvedText, .paragraphStyle: paragraph]
        if appearance.underline { result[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if appearance.strikethrough { result[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        return result
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard (value.count == 6 || value.count == 8), let number = UInt64(value, radix: 16) else { return nil }
        let rgba = value.count == 6 ? (number << 8) | 255 : number
        self.init(srgbRed: CGFloat((rgba >> 24) & 255) / 255, green: CGFloat((rgba >> 16) & 255) / 255, blue: CGFloat((rgba >> 8) & 255) / 255, alpha: CGFloat(rgba & 255) / 255)
    }
    var hexString: String {
        let color = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X%02X", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()), Int((color.alphaComponent * 255).rounded()))
    }
}

enum Palette {
    static let ink = NSColor(srgbRed: 0.17, green: 0.18, blue: 0.23, alpha: 1)
    static let purple = NSColor(srgbRed: 0.43, green: 0.34, blue: 0.82, alpha: 1)
    static let background = NSColor(srgbRed: 0.98, green: 0.975, blue: 0.96, alpha: 1)
    static let colors: [NSColor] = [
        NSColor(srgbRed: 0.43, green: 0.34, blue: 0.82, alpha: 1), NSColor(srgbRed: 0.23, green: 0.57, blue: 0.47, alpha: 1),
        NSColor(srgbRed: 0.82, green: 0.48, blue: 0.26, alpha: 1), NSColor(srgbRed: 0.29, green: 0.53, blue: 0.76, alpha: 1),
        NSColor(srgbRed: 0.75, green: 0.39, blue: 0.51, alpha: 1), NSColor(srgbRed: 0.65, green: 0.57, blue: 0.28, alpha: 1)
    ]
    static func color(_ index: Int) -> NSColor { colors[((index % colors.count) + colors.count) % colors.count] }
    static func fill(_ index: Int) -> NSColor { color(index).blended(withFraction: 0.91, of: .white)! }
}
