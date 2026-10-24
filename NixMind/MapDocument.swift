import AppKit
import SwiftUI

@MainActor @objc(MapDocument) final class MapDocument: NSDocument {
    let store = MapStore()
    let sessionID = UUID().uuidString
    override init() {
        super.init()
        hasUndoManager = true
        store.document = self
    }
    override class var autosavesInPlace: Bool { true }
    override func makeWindowControllers() {
        if fileType != MapFormats.nativeType, fileURL != nil {
            let name = fileURL!.deletingPathExtension().lastPathComponent
            fileURL = nil; fileType = MapFormats.nativeType
            displayName = name + " — " + "Imported"
            updateChangeCount(.changeDone)
        }
        let controller = NSHostingController(rootView: ContentView(store: store))
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 1380, height: 860))
        window.minSize = NSSize(width: 1040, height: 720)
        window.title = "Nix Mind"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .white
        window.center()
        let windowController = NSWindowController(window: window)
        addWindowController(windowController)
    }
    override func data(ofType typeName: String) throws -> Data {
        var book = store.workbook
        book.activeMap = store.canvas?.snapshotForSaving() ?? store.map
        return try MapFormats.encodeBook(book, type: typeName)
    }
    override func read(from data: Data, ofType typeName: String) throws {
        let book = try MapFormats.decodeBook(data, type: typeName)
        MainActor.assumeIsolated {
            store.load(book)
            store.document = self
        }
    }
    override func save(_ sender: Any?) {
        store.canvas?.finishEditing()
        super.save(sender)
    }
    override func saveAs(_ sender: Any?) {
        store.canvas?.finishEditing()
        super.saveAs(sender)
    }
    override func canClose(withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        store.canvas?.finishEditing()
        super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
    }
    @objc func showMCPSettings(_ sender: Any?) { store.canvas?.finishEditing(); store.mcpSettingsVisible = true }
    @objc func addChild(_ sender: Any?) { store.addChild() }
    @objc func addSibling(_ sender: Any?) { store.addSibling() }
    @objc func renameTopic(_ sender: Any?) { store.editSelected() }
    @objc func deleteTopic(_ sender: Any?) { store.deleteSelection() }
    @objc func arrangeMap(_ sender: Any?) { store.arrange() }
    @objc func fitMap(_ sender: Any?) { store.canvas?.fit() }
    @objc func centerMap(_ sender: Any?) { store.canvas?.center(on: store.map.root.id) }
    @objc func exportXmind(_ sender: Any?) { export(type: MapFormats.xmindType, extension: "xmind") }
    @objc func exportFreeMind(_ sender: Any?) { export(type: MapFormats.freeMindType, extension: "mm") }
    func export(type: String, extension ext: String) {
        store.canvas?.finishEditing()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (type == MapFormats.freeMindType ? store.activeSheet.title : (fileURL?.deletingPathExtension().lastPathComponent ?? "Mind map")) + "." + ext
        panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .data]
        guard let window = windowControllers.first?.window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do { try MapFormats.encodeBook(self.store.workbook, type: type).write(to: url, options: .atomic); self.store.showToast("Exported" + " \(url.lastPathComponent)") }
            catch { self.presentError(error) }
        }
    }
}
import UniformTypeIdentifiers
