import SwiftUI
import WidgetKit
import FormCore

/// Workout in progress, or this week's training and streak.
struct TrainingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FormTraining", provider: SnapshotProvider()) { entry in
            TrainingWidgetView(entry: entry)
                .formWidgetBackground()
        }
        .configurationDisplayName("Training")
        .description("Your workout in progress, or this week's workouts and streak.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular])
    }
}

struct TrainingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            Group {
                if let active = snapshot.training.active, family == .accessoryCircular {
                    ZStack {
                        AccessoryWidgetBackground()
                        Image(systemName: active.clock.isPaused ? "pause.fill" : "figure.strengthtraining.traditional")
                    }
                    .widgetAccentable()
                    .accessibilityLabel(active.clock.isPaused ? "Workout paused" : "Workout in progress")
                } else if let active = snapshot.training.active {
                    ActiveWorkoutWidgetContent(active: active, compact: family != .systemSmall)
                } else {
                    switch family {
                    case .accessoryCircular: circular(snapshot)
                    case .accessoryRectangular: rectangular(snapshot)
                    default: small(snapshot)
                    }
                }
            }
            .widgetURL(URL(string: snapshot.training.active == nil ? "form://train" : "form://workout"))
        } else {
            switch family {
            case .systemSmall:
                WidgetEmptyView(symbol: "dumbbell", message: "Open Form to show your training here.")
            default:
                Label("Open Form", systemImage: "dumbbell")
            }
        }
    }

    private func small(_ snapshot: WidgetSnapshot) -> some View {
        let week = snapshot.workoutsThisWeek(on: entry.date)
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("This week").font(.caption.weight(.semibold)).foregroundStyle(Color.formTextSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(week)").font(.system(.largeTitle, design: .rounded).weight(.bold)).monospacedDigit()
                    .foregroundStyle(Color.formTextPrimary)
                Text(week == 1 ? "workout" : "workouts").font(.caption).foregroundStyle(Color.formTextSecondary)
            }
            if snapshot.training.weeklyStreak > 0 {
                Label("\(snapshot.training.weeklyStreak)-week streak", systemImage: "flame")
                    .font(.caption).foregroundStyle(Color.formAccent)
            }
            Spacer(minLength: 0)
            if let name = snapshot.training.lastWorkoutName, let date = snapshot.training.lastWorkoutDate {
                Text("Last: \(name)").font(.caption2).foregroundStyle(Color.formTextSecondary).lineLimit(1)
                Text(date, style: .relative).font(.caption2).foregroundStyle(Color.formTextSecondary)
            } else {
                Text("Tap to start a workout").font(.caption2).foregroundStyle(Color.formTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rectangular(_ snapshot: WidgetSnapshot) -> some View {
        let week = snapshot.workoutsThisWeek(on: entry.date)
        return VStack(alignment: .leading, spacing: 1) {
            Text("\(week) \(week == 1 ? "workout" : "workouts") this week").font(.headline).widgetAccentable()
            if snapshot.training.weeklyStreak > 0 {
                Text("\(snapshot.training.weeklyStreak)-week streak").font(.caption)
            }
            if let name = snapshot.training.lastWorkoutName {
                Text("Last: \(name)").font(.caption).lineLimit(1)
            }
        }
    }

    private func circular(_ snapshot: WidgetSnapshot) -> some View {
        let week = snapshot.workoutsThisWeek(on: entry.date)
        return ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "dumbbell").font(.caption2)
                Text("\(week)").font(.title3.weight(.semibold)).monospacedDigit()
            }
        }
        .widgetAccentable()
        .accessibilityLabel("\(week) workouts this week")
    }
}

/// Live elapsed time for a workout in progress. Uses system timer text, so it
/// keeps counting without timeline reloads.
struct ActiveWorkoutWidgetContent: View {
    let active: WidgetSnapshot.ActiveWorkout
    var compact = false

    var body: some View {
        let reference = active.clock.startedAt.addingTimeInterval(active.clock.accumulatedPause)
        VStack(alignment: .leading, spacing: compact ? 1 : Spacing.xs) {
            Label(active.clock.isPaused ? "Paused" : "In progress",
                  systemImage: active.clock.isPaused ? "pause.circle.fill" : "record.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(compact ? Color.primary : Color.formAccent)
            Text(active.name).font(compact ? .headline : .subheadline.weight(.semibold)).lineLimit(1)
                .foregroundStyle(compact ? Color.primary : Color.formTextPrimary)
            Group {
                if active.clock.isPaused, let pausedAt = active.clock.pausedAt {
                    Text(DurationText.clock(active.clock.elapsed(at: pausedAt)))
                } else {
                    Text(reference, style: .timer)
                }
            }
            .font(compact ? .caption : .title2.weight(.bold))
            .monospacedDigit()
            if !compact {
                Spacer(minLength: 0)
                Text("\(active.completedSets) sets done").font(.caption2).foregroundStyle(Color.formTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
