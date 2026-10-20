import Foundation
import ActivityKit

/// Live Activity for the workout in progress. Compiled into the app (which starts,
/// updates and ends it) and the widget extension (which draws it).
struct WorkoutActivityAttributes: ActivityAttributes {

    struct ContentState: Codable, Hashable {
        var workoutName: String
        /// `startedAt` shifted by paused time, so elapsed = now − this while running.
        var elapsedReferenceDate: Date
        /// Frozen elapsed time while the workout is paused; nil while running.
        var pausedElapsed: TimeInterval?
        var completedSets: Int
        var currentExercise: String?
        /// When the running rest ends; nil when no rest is running.
        var restEndsAt: Date?
        var restDuration: TimeInterval?
        /// Remaining rest while the rest timer is paused.
        var restPausedRemaining: TimeInterval?

        var isPaused: Bool { pausedElapsed != nil }

        /// The window `restEndsAt − duration ... restEndsAt`, for countdown text and progress.
        var restInterval: ClosedRange<Date>? {
            guard let restEndsAt, let restDuration, restDuration > 0 else { return nil }
            return restEndsAt.addingTimeInterval(-restDuration)...restEndsAt
        }
    }

    /// The session this activity belongs to.
    var sessionID: UUID
}
