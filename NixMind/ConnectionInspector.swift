import SwiftUI
import AppKit

struct ConnectionInspector: View {
    @ObservedObject var store: MapStore
    let node: Topic
    private let accent = Color(nsColor: Palette.purple)
    private var appearance: ConnectionStyle { node.connectionAppearance }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("CONNECTION DETAILS").font(.system(size: 10, weight: .semibold)).tracking(1.3).foregroundStyle(.secondary)
            if let parentID = node.parentID, let parent = store.map.topic(parentID) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(parent.title).lineLimit(2).foregroundStyle(.secondary)
                    Label(node.title, systemImage: "arrow.turn.down.right").lineLimit(2)
                }.font(.system(size: 12)).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.black.opacity(0.025), in: RoundedRectangle(cornerRadius: 7))
                section("LINE") {
                    Picker("Shape", selection: style(\.shape)) {
                        ForEach(ConnectionShape.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.accessibilityLabel("Connection shape")
                    Picker("Pattern", selection: style(\.pattern)) {
                        ForEach(ConnectionPattern.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.accessibilityLabel("Connection pattern")
                    HStack { Text("Width"); Spacer(); Text(String(format: "%.1f pt", appearance.width)).monospacedDigit().foregroundStyle(.secondary) }
                    Slider(value: style(\.width), in: 0.5...12, step: 0.5).accessibilityLabel("Connection width")
                    ColorPicker("Line color", selection: color(\.color, fallback: node.resolvedConnectionColor), supportsOpacity: true).accessibilityLabel("Connection color")
                    if appearance.color != nil {
                        Button("Use branch color") { store.setConnectionStyle { $0.color = nil } }.buttonStyle(.plain).foregroundStyle(accent)
                    }
                    Picker("Start", selection: style(\.start)) {
                        ForEach(ConnectionEnding.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.accessibilityLabel("Connection start")
                    Picker("End", selection: style(\.end)) {
                        ForEach(ConnectionEnding.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.accessibilityLabel("Connection end")
                }
                section("LABEL") {
                    TextField("Connection text", text: style(\.label), axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(1...5).accessibilityLabel("Connection label")
                    Toggle("Fit text automatically", isOn: Binding(get: { appearance.labelWidth == nil && appearance.labelHeight == nil }, set: { fit in
                        store.setConnectionStyle {
                            $0.labelWidth = fit ? nil : min(ConnectionStyle.labelWidthRange.upperBound, max(ConnectionStyle.labelWidthRange.lowerBound, $0.naturalLabelWidth))
                            $0.labelHeight = fit ? nil : min(ConnectionStyle.labelHeightRange.upperBound, max(ConnectionStyle.labelHeightRange.lowerBound, $0.fittedLabelHeight))
                        }
                    })).accessibilityLabel("Automatically fit connection text box")
                    if appearance.labelWidth != nil {
                        Stepper(value: Binding(get: { appearance.labelWidth ?? 180 }, set: { value in store.setConnectionStyle { $0.labelWidth = value } }), in: ConnectionStyle.labelWidthRange, step: 10) {
                            HStack { Text("Box width"); Spacer(); Text("\(Int(appearance.labelWidth!)) pt").monospacedDigit() }
                        }.accessibilityLabel("Connection text box width")
                    }
                    if appearance.labelHeight != nil {
                        Stepper(value: Binding(get: { appearance.labelHeight ?? 24 }, set: { value in store.setConnectionStyle { $0.labelHeight = value } }), in: ConnectionStyle.labelHeightRange, step: 10) {
                            HStack { Text("Box height"); Spacer(); Text("\(Int(appearance.labelHeight!)) pt").monospacedDigit() }
                        }.accessibilityLabel("Connection text box height")
                    }
                    Text("Drag a side to resize one dimension, or a corner to resize both. Fit text automatically resets the box.").font(.system(size: 10)).foregroundStyle(.secondary)
                    Picker("Font", selection: textStyle(\.fontFamily)) {
                        Text("System").tag("System")
                        ForEach(NSFontManager.shared.availableFontFamilies.sorted(), id: \.self) { Text($0).tag($0) }
                    }.accessibilityLabel("Connection label font family")
                    Stepper(value: textStyle(\.fontSize), in: 8...96, step: 1) {
                        HStack { Text("Size"); Spacer(); Text("\(Int(appearance.labelFontSize)) pt").monospacedDigit() }
                    }.accessibilityLabel("Connection label size")
                    HStack(spacing: 7) {
                        formatButton("bold", "Bold", \.bold)
                        formatButton("italic", "Italic", \.italic)
                        formatButton("underline", "Underline", \.underline)
                        formatButton("strikethrough", "Strikethrough", \.strikethrough)
                    }
                    Picker("Alignment", selection: textStyle(\.alignment)) {
                        Image(systemName: "text.alignleft").tag(TextAlignment.left)
                        Image(systemName: "text.aligncenter").tag(TextAlignment.center)
                        Image(systemName: "text.alignright").tag(TextAlignment.right)
                    }.pickerStyle(.segmented).accessibilityLabel("Connection label alignment")
                    ColorPicker("Text color", selection: color(\.labelColor, fallback: Palette.ink), supportsOpacity: true).accessibilityLabel("Connection label color")
                    Button("Reset text style") { store.setConnectionStyle { $0.labelAppearance = ConnectionStyle().labelAppearance } }.buttonStyle(.plain).foregroundStyle(accent)
                    Text("Enter any text (up to 500 characters). Clear it to remove the label.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Button("Reset connection") { store.setConnectionStyle { $0 = ConnectionStyle() } }.buttonStyle(.plain).foregroundStyle(accent)
                Text("Changes apply to this connection only.").font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Text("Select a line or a child topic to style its connection. The central topic has no incoming connection.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider(); Text(title).font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary); content()
        }
    }
    private func style<Value>(_ key: WritableKeyPath<ConnectionStyle, Value>) -> Binding<Value> {
        Binding(get: { appearance[keyPath: key] }, set: { value in store.setConnectionStyle { $0[keyPath: key] = value } })
    }
    private func color(_ key: WritableKeyPath<ConnectionStyle, String?>, fallback: NSColor) -> Binding<Color> {
        Binding(get: { Color(nsColor: appearance[keyPath: key].flatMap(NSColor.init(hex:)) ?? fallback) }, set: { value in store.setConnectionStyle { $0[keyPath: key] = NSColor(value).hexString } })
    }
    private func textStyle<Value>(_ key: WritableKeyPath<TopicStyle, Value>) -> Binding<Value> {
        Binding(get: { appearance.labelAppearance[keyPath: key] }, set: { value in store.setConnectionStyle { $0.labelAppearance[keyPath: key] = value } })
    }
    private func formatButton(_ icon: String, _ title: String, _ key: WritableKeyPath<TopicStyle, Bool>) -> some View {
        let selected = appearance.labelAppearance[keyPath: key]
        return Button { store.setConnectionStyle { $0.labelAppearance[keyPath: key].toggle() } } label: {
            Image(systemName: icon).font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity).frame(height: 29)
                .background(selected ? accent.opacity(0.12) : Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(selected ? accent : .primary)
        }.buttonStyle(.plain).help(title).accessibilityLabel("Connection label \(title.lowercased())").accessibilityValue(selected ? "On" : "Off")
    }
}
