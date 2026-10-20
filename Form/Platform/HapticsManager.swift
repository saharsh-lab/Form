import UIKit

/// Central place for app haptics, so feedback stays consistent and respects
/// the user's Haptics setting. Call sites describe *what happened*
/// (a set was completed, a save succeeded), not which generator to use.
///
/// iOS already suppresses all haptics when the system "System Haptics" switch
/// is off; this manager adds the app-level Full / Reduced / Off preference.
@MainActor
final class HapticsManager {
    static let shared = HapticsManager()

    var level: HapticsLevel = .full

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    private init() {}

    /// A set was marked complete. Full level only.
    func setCompleted() {
        guard level == .full else { return }
        lightImpact.impactOccurred()
    }

    /// A meaningful picker or segment change (not every scroll tick). Full level only.
    func selectionChanged() {
        guard level == .full else { return }
        selection.selectionChanged()
    }

    /// A save or edit succeeded. Call only after the save has actually completed.
    func saveSucceeded() {
        guard level != .off else { return }
        notification.notificationOccurred(.success)
    }

    /// A genuine personal record was achieved and saved.
    func personalRecord() {
        guard level != .off else { return }
        notification.notificationOccurred(.success)
    }

    /// The rest timer finished while the app is in the foreground.
    func timerFinished() {
        guard level != .off else { return }
        notification.notificationOccurred(.warning)
    }

    /// A significant error, such as a failed save.
    func error() {
        guard level != .off else { return }
        notification.notificationOccurred(.error)
    }

    /// A goal milestone, such as reaching the daily protein target. Full level only, deliberately subtle.
    func milestone() {
        guard level == .full else { return }
        softImpact.impactOccurred(intensity: 0.6)
    }

    /// Readies the generators shortly before feedback is likely, for lower latency.
    func prepareForSetLogging() {
        guard level == .full else { return }
        lightImpact.prepare()
    }
}
