import AppKit
import ScrobblerCore

/// --dry-run: read Music and log what would be scrobbled, without contacting Last.fm.
let dryRun = CommandLine.arguments.contains("--dry-run")

/// --pretend-version X.Y.Z: check for updates as if this were version X.Y.Z, to test the updater
/// against the latest release (it offers to "update" to it). Doesn't change anything else.
if let i = CommandLine.arguments.firstIndex(of: "--pretend-version"), i + 1 < CommandLine.arguments.count {
    UpdateChecker.pretendVersion = CommandLine.arguments[i + 1]
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private var reader: MusicReader!
    private var app: MenuBarApp?
    private let setup = SetupWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Developer option (README screenshot); works while the app is running too.
        if let i = CommandLine.arguments.firstIndex(of: "--save-setup-screenshot"), i + 1 < CommandLine.arguments.count {
            saveSetupScreenshot(to: CommandLine.arguments[i + 1], settings: Settings(defaults: UserDefaults(suiteName: "screenshot") ?? .standard), reader: MusicReader())
            NSApp.terminate(nil)
            return
        }

        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != .current }) {
            let alert = NSAlert()
            alert.messageText = "\(AppInfo.name) is already running."
            alert.informativeText = "Look for the \u{266A} note icon in the menu bar."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        Log.echo = dryRun
        Notifier.shared.start()
        reader = MusicReader()


        if !dryRun && !settings.isConnected {
            setup.show(settings: settings, reader: reader) { [weak self] connected in
                guard let self else { return }
                if connected { startMenuBar(justConnected: true) } else { NSApp.terminate(nil) }
            }
        } else {
            startMenuBar(justConnected: false)
        }
    }

    private func startMenuBar(justConnected: Bool) {
        let app = MenuBarApp(settings: settings, reader: reader, dryRun: dryRun)
        self.app = app
        app.start(justConnected: justConnected)
    }

    func applicationWillTerminate(_ notification: Notification) {
        app?.stop()
    }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory) // menu bar only, no Dock icon (also set by LSUIElement)
    application.run()
}
