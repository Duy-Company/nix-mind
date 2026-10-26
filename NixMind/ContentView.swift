import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var store: MapStore
    @ObservedObject private var mcp = MCPState.shared
    private let accent = Color(nsColor: Palette.purple)
    var body: some View {
        ZStack {
            editor.disabled(store.searchVisible).accessibilityHidden(store.searchVisible)
            if store.searchVisible { TopicSearchPopup(store: store).transition(.opacity).zIndex(1) }
        }.animation(.easeOut(duration: 0.16), value: store.searchVisible)
    }
    private var editor: some View {
        VStack(spacing: 0) {
            header
            Divider()
            SheetTabs(store: store)
            Divider()
            HSplitView {
                if store.sidebarVisible {
                    sidebar.frame(minWidth: 180, idealWidth: 230, maxWidth: 600, maxHeight: .infinity)
                }
                ZStack(alignment: .bottom) {
                    CanvasHost(store: store).opacity(store.mode == .mindMap ? 1 : 0).allowsHitTesting(store.mode == .mindMap).accessibilityHidden(store.mode != .mindMap).clipped()
                    if store.mode == .outliner { OutlinerView(store: store) }
                    if store.mode == .mindMap {
                        VStack(spacing: 12) {
                            if let toast = store.toast { Text(toast).font(.system(size: 12)).padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)) }
                            CanvasZoomControls(store: store, viewport: store.viewport)
                        }.padding(.bottom, 24)
                    }
                }.frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity).layoutPriority(1).clipped()
                if store.inspectorVisible {
                    NodeInspector(store: store).frame(minWidth: 260, idealWidth: 300, maxWidth: 680, maxHeight: .infinity)
                }
            }
            Divider()
            footer
        }
        .background(.white).foregroundStyle(Color(nsColor: Palette.ink))
        .frame(minWidth: 1080, minHeight: 700)
        .sheet(isPresented: $store.mcpSettingsVisible) { MCPSettings() }
        .preferredColorScheme(.light).environment(\.locale, Locale(identifier: "en"))
    }
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 22)).foregroundStyle(accent).frame(width: 36, height: 36).background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("nix mind").font(.system(size: 17, weight: .bold, design: .rounded))
                Text("A little room for big ideas.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            iconButton("sidebar.left", store.sidebarVisible ? "Hide topics sidebar" : "Show topics sidebar") { store.canvas?.finishEditing(); store.sidebarVisible.toggle() }
            Spacer()
            iconButton("magnifyingglass", "Search topics ⌘F") { store.showSearch() }
            iconButton("arrow.uturn.backward", "Undo ⌘Z") { store.document?.undoManager?.undo() }.disabled(!(store.document?.undoManager?.canUndo ?? false))
            iconButton("arrow.uturn.forward", "Redo ⇧⌘Z") { store.document?.undoManager?.redo() }.disabled(!(store.document?.undoManager?.canRedo ?? false))
            Divider().frame(height: 22).padding(.horizontal, 6)
            Button { store.arrange() } label: { Label("Arrange", systemImage: "arrow.triangle.branch").font(.system(size: 12)) }.buttonStyle(.plain).padding(.horizontal, 8)
            Button { store.addChild() } label: { Label("Add topic", systemImage: "plus").font(.system(size: 12, weight: .medium)).padding(.horizontal, 13).padding(.vertical, 9) }.buttonStyle(.plain).foregroundStyle(accent).background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            iconButton("sidebar.right", store.inspectorVisible ? "Hide inspector" : "Show inspector") { store.canvas?.finishEditing(); store.inspectorVisible.toggle() }
            Button { store.document?.save(nil) } label: { Label("Save", systemImage: "square.and.arrow.down").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 16).padding(.vertical, 9) }.buttonStyle(.plain).foregroundStyle(.white).background(accent, in: RoundedRectangle(cornerRadius: 8))
        }.padding(.horizontal, 22).frame(height: 68)
    }
    private func iconButton(_ image: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: image).font(.system(size: 14)).frame(width: 30, height: 30).contentShape(Rectangle()) }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("TOPICS").font(.system(size: 10, weight: .semibold)).tracking(1.3).foregroundStyle(.secondary); Spacer(); Text("\(store.map.topics.count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(accent) }.padding(20)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(store.outline) { row in
                        Button { store.select(row.id, center: true) } label: {
                            HStack(spacing: 8) {
                                Circle().fill(Color(nsColor: Palette.color(row.node.color))).frame(width: row.depth == 0 ? 9 : 6, height: row.depth == 0 ? 9 : 6)
                                Text(row.node.title).font(.system(size: 12, weight: row.depth == 0 ? .semibold : .regular)).lineLimit(1)
                                Spacer(minLength: 0)
                            }.padding(.leading, 12 + CGFloat(min(row.depth, 5)) * 10).padding(.trailing, 8).frame(height: 33).contentShape(Rectangle())
                        }.buttonStyle(.plain).background(store.selectedID == row.id ? accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 7)).accessibilityLabel("Select \(row.node.title)")
                    }
                }.padding(.horizontal, 10)
            }
            Spacer(minLength: 15)
            VStack(alignment: .leading, spacing: 11) {
                Label("Room to grow", systemImage: "sparkle").font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
                Text("Add as many branches as you need. Your map arranges itself while your view stays in place.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                Divider()
                shortcut("Add child", "Tab"); shortcut("Add sibling", "↵"); shortcut("Rename", "E")
            }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 12)).padding(13)
            HStack {
                Button { NSDocumentController.shared.newDocument(nil) } label: { Label("New", systemImage: "doc.badge.plus") }
                Spacer()
                Button { NSDocumentController.shared.openDocument(nil) } label: { Label("Open", systemImage: "folder") }
            }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.bottom, 20)
        }.background(Color(nsColor: NSColor(srgbRed: 0.97, green: 0.97, blue: 0.975, alpha: 1)))
    }
    private func shortcut(_ text: String, _ key: String) -> some View {
        HStack { Text(text); Spacer(); Text(key).font(.system(size: 10, design: .monospaced)).padding(3).background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 4)) }.font(.system(size: 11)).foregroundStyle(.secondary)
    }
    private var footer: some View {
        HStack(spacing: 12) {
            Text("Local file").font(.system(size: 10)).foregroundStyle(.secondary)
            Button { store.canvas?.finishEditing(); store.mcpSettingsVisible = true } label: {
                HStack(spacing: 5) { Circle().fill(mcp.running ? Color(nsColor: Palette.color(1)) : .gray).frame(width: 6, height: 6); Text("MCP").font(.system(size: 10, weight: .medium)) }
            }.buttonStyle(.plain).accessibilityLabel("MCP settings").help("Local MCP settings")
            Spacer()
            if store.mode == .mindMap { Text("Drag to pan · Pinch to zoom · Double-click to rename").font(.system(size: 10)).foregroundStyle(.secondary) }
            else { Text("Return: sibling · Tab: indent · Shift-Tab: outdent").font(.system(size: 10)).foregroundStyle(.secondary) }
            HStack(spacing: 2) {
                modeButton(.mindMap, title: "Mind map", image: "point.3.connected.trianglepath.dotted")
                modeButton(.outliner, title: "Outliner", image: "list.bullet.indent")
            }.padding(3).background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
        }.padding(.horizontal, 18).frame(height: 44).background(.white)
    }
    private func modeButton(_ mode: EditorMode, title: String, image: String) -> some View {
        Button { store.setMode(mode) } label: { Label(title, systemImage: image).font(.system(size: 10, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 5).background(store.mode == mode ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 5)) }.buttonStyle(.plain).foregroundStyle(store.mode == mode ? accent : .secondary).accessibilityLabel("Show \(title)")
    }
}

/// Zoom ticks update this small view instead of rebuilding the topic list and inspector.
private struct CanvasZoomControls: View {
    let store: MapStore
    @ObservedObject var viewport: CanvasViewport
    var body: some View {
        HStack(spacing: 0) {
            button("minus", "Zoom out") { store.canvas?.setZoom(viewport.zoom / 1.15) }
            Button { store.canvas?.setZoom(1) } label: { Text("\(Int(viewport.zoom * 100))%").font(.system(size: 11, weight: .medium, design: .monospaced)).frame(width: 49, height: 30) }.buttonStyle(.plain).help("Reset zoom to 100%")
            button("plus", "Zoom in") { store.canvas?.setZoom(viewport.zoom * 1.15) }
            Divider().frame(height: 18).padding(.horizontal, 8)
            button("arrow.up.left.and.arrow.down.right", "Fit to window") { store.canvas?.fit() }
            button("scope", "Center on root") { store.canvas?.center(on: store.map.root.id) }
        }.padding(6).background(.white, in: Capsule()).overlay(Capsule().stroke(Color.black.opacity(0.07))).shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }
    private func button(_ image: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: image).font(.system(size: 14)).frame(width: 30, height: 30).contentShape(Rectangle()) }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}
