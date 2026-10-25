import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var appUpdater = AppUpdater {
        for document in NSDocumentController.shared.documents {
            (document as? MapDocument)?.store.canvas?.finishEditing()
        }
    }
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.mainMenu = makeMenu()
        _ = NSDocumentController.shared
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        MCPState.shared.start()
        appUpdater.start()
    }
    func applicationWillTerminate(_ notification: Notification) { MCPState.shared.stop() }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        func section(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title); item.submenu = submenu; menu.addItem(item); return submenu
        }
        func item(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.keyEquivalentModifierMask = modifiers; menu.addItem(item)
        }
        let app = section("Nix Mind")
        item(app, "About Nix Mind", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        appUpdater.addMenuItems(to: app)
        app.addItem(.separator()); item(app, "Hide Nix Mind", #selector(NSApplication.hide(_:)), "h")
        app.addItem(.separator()); item(app, "Quit Nix Mind", #selector(NSApplication.terminate(_:)), "q")
        let file = section("File")
        item(file, "New Mind Map", #selector(NSDocumentController.newDocument(_:)), "n")
        item(file, "Open…", #selector(NSDocumentController.openDocument(_:)), "o")
        file.addItem(.separator())
        item(file, "Save", #selector(NSDocument.save(_:)), "s")
        item(file, "Save As…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift])
        file.addItem(.separator())
        item(file, "Export mind map archive…", #selector(MapDocument.exportArchive(_:)))
        item(file, "Export current sheet (.mm)…", #selector(MapDocument.exportFreeMind(_:)))
        file.addItem(.separator()); item(file, "Close", #selector(NSWindow.performClose(_:)), "w")
        let edit = section("Edit")
        item(edit, "Undo", Selector(("undo:")), "z")
        item(edit, "Redo", Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator()); item(edit, "Cut", #selector(NSText.cut(_:)), "x"); item(edit, "Copy", #selector(NSText.copy(_:)), "c"); item(edit, "Paste", #selector(NSText.paste(_:)), "v"); item(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
        edit.addItem(.separator()); item(edit, "Find Topics…", #selector(MapDocument.showSearch(_:)), "f")
        let node = section("Topic")
        item(node, "Add child topic", #selector(MapDocument.addChild(_:)))
        item(node, "Add sibling topic", #selector(MapDocument.addSibling(_:)))
        item(node, "Rename topic", #selector(MapDocument.renameTopic(_:)))
        item(node, "Delete branch", #selector(MapDocument.deleteTopic(_:)))
        let mcp = section("MCP")
        item(mcp, "MCP Settings…", #selector(MapDocument.showMCPSettings(_:)), "a", [.command, .shift])
        item(node, "Arrange sheet", #selector(MapDocument.arrangeMap(_:)), "l", [.command, .shift])
        let view = section("View")
        item(view, "Fit to window", #selector(MapDocument.fitMap(_:)), "0")
        item(view, "Center on root", #selector(MapDocument.centerMap(_:)), "1")
        item(view, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        let window = section("Window")
        item(window, "Zoom out", #selector(NSWindow.performMiniaturize(_:)), "m")
        item(window, "Zoom", #selector(NSWindow.performZoom(_:)))
        NSApplication.shared.windowsMenu = window
        return menu
    }
}

if CommandLine.arguments.contains("--mcp") {
    MCPServer.run()
} else {
MainActor.assumeIsolated {
UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
let application = NSApplication.shared
application.setActivationPolicy(.regular)
let delegate = AppDelegate()
application.delegate = delegate
application.run()

}

}
