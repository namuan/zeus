import AppKit
import UserNotifications

/// Sends sound and/or push notifications when a watched agent task finishes.
@MainActor
final class ActivityNotifier {
    private let attentionSound = NSSound(named: "Tink")

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
        content.title = "Agent finished"
        content.body = "\(taskName) has completed its task"
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
