import AppKit
import Sparkle
import CryptoKit

@MainActor final class FeedProbe: NSObject, SPUUpdaterDelegate {
    let url: String
    var version: String?
    var error: Error?
    init(url: String) { self.url = url }
    func feedURLString(for updater: SPUUpdater) -> String? { url }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) { version = item.versionString }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) { self.error = error }
}

@main struct UpdaterTests {
    @MainActor static func main() throws {
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--create-key" {
            let key = Curve25519.Signing.PrivateKey()
            let path = CommandLine.arguments[2]
            FileManager.default.createFile(atPath: path, contents: Data(key.rawRepresentation.base64EncodedString().utf8), attributes: [.posixPermissions: 0o600])
            print(key.publicKey.rawRepresentation.base64EncodedString())
            return
        }
        _ = NSApplication.shared
        if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--probe" {
            let delegate = FeedProbe(url: CommandLine.arguments[2])
            let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: delegate, userDriverDelegate: nil)
            try controller.updater.start()
            controller.updater.checkForUpdateInformation()
            let deadline = Date(timeIntervalSinceNow: 15)
            while delegate.version == nil && delegate.error == nil && Date() < deadline {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
            }
            let expected = CommandLine.arguments[3]
            if expected == "reject" {
                precondition(delegate.error != nil && delegate.version == nil, "Sparkle must reject the altered signed feed")
            } else {
                precondition(delegate.version == expected, "Sparkle did not find the signed update: \(String(describing: delegate.error))")
            }
            print("✓ Sparkle feed probe: \(expected)")
            return
        }
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1; print("✓ \(message)")
        }
        var prepared = false
        let paused = AppUpdater(isEnabled: false) {}
        let pausedMenu = NSMenu()
        paused.addMenuItems(to: pausedMenu)
        paused.start()
        check(pausedMenu.items.isEmpty, "Paused updater hides unavailable update actions")
        let updater = AppUpdater { prepared = true }
        let menu = NSMenu()
        updater.addMenuItems(to: menu)
        check(menu.items.count == 3, "Updater adds a separator, manual check, and automatic-check setting")
        let manual = menu.items[1], automatic = menu.items[2]
        check(manual.title == "Check for Updates…", "Manual update action is discoverable in the app menu")
        check(manual.target === updater.controller, "Sparkle owns check action validation and in-progress state")
        check(manual.action == #selector(SPUStandardUpdaterController.checkForUpdates(_:)), "Manual action uses Sparkle's native update UI")
        try updater.controller.updater.start()
        check(updater.controller.updater.canCheckForUpdates, "Embedded framework starts successfully in a real app bundle")
        check(!updater.controller.updater.automaticallyChecksForUpdates, "Test host honors disabled automatic checks")
        updater.toggleAutomaticChecks(nil)
        _ = updater.validateMenuItem(automatic)
        check(updater.controller.updater.automaticallyChecksForUpdates && automatic.state == .on, "Automatic-check toggle enables the scheduler and checkmark")
        updater.toggleAutomaticChecks(nil)
        _ = updater.validateMenuItem(automatic)
        check(!updater.controller.updater.automaticallyChecksForUpdates && automatic.state == .off, "Automatic-check toggle can be turned off")
        let item = SUAppcastItem(dictionary: ["title": "Test update", "enclosure": ["url": "https://example.com/update.zip", "sparkle:version": "2.0"]])!
        updater.updater(updater.controller.updater, willInstallUpdate: item)
        check(prepared, "Installation flushes pending document title edits")
        check(Bundle.main.object(forInfoDictionaryKey: "SUAllowsAutomaticUpdates") as? Bool == false, "Updates require the user's install action")
        check(Bundle.main.object(forInfoDictionaryKey: "SURequireSignedFeed") as? Bool == true, "Host requires signed release metadata")
        check(Bundle.main.object(forInfoDictionaryKey: "SUVerifyUpdateBeforeExtraction") as? Bool == true, "Host verifies archives before extraction")
        print("PASS: \(checks) native updater checks")
    }
}
