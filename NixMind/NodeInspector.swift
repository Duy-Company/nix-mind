import SwiftUI
import AppKit

struct NodeInspector: View {
    @ObservedObject var store: MapStore
    private let accent = Color(nsColor: Palette.purple)
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                HStack { Text("TOPIC DETAILS").font(.system(size: 10, weight: .semibold)).tracking(1.3).foregroundStyle(.secondary); Spacer(); Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary) }
                InspectorTitle(store: store, node: store.selected)
                section("TEXT") {
                    Picker("Font", selection: style(\.fontFamily)) {
                        Text("System").tag("System")
                        ForEach(NSFontManager.shared.availableFontFamilies.sorted(), id: \.self) { Text($0).tag($0) }
                    }.accessibilityLabel("Font family")
                    Stepper(value: style(\.fontSize), in: 8...96, step: 1) { HStack { Text("Size"); Spacer(); Text("\(Int(store.selected.appearance.fontSize)) pt").monospacedDigit() } }.accessibilityLabel("Font size")
                    HStack(spacing: 7) {
                        formatButton("bold", "Bold", \.bold)
                        formatButton("italic", "Italic", \.italic)
                        formatButton("underline", "Underline", \.underline)
                        formatButton("strikethrough", "Strikethrough", \.strikethrough)
                    }
                    Picker("Alignment", selection: style(\.alignment)) {
                        Image(systemName: "text.alignleft").tag(TextAlignment.left)
                        Image(systemName: "text.aligncenter").tag(TextAlignment.center)
                        Image(systemName: "text.alignright").tag(TextAlignment.right)
                    }.pickerStyle(.segmented).accessibilityLabel("Text alignment")
                    ColorPicker("Text color", selection: color(\.textColor, fallback: store.selected.resolvedText), supportsOpacity: true)
                }
                section("APPEARANCE") {
                    Picker("Shape", selection: style(\.shape)) { ForEach(NodeShape.allCases, id: \.self) { Text($0.title).tag($0) } }.accessibilityLabel("Node shape")
                    ColorPicker("Fill", selection: color(\.fillColor, fallback: store.selected.resolvedFill), supportsOpacity: true).accessibilityLabel("Node fill")
                    ColorPicker("Border", selection: color(\.borderColor, fallback: store.selected.resolvedBorder), supportsOpacity: true).accessibilityLabel("Border color")
                    HStack { Text("Border width"); Spacer(); Text(String(format: "%.1f pt", store.selected.appearance.borderWidth)).monospacedDigit().foregroundStyle(.secondary) }
                    Slider(value: style(\.borderWidth), in: 0...12, step: 0.5).accessibilityLabel("Border width")
                    Button("Reset appearance") { let isRoot = store.selected.parentID == nil; store.setStyle { $0 = .standard(root: isRoot) } }.buttonStyle(.plain).foregroundStyle(accent)
                }
                section("STRUCTURE") {
                    Picker("Direction", selection: Binding(get: { store.selected.structure ?? .automatic }, set: { store.setStructure($0) })) {
                        ForEach(NodeStructure.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.accessibilityLabel("Branch structure")
                    Text("Controls child layout and the side of the + buttons.").font(.system(size: 10)).foregroundStyle(.secondary)
                    HStack(spacing: 9) {
                        Text("Branch").font(.system(size: 11))
                        Spacer()
                        ForEach(0..<6) { index in
                            Button { store.setColor(index) } label: { Circle().fill(Color(nsColor: Palette.color(index))).frame(width: 18, height: 18).overlay { if store.selected.color % 6 == index { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white) } } }.buttonStyle(.plain).accessibilityLabel("Branch color \(index + 1)")
                        }
                    }
                }
                section("NOTES") {
                    TextEditor(text: Binding(get: { store.selected.note }, set: { store.setNote($0) })).font(.system(size: 12)).scrollContentBackground(.hidden).padding(5).frame(height: 100).background(Color.black.opacity(0.025), in: RoundedRectangle(cornerRadius: 7)).accessibilityLabel("Topic notes")
                }
                HStack { Button("Add child") { store.addChild() }; Button("Add sibling") { store.addSibling() } }.controlSize(.small)
                if store.selected.parentID != nil { Button(role: .destructive) { store.deleteSelection() } label: { Label("Delete branch", systemImage: "trash") }.buttonStyle(.plain).foregroundStyle(.red) }
            }.font(.system(size: 11)).padding(20)
        }.background(.white)
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { Divider(); Text(title).font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary); content() }
    }
    private func style<Value>(_ key: WritableKeyPath<TopicStyle, Value>) -> Binding<Value> {
        Binding(get: { store.selected.appearance[keyPath: key] }, set: { value in store.setStyle { $0[keyPath: key] = value } })
    }
    private func color(_ key: WritableKeyPath<TopicStyle, String?>, fallback: NSColor) -> Binding<Color> {
        Binding(get: { Color(nsColor: store.selected.appearance[keyPath: key].flatMap(NSColor.init(hex:)) ?? fallback) }, set: { value in store.setStyle { $0[keyPath: key] = NSColor(value).hexString } })
    }
    private func formatButton(_ icon: String, _ title: String, _ key: WritableKeyPath<TopicStyle, Bool>) -> some View {
        let selected = store.selected.appearance[keyPath: key]
        return Button { store.setStyle { $0[keyPath: key].toggle() } } label: { Image(systemName: icon).font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity).frame(height: 29).background(selected ? accent.opacity(0.12) : Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 5)).foregroundStyle(selected ? accent : .primary) }.buttonStyle(.plain).help(title).accessibilityLabel(title).accessibilityValue(selected ? "On" : "Off")
    }
}

private struct InspectorTitle: View {
    @ObservedObject var store: MapStore
    let node: Topic
    @State private var draft = ""
    @FocusState private var focused: Bool
    var body: some View {
        TextField("Topic title", text: $draft, axis: .vertical).font(.system(size: 13, weight: .medium)).textFieldStyle(.plain).lineLimit(1...4).padding(10).background(Color.black.opacity(0.025), in: RoundedRectangle(cornerRadius: 7)).focused($focused)
            .onAppear { draft = node.title }.onChange(of: node.id) { _, _ in draft = node.title }
            .onChange(of: node.title) { _, value in if !focused { draft = value } }
            .onChange(of: draft) { _, value in if focused { store.rename(node.id, title: value) } }
            .onSubmit { focused = false }.accessibilityLabel("Topic title in inspector")
    }
}
