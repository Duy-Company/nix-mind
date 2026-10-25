// Standalone model/editor test executables do not link the app's Sparkle package.
#if canImport(Sparkle)
import AppKit
import Sparkle

@MainActor final class AppUpdater: NSObject, SPUUpdaterDelegate, NSMenuItemValidation {
    private(set) var controller: SPUStandardUpdaterController!
    private let isEnabled: Bool
    private let prepareForInstallation: () -> Void

    init(isEnabled: Bool = Bundle.main.object(forInfoDictionaryKey: "NixMindUpdatesEnabled") as? Bool ?? false, prepareForInstallation: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.prepareForInstallation = prepareForInstallation
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    }

    func start() { if isEnabled { controller.startUpdater() } }

    func addMenuItems(to menu: NSMenu) {
        guard isEnabled else { return }
        menu.addItem(.separator())
        let check = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        check.target = controller
        menu.addItem(check)
        let automatic = NSMenuItem(title: "Automatically Check for Updates", action: #selector(toggleAutomaticChecks(_:)), keyEquivalent: "")
        automatic.target = self
        menu.addItem(automatic)
    }

    @objc func toggleAutomaticChecks(_ sender: Any?) {
        controller.updater.automaticallyChecksForUpdates.toggle()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.state = controller.updater.automaticallyChecksForUpdates ? .on : .off
        return true
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        // Commit inline title edits before normal NSDocument save/quit handling.
        prepareForInstallation()
    }
}
#endif
