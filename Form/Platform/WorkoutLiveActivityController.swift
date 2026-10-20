import Foundation
import ActivityKit
import FormCore

/// Starts, updates and ends the workout Live Activity (Lock Screen and Dynamic Island).
///
/// Elapsed time and rest countdowns are drawn by the system from dates, so they
/// keep ticking while Form is suspended. The activity is refreshed whenever the
/// workout is saved. Live Activities can be turned off in iOS Settings › Form.
@MainActor
final class WorkoutLiveActivityController {
    static let shared = WorkoutLiveActivityController()

    private init() {}

    func sync(with session: WorkoutSession?, now: Date = .now) {
        let activities = Activity<WorkoutActivityAttributes>.activities
        guard let session, session.status == .active else {
            for activity in activities { end(activity) }
            return
        }
        // Only one workout can be active; end anything left over from another session.
        for activity in activities where activity.attributes.sessionID != session.id { end(activity) }

        let state = Self.contentState(for: session, now: now)
        let content = ActivityContent(state: state, staleDate: Self.staleDate(for: state, now: now))

        if let current = activities.first(where: { $0.attributes.sessionID == session.id }) {
            guard current.content.state != state else { return }
            Task { await current.update(content) }
        } else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            // Failing to start (for example, too many activities) only means no Lock Screen view.
            _ = try? Activity.request(attributes: WorkoutActivityAttributes(sessionID: session.id),
                                      content: content, pushType: nil)
        }
    }

    func endAll() {
        for activity in Activity<WorkoutActivityAttributes>.activities { end(activity) }
    }

    private func end(_ activity: Activity<WorkoutActivityAttributes>) {
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    static func contentState(for session: WorkoutSession, now: Date) -> WorkoutActivityAttributes.ContentState {
        let clock = session.clock
        let timer = session.restTimer
        let current = session.orderedExercises.first { exercise in
            !exercise.isSkipped && exercise.orderedSets.contains { !$0.isCompleted }
        }
        let restRunning = timer?.isRunning == true && (timer?.endDate ?? .distantPast) > now
        return WorkoutActivityAttributes.ContentState(
            workoutName: session.name,
            elapsedReferenceDate: clock.startedAt.addingTimeInterval(clock.accumulatedPause),
            pausedElapsed: clock.isPaused ? clock.elapsed(at: now) : nil,
            completedSets: session.completedSetCount,
            currentExercise: current?.exerciseName,
            restEndsAt: restRunning ? timer?.endDate : nil,
            restDuration: timer?.isActive == true ? timer?.duration : nil,
            restPausedRemaining: timer?.isPaused == true ? timer?.remaining(at: now) : nil
        )
    }

    /// Once a rest ends the countdown would sit at 0:00, so mark the content stale
    /// then and let the view say the rest is over.
    private static func staleDate(for state: WorkoutActivityAttributes.ContentState, now: Date) -> Date? {
        state.restEndsAt
    }
}
