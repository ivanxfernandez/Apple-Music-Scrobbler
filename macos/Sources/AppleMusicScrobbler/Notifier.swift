import AppKit
import UserNotifications
import ScrobblerCore

/// macOS notifications (the Windows balloons). Permission is asked the first time one is shown,
/// not at launch, so a new user doesn't get several system prompts at once.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// Notifications only work inside an .app bundle (not with `swift run`).
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func start() {
        center?.delegate = self
    }

    /// Called when the user clicks a notification shown with an `action`.
    var onAction: ((String) -> Void)?

    func show(_ title: String, _ body: String, url: URL? = nil, action: String? = nil) {
        guard let center else {
            Log.write("[notification] \(title): \(body)")
            return
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if let url { content.userInfo["url"] = url.absoluteString }
            if let action { content.userInfo["action"] = action }
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    // Show notifications even though a menu bar app counts as "in the foreground".
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let action = info["action"] as? String {
            DispatchQueue.main.async { self.onAction?(action) }
        } else if let text = info["url"] as? String, let url = URL(string: text) {
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        }
        completionHandler()
    }
}
