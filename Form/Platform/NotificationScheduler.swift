import Foundation
import UserNotifications
import FormCore

/// Local notifications only; nothing is sent to a server.
/// Used for the optional rest-timer alert and the optional daily logging reminder.
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

    // MARK: Daily logging reminder

    private static let reminderPrefix = "form.reminder."

    /// Replaces the pending logging reminders with one per date.
    static func scheduleLoggingReminders(at dates: [Date], calendar: Calendar = .current) async {
        await cancelLoggingReminders()
        for date in dates {
            let content = UNMutableNotificationContent()
            content.title = "Log today's food"
            content.body = "Nothing is in your Form diary yet today."
            content.sound = .default
            content.interruptionLevel = .passive
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let identifier = reminderPrefix + CSVTable.day(date)
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }

    static func cancelLoggingReminders() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(reminderPrefix) })
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
}
