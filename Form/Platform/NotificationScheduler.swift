import Foundation
import UserNotifications

/// Local notifications only; nothing is sent to a server.
/// Used for the optional rest-timer alert and (Phase 6) workout reminders.
@MainActor
enum NotificationScheduler {
    private static let restTimerIdentifier = "form.rest-timer"

    /// Asks for permission. Returns whether alerts are allowed.
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /// Schedules (or replaces) the "rest finished" alert for `endDate`.
    /// The system delivers it even if Form is suspended; iOS shows it only when
    /// the app isn't in the foreground, where Form gives haptic feedback instead.
    static func scheduleRestTimerAlert(at endDate: Date, exerciseName: String?) {
        let interval = endDate.timeIntervalSinceNow
        cancelRestTimerAlert()
        guard interval >= 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest finished"
        content.body = exerciseName.map { "Time for your next set of \($0)." } ?? "Time for your next set."
        content.sound = .default
        content.interruptionLevel = .active
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: restTimerIdentifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelRestTimerAlert() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [restTimerIdentifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [restTimerIdentifier])
    }
}
