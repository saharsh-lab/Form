import ActivityKit
import SwiftUI
import WidgetKit
import FormCore

/// Lock Screen and Dynamic Island presentation of the workout in progress.
/// Elapsed time and rest countdowns are system timer text, so they tick while
/// Form is suspended.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenWorkoutView(state: context.state, isStale: context.isStale)
                .padding(Spacing.m)
                .activityBackgroundTint(Color.formSurface)
                .activitySystemActionForegroundColor(Color.formAccent)
                .widgetURL(URL(string: "form://workout"))
        } dynamicIsland: { context in
            let state = context.state
            let resting = Self.isResting(state, isStale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(state.workoutName, systemImage: "figure.strengthtraining.traditional")
                        .font(.caption.weight(.semibold)).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedText(state: state).font(.caption.weight(.semibold)).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        RestStatusView(state: state, isStale: context.isStale)
                        HStack {
                            if let exercise = state.currentExercise {
                                Text(exercise).lineLimit(1)
                            }
                            Spacer()
                            Text("\(state.completedSets) sets")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: resting ? "timer" : "figure.strengthtraining.traditional")
                    .foregroundStyle(Color.formAccent)
            } compactTrailing: {
                Group {
                    if resting, let interval = state.restInterval {
                        Text(timerInterval: interval, countsDown: true)
                    } else {
                        ElapsedText(state: state)
                    }
                }
                .monospacedDigit()
                .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: resting ? "timer" : "figure.strengthtraining.traditional")
                    .foregroundStyle(Color.formAccent)
            }
            .widgetURL(URL(string: "form://workout"))
        }
    }

    static func isResting(_ state: WorkoutActivityAttributes.ContentState, isStale: Bool) -> Bool {
        guard let end = state.restEndsAt else { return false }
        return !isStale && end > Date()
    }
}

private struct ElapsedText: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        if let paused = state.pausedElapsed {
            Text(DurationText.clock(paused))
        } else {
            Text(state.elapsedReferenceDate, style: .timer)
        }
    }
}

private struct RestStatusView: View {
    let state: WorkoutActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if WorkoutLiveActivity.isResting(state, isStale: isStale), let interval = state.restInterval {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Rest").font(.caption.weight(.semibold))
                    Spacer()
                    Text(timerInterval: interval, countsDown: true)
                        .font(.title3.weight(.bold)).monospacedDigit()
                        .multilineTextAlignment(.trailing)
                }
                ProgressView(timerInterval: interval, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(Color.formAccent)
            }
        } else if let remaining = state.restPausedRemaining {
            Label("Rest paused · \(DurationText.clock(remaining)) left", systemImage: "pause.circle")
                .font(.caption.weight(.semibold))
        } else if state.restEndsAt != nil || isStale {
            Label("Rest over", systemImage: "checkmark.circle")
                .font(.caption.weight(.semibold)).foregroundStyle(Color.formAccent)
        }
    }
}

private struct LockScreenWorkoutView: View {
    let state: WorkoutActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.workoutName).font(.headline).foregroundStyle(Color.formTextPrimary).lineLimit(1)
                    Text(state.isPaused ? "Paused" : (state.currentExercise ?? "In progress"))
                        .font(.caption).foregroundStyle(Color.formTextSecondary).lineLimit(1)
                }
                Spacer()
                ElapsedText(state: state)
                    .font(.title2.weight(.bold)).monospacedDigit()
                    .foregroundStyle(Color.formTextPrimary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 110, alignment: .trailing)
            }
            RestStatusView(state: state, isStale: isStale)
                .foregroundStyle(Color.formTextPrimary)
            Text("\(state.completedSets) sets completed").font(.caption2).foregroundStyle(Color.formTextSecondary)
        }
    }
}
