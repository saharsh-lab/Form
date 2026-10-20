import Foundation
import FormCore

/// Keeps the optional daily logging reminder up to date. Reminders are scheduled
/// a week ahead and today's is dropped as soon as something is logged, so you're
/// only reminded on days with an empty diary (as long as Form runs that day).
@MainActor
enum ReminderSync {
    private struct Key: Equatable {
        var enabled: Bool
        var hour: Int
        var minute: Int
        var hasLoggedToday: Bool
        var day: Date
    }

    private static var lastKey: Key?

    static func update(preferences: UserPreferences, hasLoggedToday: Bool, now: Date = .now) {
        let key = Key(enabled: preferences.remindersEnabled, hour: preferences.reminderHour, minute: preferences.reminderMinute,
                      hasLoggedToday: hasLoggedToday, day: Calendar.current.startOfDay(for: now))
        guard key != lastKey else { return }
        lastKey = key
        Task {
            guard key.enabled else {
                await NotificationScheduler.cancelLoggingReminders()
                return
            }
            let dates = ReminderPlanner.fireDates(hour: key.hour, minute: key.minute, hasLoggedToday: key.hasLoggedToday, now: now)
            await NotificationScheduler.scheduleLoggingReminders(at: dates)
        }
    }

    /// Forgets the cached state so the next update reschedules.
    static func reset() {
        lastKey = nil
    }
}
