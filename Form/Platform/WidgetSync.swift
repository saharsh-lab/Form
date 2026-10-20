import Foundation
import SwiftData
import WidgetKit
import FormCore

/// Keeps widgets and the workout Live Activity in step with saved data.
///
/// After each save the app writes a small JSON snapshot to the App Group
/// container and asks WidgetKit to reload. Widgets read only that snapshot,
/// so they never touch the database.
@MainActor
enum WidgetSync {

    private static var lastWritten: WidgetSnapshot?

    static func refresh(context: ModelContext, now: Date = .now) {
        let snapshot = makeSnapshot(context: context, now: now)
        WorkoutLiveActivityController.shared.sync(with: WorkoutRepository(context: context).activeSession(), now: now)

        guard let url = AppGroup.widgetSnapshotURL else { return }
        // Skip the write and reload when nothing a widget shows has changed.
        var comparable = snapshot
        comparable.generatedAt = lastWritten?.generatedAt ?? snapshot.generatedAt
        if comparable == lastWritten, Calendar.current.isDate(lastWritten?.generatedAt ?? .distantPast, inSameDayAs: now) {
            return
        }
        do {
            try WidgetSnapshotStore.write(snapshot, to: url)
            lastWritten = snapshot
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Widgets keep showing their last snapshot; the app itself is unaffected.
            lastWritten = nil
        }
    }

    static func makeSnapshot(context: ModelContext, now: Date, calendar: Calendar = .current) -> WidgetSnapshot {
        let preferences = PreferencesStore.current(in: context)

        // Nutrition for today, judged against the goal in effect today.
        let day = DayBounds.range(containing: now, calendar: calendar)
        let dayStart = day.lowerBound
        let dayEnd = day.upperBound
        let entries = (try? context.fetch(FetchDescriptor<FoodLogEntry>(
            predicate: #Predicate { $0.day >= dayStart && $0.day < dayEnd }))) ?? []
        let totals = NutritionTotals(entries.map(\.nutrition))
        let goals = (try? context.fetch(FetchDescriptor<DailyNutritionGoal>())) ?? []
        let targets = GoalResolver.goal(on: now, from: goals.map(\.snapshot), calendar: calendar)?.targets ?? .unspecified
        var consumed = NutritionValues.unspecified
        for nutrient in Nutrient.allCases where totals.missingCount(for: nutrient) < totals.entryCount {
            consumed[nutrient] = totals.total(for: nutrient)
        }
        let nutrition = WidgetSnapshot.Nutrition(day: dayStart, consumed: consumed, targets: targets,
                                                 entryCount: totals.entryCount,
                                                 entriesMissingCalories: totals.missingCount(for: .calories))

        // Training.
        let completed = WorkoutStatus.completed.rawValue
        let since = calendar.date(byAdding: .year, value: -1, to: dayStart) ?? dayStart
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.statusRaw == completed && $0.startedAt >= since },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))) ?? []
        let dates = sessions.map(\.startedAt)
        let week = DayBounds.weekRange(containing: now, calendar: calendar)
        let active = WorkoutRepository(context: context).activeSession().map { session in
            WidgetSnapshot.ActiveWorkout(name: session.name, clock: session.clock,
                                         completedSets: session.completedSetCount, restTimer: session.restTimer)
        }
        let training = WidgetSnapshot.Training(active: active,
                                               lastWorkoutName: sessions.first?.name,
                                               lastWorkoutDate: sessions.first.map { $0.endedAt ?? $0.startedAt },
                                               workoutsThisWeek: dates.filter { week.contains($0) }.count,
                                               weeklyStreak: ProgressAnalytics.weeklyStreak(of: dates, now: now, calendar: calendar))

        // Latest body weight.
        let bodyWeight = MeasurementKind.bodyWeight.rawValue
        var weightDescriptor = FetchDescriptor<BodyMeasurement>(
            predicate: #Predicate { $0.kindRaw == bodyWeight },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        weightDescriptor.fetchLimit = 1
        let latestWeight = (try? context.fetch(weightDescriptor).first).map {
            WidgetSnapshot.BodyWeight(kilograms: $0.value, date: $0.date)
        }

        return WidgetSnapshot(generatedAt: now, weightUnit: preferences.weightUnit,
                              nutrition: nutrition, training: training, latestBodyWeight: latestWeight)
    }
}
