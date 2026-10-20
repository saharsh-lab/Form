import SwiftUI
import SwiftData
import FormCore

/// The Today dashboard: greeting, nutrition progress, workout status, quick actions and consistency.
/// Every value shown is read from persisted records; nothing is hard-coded.
struct TodayView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    /// The day being shown. Refreshed when the app becomes active or the day changes.
    @State private var today = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                TodayHeader(date: today)
                TodayNutritionCard(day: today)
                TodayWorkoutCard(day: today)
                quickActions
                TodayConsistencyCard(now: today)
                LatestBodyWeightCard()
            }
            .padding(.horizontal, Spacing.m)
            .padding(.top, Spacing.xs)
            .padding(.bottom, Spacing.xl)
        }
        .formPageBackground()
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                        .frame(minWidth: Metrics.minimumTouchTarget, minHeight: Metrics.minimumTouchTarget)
                }
                .accessibilityLabel("Settings")
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { today = Date() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            today = Date()
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            SectionHeader("Quick actions")
            HStack(spacing: Spacing.s) {
                QuickActionButton(title: "Start workout", symbol: "figure.strengthtraining.traditional") {
                    router.select(.train)
                }
                QuickActionButton(title: "Add food", symbol: "plus.circle") {
                    router.select(.nutrition)
                }
                QuickActionButton(title: "Log weight", symbol: "scalemass") {
                    router.presentedSheet = .logBodyWeight
                }
            }
        }
    }
}

private struct TodayHeader: View {
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.formTextSecondary)
            Text(greeting)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Color.formTextPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }
}

/// Calories and macros for the day, judged against the goal in effect that day.
private struct TodayNutritionCard: View {
    @Environment(AppRouter.self) private var router
    @Query private var entries: [FoodLogEntry]
    @Query(sort: \DailyNutritionGoal.effectiveFrom, order: .reverse) private var goals: [DailyNutritionGoal]
    private let day: Date

    init(day: Date) {
        self.day = day
        let range = DayBounds.range(containing: day)
        let start = range.lowerBound
        let end = range.upperBound
        _entries = Query(filter: #Predicate<FoodLogEntry> { entry in
            entry.day >= start && entry.day < end
        })
    }

    private var totals: NutritionTotals {
        NutritionTotals(entries.map(\.nutrition))
    }

    private var targets: NutritionValues? {
        GoalResolver.goal(on: day, from: goals.map(\.snapshot))?.targets
    }

    var body: some View {
        FormCard {
            SectionHeader(title: "Nutrition") {
                Button("Diary") { router.select(.nutrition) }
                    .font(.subheadline.weight(.medium))
            }
            if entries.isEmpty && targets == nil {
                EmptyStateView(symbol: "fork.knife",
                               title: "Nothing logged yet",
                               message: "Set your daily targets in Settings, then log meals from the Nutrition tab to see your progress here.",
                               actionTitle: "Open Nutrition") {
                    router.select(.nutrition)
                }
            } else {
                CalorieSummaryView(totals: totals, target: targets?.calories)
                Divider().overlay(Color.formSeparator)
                MacroSummaryView(totals: totals, targets: targets)
                if entries.isEmpty {
                    InlineNotice(symbol: "info.circle", text: "No food logged today yet.")
                } else if totals.missingCount(for: .calories) > 0 {
                    InlineNotice(symbol: "exclamationmark.triangle",
                                 text: "\(totals.missingCount(for: .calories)) of \(totals.entryCount) entries have no calorie value, so the total may be low.",
                                 tint: .formWarning)
                }
                if targets == nil {
                    NavigationLink {
                        NutritionGoalsView()
                    } label: {
                        Label("Set daily targets", systemImage: "target")
                            .font(.subheadline.weight(.medium))
                    }
                }
            }
        }
    }
}

/// Today's workout: in progress, completed, or not started.
private struct TodayWorkoutCard: View {
    @Environment(AppRouter.self) private var router
    @Query private var todaysSessions: [WorkoutSession]
    @Query private var activeSessions: [WorkoutSession]
    @State private var now = Date()

    init(day: Date) {
        let range = DayBounds.range(containing: day)
        let start = range.lowerBound
        let end = range.upperBound
        let completed = WorkoutStatus.completed.rawValue
        let active = WorkoutStatus.active.rawValue
        _todaysSessions = Query(filter: #Predicate<WorkoutSession> { session in
            session.startedAt >= start && session.startedAt < end && session.statusRaw == completed
        }, sort: \WorkoutSession.startedAt, order: .reverse)
        _activeSessions = Query(filter: #Predicate<WorkoutSession> { session in
            session.statusRaw == active
        }, sort: \WorkoutSession.startedAt, order: .reverse)
    }

    var body: some View {
        FormCard {
            SectionHeader(title: "Workout") {
                Button("Train") { router.select(.train) }
                    .font(.subheadline.weight(.medium))
            }
            if let active = activeSessions.first {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    workoutSummary(title: active.name,
                                   status: active.clock.isPaused ? "Paused" : "In progress",
                                   symbol: active.clock.isPaused ? "pause.circle.fill" : "record.circle",
                                   duration: active.clock.elapsed(at: context.date),
                                   sets: active.completedSetCount,
                                   volume: active.totalVolumeKilograms)
                }
            } else if let finished = todaysSessions.first {
                workoutSummary(title: finished.name,
                               status: todaysSessions.count > 1 ? "Completed · \(todaysSessions.count) workouts today" : "Completed",
                               symbol: "checkmark.circle.fill",
                               duration: finished.clock.elapsed(at: now),
                               sets: finished.completedSetCount,
                               volume: finished.totalVolumeKilograms)
            } else {
                EmptyStateView(symbol: "dumbbell",
                               title: "No workout yet today",
                               message: "Pick a routine or start an empty workout from the Train tab.",
                               actionTitle: "Go to Train") {
                    router.select(.train)
                }
            }
        }
    }

    @ViewBuilder
    private func workoutSummary(title: String, status: String, symbol: String, duration: TimeInterval, sets: Int, volume: Double) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.formTextPrimary)
                Label(status, systemImage: symbol)
                    .font(.subheadline)
                    .foregroundStyle(Color.formAccent)
            }
            HStack {
                StatTile(title: "Duration", value: DurationText.clock(duration))
                StatTile(title: "Sets", value: "\(sets)")
                WeightStatTile(title: "Volume", kilograms: volume)
            }
        }
    }
}

/// Shows a kilogram value in the user's preferred unit.
struct WeightStatTile: View {
    let title: String
    let kilograms: Double
    @Query(sort: \UserPreferences.createdAt) private var preferences: [UserPreferences]

    var body: some View {
        let unit = preferences.first?.weightUnit ?? .kilograms
        StatTile(title: title,
                 value: kilograms > 0 ? NumberText.weight(kilograms: kilograms, unit: unit) : "—")
    }
}

/// Workouts this week and over the last four weeks, from completed sessions.
private struct TodayConsistencyCard: View {
    @Query private var recentSessions: [WorkoutSession]
    private let now: Date

    init(now: Date) {
        self.now = now
        let completed = WorkoutStatus.completed.rawValue
        let since = Calendar.current.date(byAdding: .day, value: -35, to: DayBounds.range(containing: now).lowerBound) ?? now
        _recentSessions = Query(filter: #Predicate<WorkoutSession> { session in
            session.statusRaw == completed && session.startedAt >= since
        }, sort: \WorkoutSession.startedAt, order: .reverse)
    }

    private var thisWeekCount: Int {
        let week = DayBounds.weekRange(containing: now)
        return recentSessions.filter { week.contains($0.startedAt) }.count
    }

    private var lastFourWeeksAverage: Double {
        let start = Calendar.current.date(byAdding: .day, value: -28, to: now) ?? now
        let count = recentSessions.filter { $0.startedAt >= start && $0.startedAt <= now }.count
        return Double(count) / 4
    }

    var body: some View {
        FormCard {
            SectionHeader("Consistency")
            if recentSessions.isEmpty {
                InlineNotice(symbol: "calendar", text: "Completed workouts will appear here so you can see your weekly rhythm.")
            } else {
                HStack {
                    StatTile(title: "This week", value: "\(thisWeekCount)", caption: thisWeekCount == 1 ? "workout" : "workouts")
                    StatTile(title: "4-week average", value: lastFourWeeksAverage.formatted(.number.precision(.fractionLength(0...1))), caption: "per week")
                    if let last = recentSessions.first {
                        StatTile(title: "Last workout", value: last.startedAt.formatted(.relative(presentation: .named)), caption: last.name)
                    }
                }
            }
        }
    }
}

/// Most recent body-weight entry, with a shortcut to log a new one.
private struct LatestBodyWeightCard: View {
    @Environment(AppRouter.self) private var router
    @Query private var weights: [BodyMeasurement]
    @Query(sort: \UserPreferences.createdAt) private var preferences: [UserPreferences]

    init() {
        let kind = MeasurementKind.bodyWeight.rawValue
        var descriptor = FetchDescriptor<BodyMeasurement>(
            predicate: #Predicate<BodyMeasurement> { $0.kindRaw == kind },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        _weights = Query(descriptor)
    }

    var body: some View {
        FormCard {
            SectionHeader(title: "Body weight") {
                Button("Log") { router.presentedSheet = .logBodyWeight }
                    .font(.subheadline.weight(.medium))
            }
            if let latest = weights.first {
                let unit = preferences.first?.weightUnit ?? .kilograms
                StatTile(title: latest.date.formatted(date: .abbreviated, time: .omitted),
                         value: NumberText.weight(kilograms: latest.value, unit: unit))
            } else {
                InlineNotice(symbol: "scalemass", text: "No body weight recorded yet.")
            }
        }
    }
}
