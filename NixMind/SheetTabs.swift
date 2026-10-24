import SwiftUI

struct SheetTabs: View {
    @ObservedObject var store: MapStore
    @State private var renaming: String?
    @State private var draft = ""
    @FocusState private var titleFocused: Bool
    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "square.stack.3d.up").font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(store.workbook.sheets) { sheet in
                        HStack(spacing: 8) {
                            if renaming == sheet.id {
                                TextField("Sheet name", text: $draft).textFieldStyle(.plain).font(.system(size: 12)).frame(width: 120).focused($titleFocused).onSubmit { commit() }.onExitCommand { renaming = nil }.accessibilityLabel("Sheet name")
                            } else {
                                Button { store.switchSheet(sheet.id) } label: { Text(sheet.title).font(.system(size: 12, weight: store.activeSheet.id == sheet.id ? .semibold : .regular)).lineLimit(1).frame(minWidth: 65, maxWidth: 170, alignment: .leading).padding(.vertical, 9).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel("Sheet tab \(sheet.title)")
                                    .simultaneousGesture(TapGesture(count: 2).onEnded { beginRename(sheet) })
                            }
                            if store.workbook.sheets.count > 1 {
                                Button { store.deleteSheet(sheet.id) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .semibold)).frame(width: 17, height: 22) }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Close sheet \(sheet.title)")
                            }
                        }.padding(.horizontal, 11).background(store.activeSheet.id == sheet.id ? Color(nsColor: Palette.purple).opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        .contextMenu { Button("Rename sheet…") { beginRename(sheet) }; Button("Delete sheet") { store.deleteSheet(sheet.id) }.disabled(store.workbook.sheets.count == 1) }
                    }
                }
            }
            Button { commit(); store.addSheet() } label: { Image(systemName: "plus").font(.system(size: 13, weight: .medium)).frame(width: 42, height: 38) }.buttonStyle(.plain).help("Add sheet").accessibilityLabel("Add sheet")
        }.frame(height: 44).background(Color(nsColor: NSColor(srgbRed: 0.985, green: 0.985, blue: 0.99, alpha: 1)))
        .onChange(of: draft) { _, value in if let id = renaming { store.renameSheet(id, title: value) } }
        .onChange(of: titleFocused) { _, focused in if !focused { commit() } }
    }
    private func beginRename(_ sheet: MapSheet) { renaming = sheet.id; draft = sheet.title; titleFocused = true }
    private func commit() { if let id = renaming { store.renameSheet(id, title: draft); renaming = nil } }
}
