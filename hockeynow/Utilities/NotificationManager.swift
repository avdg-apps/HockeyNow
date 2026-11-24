import AppKit
import UserNotifications
import Combine

// MARK: - Notifications (Apple's UserNotifications)
// A menu bar app is often treated as "frontmost", and macOS then drops banners unless the delegate explicitly allows
// them in willPresent. The delegate also has to be set before any notification is posted.
@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    @Published private(set) var status: UNAuthorizationStatus = .notDetermined

    private override init() { super.init() }

    private var configured = false
    func configure() {
        guard !configured else { return }
        configured = true
        UNUserNotificationCenter.current().delegate = self
        Task { await requestAuthorizationIfNeeded() }
    }

    func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        status = settings.authorizationStatus
    }

    func requestAuthorizationIfNeeded() async {
        await refreshStatus()
        guard status == .notDetermined else { return }
        // An accessory (menu bar) app must be active for macOS to show the permission prompt.
        NSApp.activate(ignoringOtherApps: true)
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await refreshStatus()
    }

    func openSystemSettings() {
        let urls = ["x-apple.systempreferences:com.apple.Notifications-Settings.extension",
                    "x-apple.systempreferences:com.apple.preference.notifications"]
        for string in urls { if let url = URL(string: string), NSWorkspace.shared.open(url) { return } }
    }

    // One place that posts an alert. `url` is opened when the banner is clicked (for example the game page).
    static func post(title: String, body: String, identifier: String, url: URL?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = hockeyNowNotificationSound()
        if let url { content.userInfo = ["url": url.absoluteString] }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    func sendTest() {
        Task {
            await requestAuthorizationIfNeeded()
            let content = UNMutableNotificationContent()
            content.title = "HockeyNow"
            content.body = "Notifications are working. 🚨 This is how a goal alert will look."
            content.sound = hockeyNowNotificationSound()
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: nil))
        }
    }

    // Show banners even while HockeyNow counts as the active app.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        if let text = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: text) {
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        }
        completionHandler()
    }
}
