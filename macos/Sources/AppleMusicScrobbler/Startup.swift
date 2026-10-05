import ServiceManagement
import ScrobblerCore

/// "Start at login" through macOS's login items (System Settings › General › Login Items).
enum Startup {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            Log.write(enabled ? "Start at login turned on" : "Start at login turned off")
        } catch {
            Log.write("Could not change start at login: \(error.localizedDescription)")
        }
    }
}
