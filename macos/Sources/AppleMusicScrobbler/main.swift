import AppKit
import ScrobblerCore

/// --dry-run: read Music and log what would be scrobbled, without contacting Last.fm.
let dryRun = CommandLine.arguments.contains("--dry-run")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private var reader: MusicReader!
    private var app: MenuBarApp?
    private let setup = SetupWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
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
