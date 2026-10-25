import SwiftUI

struct OutlinerView: View {
    @ObservedObject var store: MapStore
    @State private var collapsed: Set<String> = []
    private var rows: [OutlineItem] {
        var hidden: Set<String> = []
        for id in collapsed { hidden.formUnion(store.map.descendants(of: id).subtracting([id])) }
        return store.outline.filter { !hidden.contains($0.id) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("OUTLINER").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.8).foregroundStyle(.secondary)
                    Text(store.activeSheet.title).font(.system(size: 24, weight: .semibold))
                }
                Spacer()
                Button { store.addChild() } label: { Label("Add topic", systemImage: "plus") }.controlSize(.small)
            }.padding(28)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(rows) { row in
                            OutlineRowView(store: store, row: row, collapsed: collapsed.contains(row.id), toggle: { if !collapsed.insert(row.id).inserted { collapsed.remove(row.id) } }).id(row.id)
                        }
                    }.padding(22)
                }.onChange(of: store.editingOutlineID) { _, id in if let id { collapsed.removeAll(); proxy.scrollTo(id, anchor: .center) } }
                .onChange(of: store.outlineRevealRequest) { _, request in
                    guard let request else { return }
                    collapsed.subtract(store.ancestorIDs(of: request.id))
                    DispatchQueue.main.async { proxy.scrollTo(request.id, anchor: .center) }
                }
            }
        }.background(Color(nsColor: Palette.background)).onChange(of: store.activeSheet.id) { _, _ in collapsed.removeAll() }
    }
}

private struct OutlineRowView: View {
    @ObservedObject var store: MapStore
    let row: OutlineItem
    let collapsed: Bool
    let toggle: () -> Void
    @FocusState private var focused: Bool
    @State private var draft = ""
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Button(action: toggle) { Image(systemName: collapsed ? "chevron.right" : "chevron.down").font(.system(size: 9, weight: .semibold)).frame(width: 16, height: 26).opacity(store.map.children(of: row.id).isEmpty ? 0 : 1) }.buttonStyle(.plain).accessibilityLabel("Collapse or expand \(row.node.title)")
            Circle().fill(Color(nsColor: Palette.color(row.node.color))).frame(width: 7, height: 7).padding(.top, 10)
            VStack(alignment: .leading, spacing: 5) {
                if store.editingOutlineID == row.id {
                    TextField("Topic title", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain).font(.system(size: row.depth == 0 ? 18 : 14, weight: row.node.appearance.bold ? .bold : .regular)).focused($focused)
                        .onAppear { draft = row.node.title; focused = true }.onSubmit { store.addSibling(row.id) }.onExitCommand { store.editingOutlineID = nil }
                        .onChange(of: draft) { _, value in if focused { store.rename(row.id, title: value) } }
                        .onKeyPress(.return, phases: .down) { _ in store.addSibling(row.id); return .handled }
                        .onKeyPress(.tab, phases: .down) { press in if press.modifiers.contains(.shift) { store.outdent(row.id) } else { store.indent(row.id) }; return .handled }
                        .accessibilityLabel("Outline title")
                } else {
                    Text(row.node.title).font(.system(size: row.depth == 0 ? 18 : 14, weight: row.node.appearance.bold ? .bold : .regular)).italic(row.node.appearance.italic).underline(row.node.appearance.underline).strikethrough(row.node.appearance.strikethrough).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
                        .onTapGesture { store.select(row.id); store.editingOutlineID = row.id }
                }
                if !row.node.note.isEmpty { Text(row.node.note).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button("Add child") { store.addChild(row.id) }
                Button("Add sibling") { store.addSibling(row.id) }
                Button("Indent") { store.indent(row.id) }
                Button("Outdent") { store.outdent(row.id) }
                if row.node.parentID != nil { Button("Delete branch") { store.select(row.id); store.deleteSelection() } }
            } label: { Image(systemName: "ellipsis").frame(width: 20, height: 23) }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Outline actions for \(row.node.title)")
        }.padding(.leading, CGFloat(min(row.depth, 12)) * 22 + 10).padding(.trailing, 10).padding(.vertical, 9)
        .background(store.selectedID == row.id ? Color(nsColor: Palette.purple).opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle()).onTapGesture { store.select(row.id) }
    }
}
