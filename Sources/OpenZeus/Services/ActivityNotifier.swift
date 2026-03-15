import AppKit
import UserNotifications

/// Sends sound and/or push notifications when a watched agent task finishes.
@MainActor
final class ActivityNotifier {
    private let config: NotificationConfig
    private let attentionSound: NSSound?

    init(config: NotificationConfig = .init()) {
        self.config = config
        self.attentionSound = NSSound(named: config.soundName)
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Call when a watched task transitions from active → idle.
    /// Plays sound immediately (regardless of app focus), then sends a
    /// push notification if the app is in the background.
    func notify(taskName: String, watchMode: WatchMode) {
        guard watchMode != .off else { return }

        if watchMode == .on {
            attentionSound?.play()
        }

        // Only send a push notification when the user can't see the result
        guard !NSApp.isActive else { return }

        let content = UNMutableNotificationContent()
        content.title = config.notificationTitle
        content.body = config.body(taskName: taskName)
        if watchMode == .on {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
