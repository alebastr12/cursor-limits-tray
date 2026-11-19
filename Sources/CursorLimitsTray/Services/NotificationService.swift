import Foundation
import UserNotifications

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private var configured = false

    func configure() {
        guard !configured else { return }
        configured = true
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async -> Bool {
        configure()
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func notifyLowBalance(provider: String, limit: String, remaining: Int) {
        configure()
        let content = UNMutableNotificationContent()
        content.title = L10n.tr("notification.low_title", provider)
        content.body = L10n.tr("notification.low_body", limit, remaining)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(provider).\(limit).\(remaining).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
