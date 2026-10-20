import SwiftUI
import SwiftData
import Charts
import FormCore

enum ProgressSection: String, CaseIterable, Identifiable {
    case workouts, exercises, body, nutrition

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workouts: return "Workouts"
        case .exercises: return "Exercises"
        case .body: return "Body"
        case .nutrition: return "Nutrition"
        }
    }
}

/// Progress tab root: charts and summaries for workouts, exercises, body
/// measurements and nutrition over a selectable date range. Every value
/// comes from stored records and recalculates when records change.
struct ProgressHomeView: View {
    @State private var section: ProgressSection = .workouts
    @State private var range: ProgressRange = .threeMonths
    @State private var addingMeasurement: MeasurementKind?
    @State private var bodyKind: MeasurementKind = .bodyWeight
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date()

    var body: some View {
        List {
            Section {
                Picker("Section", selection: $section) {
                    ForEach(ProgressSection.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Range", selection: $range) {
                    ForEach(ProgressRange.allCases) { option in
                        Text(option.displayName).tag(option)
                            .accessibilityLabel(option.accessibilityName)
                    }
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: Spacing.xxs, leading: 0, bottom: Spacing.xxs, trailing: 0))
            .onChange(of: section) { _, _ in HapticsManager.shared.selectionChanged() }
            .onChange(of: range) { _, _ in HapticsManager.shared.selectionChanged() }

            switch section {
            case .workouts:
                WorkoutProgressSections(range: range, now: now)
            case .exercises:
                ExerciseProgressSections(range: range, now: now)
            case .body:
                BodyProgressSections(kind: $bodyKind, range: range, now: now) { addingMeasurement = $0 }
            case .nutrition:
                NutritionProgressSections(range: range, now: now)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .formPageBackground()
        .navigationTitle("Progress")
        .toolbar {
            if section == .body {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addingMeasurement = bodyKind
                    } label: {
                        Image(systemName: "plus")
                            .frame(minWidth: Metrics.minimumTouchTarget, minHeight: Metrics.minimumTouchTarget)
                    }
                    .accessibilityLabel("Add \(bodyKind.displayName.lowercased()) entry")
                }
            }
        }
        .sheet(item: $addingMeasurement) { kind in
            MeasurementEntrySheet(kind: kind)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = Date() }
        }
    }
}

// MARK: - Workouts

private struct WorkoutProgressSections: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.statusRaw == "completed" }, sort: \WorkoutSession.startedAt)
    private var sessions: [WorkoutSession]
    @Query(sort: \UserPreferences.createdAt) private var preferences: [UserPreferences]
    let range: ProgressRange
    let now: Date

    private var weightUnit: WeightUnit { preferences.first?.weightUnit ?? .kilograms }

    var body: some View {
        let start = range.startDate(now: now) ?? sessions.first?.startedAt ?? now
        let inRange = sessions.filter { $0.startedAt >= start && $0.startedAt <= now }
        let dates = sessions.map(\.startedAt)
        let counts = ProgressAnalytics.counts(of: inRange.map(\.startedAt), per: range.bucket, from: start, to: now)
        let volumePoints = inRange.compactMap { session -> SeriesPoint? in
            let volume = session.totalVolumeKilograms
            return volume > 0 ? SeriesPoint(date: session.startedAt, value: weightUnit.fromKilograms(volume)) : nil
        }

        if sessions.isEmpty {
            Section {
                EmptyStateView(symbol: "chart.bar", title: "No workouts yet",
                               message: "Finish a workout and your counts, volume and consistency will appear here.")
            }
        } else {
            Section {
                HStack {
                    StatTile(title: "Workouts", value: "\(inRange.count)", caption: range.accessibilityName)
                    StatTile(title: "Per week", value: ProgressAnalytics.averagePerWeek(of: dates, from: start, now: now)
                                .formatted(.number.precision(.fractionLength(1))), caption: "average")
                    StatTile(title: "Streak", value: "\(ProgressAnalytics.weeklyStreak(of: dates, now: now))",
                             caption: "weeks in a row")
                }
            } header: {
                Text("Consistency")
            }

            Section {
                PeriodBarChart(counts: counts, component: range.bucket) { count in
                    "\(count) \(count == 1 ? "workout" : "workouts")"
                }
                .padding(.vertical, Spacing.xs)
            } header: {
                Text(range.bucket == .month ? "Workouts per month" : "Workouts per week")
            }

            Section {
                if volumePoints.isEmpty {
                    Text("No loaded sets in this range.").foregroundStyle(Color.formTextSecondary)
                } else {
                    PointSeriesChart(points: volumePoints, tint: .formFat) { value in
                        "\(value.formatted(.number.precision(.fractionLength(0)))) \(weightUnit.symbol)"
                    }
                    .padding(.vertical, Spacing.xs)
                }
            } header: {
                Text("Volume per workout")
            } footer: {
                Text("Volume is weight × reps for completed working and drop sets. Warm-ups are excluded. Tap a point to see its value.")
            }
        }
    }
}

// MARK: - Exercises

/// Summary of one exercise's history, built from completed sessions.
struct ExerciseHistorySummary: Identifiable {
    let id: UUID
    let name: String
    let trackingType: ExerciseTrackingType
    let occurrences: [WorkoutExercise]
    var lastDate: Date? { occurrences.last?.session?.startedAt }
}

private struct ExerciseProgressSections: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.statusRaw == "completed" }, sort: \WorkoutSession.startedAt)
    private var sessions: [WorkoutSession]
    @Query(sort: \UserPreferences.createdAt) private var preferences: [UserPreferences]
    let range: ProgressRange
    let now: Date
    @State private var search = ""

    private var weightUnit: WeightUnit { preferences.first?.weightUnit ?? .kilograms }

    private var summaries: [ExerciseHistorySummary] {
        var byID: [UUID: [WorkoutExercise]] = [:]
        for session in sessions {
            for workoutExercise in session.orderedExercises where !workoutExercise.isSkipped {
                guard let id = workoutExercise.exerciseID,
                      WorkoutCalculator.completedSetCount(workoutExercise.performances) > 0 else { continue }
                byID[id, default: []].append(workoutExercise)
            }
        }
        return byID.compactMap { id, occurrences in
            guard let latest = occurrences.last else { return nil }
            return ExerciseHistorySummary(id: id, name: latest.exerciseName, trackingType: latest.trackingType, occurrences: occurrences)
        }
        .sorted { ($0.lastDate ?? .distantPast) > ($1.lastDate ?? .distantPast) }
    }

    var body: some View {
        let all = summaries
        let filtered = TextSearch.rank(all, query: search, name: { $0.name })
        if all.isEmpty {
            Section {
                EmptyStateView(symbol: "dumbbell", title: "No exercise history",
                               message: "Complete sets in a workout to track weights, reps and personal records for each exercise.")
            }
        } else {
            Section {
                TextField("Search exercises", text: $search)
                    .autocorrectionDisabled()
                ForEach(filtered) { summary in
                    NavigationLink {
                        ExerciseProgressDetailView(summary: summary, range: range, now: now)
                    } label: {
                        ExerciseSummaryRow(summary: summary, weightUnit: weightUnit)
                    }
                }
            } header: {
                Text("Personal records")
            } footer: {
                Text("Records compare only sessions of the same exercise and tracking type. Open an exercise for its history.")
            }
        }
    }
}

private struct ExerciseSummaryRow: View {
    let summary: ExerciseHistorySummary
    let weightUnit: WeightUnit

    var body: some View {
        let bests = PersonalRecordCalculator.merge(summary.occurrences.map {
            PersonalRecordCalculator.bests(in: $0.performances, trackingType: summary.trackingType)
        })
        let primary = summary.trackingType.recordKinds.first
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.name).foregroundStyle(Color.formTextPrimary)
                Text("\(summary.occurrences.count) \(summary.occurrences.count == 1 ? "session" : "sessions")")
                    .formCaption()
            }
            Spacer()
            if let primary, let value = bests[primary] {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(RecordFormatter.text(primary, value: value, weightUnit: weightUnit))
                        .font(.body.weight(.semibold)).monospacedDigit()
                    Text(primary.displayName).formCaption()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Charts and records for one exercise.
struct ExerciseProgressDetailView: View {
    @Query(sort: \UserPreferences.createdAt) private var preferences: [UserPreferences]
    let summary: ExerciseHistorySummary
    let range: ProgressRange
    let now: Date

    enum Metric: String, CaseIterable, Identifiable {
        case topWeight, estimatedOneRepMax, volume, reps, duration, distance
        var id: String { rawValue }
        var title: String {
            switch self {
            case .topWeight: return "Top weight"
            case .estimatedOneRepMax: return "Est. 1RM"
            case .volume: return "Volume"
            case .reps: return "Best reps"
            case .duration: return "Duration"
            case .distance: return "Distance"
            }
        }
    }

    @State private var metric: Metric?

    private var weightUnit: WeightUnit { preferences.first?.weightUnit ?? .kilograms }

    private var metrics: [Metric] {
        switch summary.trackingType {
        case .weightAndReps: return [.topWeight, .estimatedOneRepMax, .volume, .reps]
        case .repsOnly: return [.reps]
        case .duration: return [.duration]
        case .distanceAndDuration: return [.distance, .duration]
        }
    }

    private var inRange: [WorkoutExercise] {
        let start = range.startDate(now: now) ?? .distantPast
        return summary.occurrences.filter { ($0.session?.startedAt ?? .distantPast) >= start }
    }

    private func value(_ metric: Metric, for occurrence: WorkoutExercise) -> Double? {
        let work = occurrence.performances.filter(\.countsAsWorkSet)
        switch metric {
        case .topWeight:
            return work.compactMap { ($0.reps ?? 0) > 0 ? $0.weightKilograms : nil }.max().map { weightUnit.fromKilograms($0) }
        case .estimatedOneRepMax:
            return work.compactMap { set in set.weightKilograms.flatMap { WorkoutCalculator.estimatedOneRepMax(weightKilograms: $0, reps: set.reps ?? 0) } }
                .max().map { weightUnit.fromKilograms($0) }
        case .volume:
            let volume = WorkoutCalculator.volume(of: occurrence.performances, trackingType: occurrence.trackingType)
            return volume > 0 ? weightUnit.fromKilograms(volume) : nil
        case .reps:
            return work.compactMap(\.reps).max().map(Double.init)
        case .duration:
            return work.compactMap(\.durationSeconds).max()
        case .distance:
            return work.compactMap(\.distanceMeters).max().map { DistanceUnit.matching(weightUnit).fromMeters($0) }
        }
    }

    private func format(_ metric: Metric, _ value: Double) -> String {
        switch metric {
        case .topWeight, .estimatedOneRepMax, .volume:
            return "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(weightUnit.symbol)"
        case .reps: return "\(Int(value)) reps"
        case .duration: return DurationText.clock(value)
        case .distance: return "\(value.formatted(.number.precision(.fractionLength(0...2)))) \(DistanceUnit.matching(weightUnit).symbol)"
        }
    }

    /// The date each current best was first achieved.
    private var recordDates: [(kind: RecordKind, value: Double, date: Date)] {
        var bests: [RecordKind: (Double, Date)] = [:]
        for occurrence in summary.occurrences {
            guard let date = occurrence.session?.startedAt else { continue }
            for (kind, value) in PersonalRecordCalculator.bests(in: occurrence.performances, trackingType: summary.trackingType) {
                if value > (bests[kind]?.0 ?? 0) + 0.000_1 { bests[kind] = (value, date) }
            }
        }
        return summary.trackingType.recordKinds.compactMap { kind in
            bests[kind].map { (kind, $0.0, $0.1) }
        }
    }

    var body: some View {
        let selectedMetric = metric ?? metrics[0]
        let points = inRange.compactMap { occurrence -> SeriesPoint? in
            guard let date = occurrence.session?.startedAt, let value = value(selectedMetric, for: occurrence) else { return nil }
            return SeriesPoint(date: date, value: value)
        }
        List {
            if metrics.count > 1 {
                Section {
                    Picker("Metric", selection: Binding(get: { selectedMetric }, set: { metric = $0 })) {
                        ForEach(metrics) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                if points.isEmpty {
                    Text("No sessions in this range.").foregroundStyle(Color.formTextSecondary)
                } else {
                    PointSeriesChart(points: points) { format(selectedMetric, $0) }
                        .padding(.vertical, Spacing.xs)
                }
            } header: {
                Text("\(selectedMetric.title) · \(range.accessibilityName)")
            } footer: {
                Text("Each point is one session's recorded value. Tap a point for its date and value.")
            }
            Section("Personal records") {
                ForEach(recordDates, id: \.kind) { record in
                    LabeledContent {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(RecordFormatter.text(record.kind, value: record.value, weightUnit: weightUnit))
                                .font(.body.weight(.semibold)).monospacedDigit()
                            Text(record.date.formatted(date: .abbreviated, time: .omitted)).formCaption()
                        }
                    } label: {
                        Text(record.kind.displayName)
                    }
                }
            }
            Section("Sessions") {
                ForEach(summary.occurrences.reversed()) { occurrence in
                    if let session = occurrence.session {
                        NavigationLink {
                            WorkoutSessionDetailView(session: session)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.startedAt.formatted(date: .abbreviated, time: .omitted))
                                    .foregroundStyle(Color.formTextPrimary)
                                Text(setSummary(occurrence)).formCaption().lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .formPageBackground()
        .navigationTitle(summary.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func setSummary(_ occurrence: WorkoutExercise) -> String {
        occurrence.performances.filter(\.countsAsWorkSet).map { set in
            switch summary.trackingType {
            case .weightAndReps:
                let weight = set.weightKilograms.map { NumberText.weight(kilograms: $0, unit: weightUnit) } ?? "–"
                return "\(weight) × \(set.reps.map(String.init) ?? "–")"
            case .repsOnly: return "\(set.reps ?? 0) reps"
            case .duration: return DurationText.clock(set.durationSeconds ?? 0)
            case .distanceAndDuration: return format(.distance, DistanceUnit.matching(weightUnit).fromMeters(set.distanceMeters ?? 0))
            }
        }
        .joined(separator: ", ")
    }
}

// MARK: - Body

private struct BodyProgressSections: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BodyMeasurement.date) private var measurements: [BodyMeasurement]
    @Query(sort: \UserPreferences.createdAt) private var preferences: [UserPreferences]
    @Binding var kind: MeasurementKind
    let range: ProgressRange
    let now: Date
    let add: (MeasurementKind) -> Void

    @State private var editing: BodyMeasurement?
    @State private var pendingDeletion: BodyMeasurement?
    @State private var errorMessage: String?

    private var weightUnit: WeightUnit { preferences.first?.weightUnit ?? .kilograms }
    private var lengthUnit: LengthUnit { preferences.first?.lengthUnit ?? .centimeters }

    private func display(_ value: Double) -> Double {
        switch kind.dimension {
        case .mass: return weightUnit.fromKilograms(value)
        case .length: return lengthUnit.fromCentimeters(value)
        case .percentage: return value
        }
    }

    private var unitSymbol: String {
        switch kind.dimension {
        case .mass: return weightUnit.symbol
        case .length: return lengthUnit.symbol
        case .percentage: return "%"
        }
    }

    var body: some View {
        let ofKind = measurements.filter { $0.kind == kind }
        let start = range.startDate(now: now) ?? .distantPast
        let inRange = ofKind.filter { $0.date >= start }
        let points = inRange.map { SeriesPoint(date: $0.date, value: display($0.value)) }

        Section {
            Picker("Measurement", selection: $kind) {
                ForEach(MeasurementKind.allCases) { Text($0.displayName).tag($0) }
            }
        }

        Section {
            if points.isEmpty {
                EmptyStateView(symbol: kind.symbol,
                               title: "No \(kind.displayName.lowercased()) entries\(range == .all ? "" : " in this range")",
                               message: "Only values you record are shown. Missing days are left as gaps.",
                               actionTitle: "Add entry") { add(kind) }
            } else {
                if let first = points.first, let last = points.last, points.count > 1 {
                    HStack {
                        StatTile(title: "Latest", value: formatted(last.value))
                        StatTile(title: "Change", value: signed(last.value - first.value), caption: "since \(first.date.formatted(.dateTime.day().month(.abbreviated)))")
                        StatTile(title: "Entries", value: "\(points.count)")
                    }
                }
                PointSeriesChart(points: points, tint: .formProtein) { formatted($0) }
                    .padding(.vertical, Spacing.xs)
            }
        } header: {
            Text(kind.displayName)
        } footer: {
            Text("Points are your recorded values; the dashed line only joins them and isn't an estimate.")
        }

        Section {
            ForEach(ofKind.reversed()) { measurement in
                Button {
                    editing = measurement
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(measurement.date.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(Color.formTextPrimary)
                            if !measurement.notes.isEmpty {
                                Text(measurement.notes).formCaption().lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(measurement.displayValue(weightUnit: weightUnit, lengthUnit: lengthUnit))
                            .font(.body.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(Color.formTextPrimary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the entry for editing")
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { pendingDeletion = measurement } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button { editing = measurement } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { pendingDeletion = measurement } label: { Label("Delete", systemImage: "trash") }
                }
            }
        } header: {
            Text("History")
        } footer: {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(Color.formDestructive)
            }
        }
        .sheet(item: $editing) { measurement in
            MeasurementEntrySheet(editing: measurement, displayText: NumberText.editable(display(measurement.value), maxFractionDigits: 1))
        }
        .confirmationDialog("Delete this entry?",
                            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingDeletion) { measurement in
            Button("Delete", role: .destructive) { delete(measurement) }
        } message: { measurement in
            Text("\(measurement.displayValue(weightUnit: weightUnit, lengthUnit: lengthUnit)) on \(measurement.date.formatted(date: .abbreviated, time: .omitted)) will be removed. This can't be undone.")
        }
    }

    private func formatted(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unitSymbol)"
    }

    private func signed(_ value: Double) -> String {
        let sign = value > 0 ? "+" : (value < 0 ? "−" : "±")
        return "\(sign)\(abs(value).formatted(.number.precision(.fractionLength(0...1)))) \(unitSymbol)"
    }

    private func delete(_ measurement: BodyMeasurement) {
        modelContext.delete(measurement)
        if let error = modelContext.saveReportingErrors() {
            modelContext.rollback()
            errorMessage = "Couldn't delete: \(error.localizedDescription)"
            HapticsManager.shared.error()
        } else {
            errorMessage = nil
        }
        pendingDeletion = nil
    }
}

// MARK: - Nutrition

/// Daily nutrition from diary snapshots. Only days with entries are plotted
/// and averaged; a day with nothing logged is a gap, never a zero.
private struct NutritionProgressSections: View {
    @Query private var entries: [FoodLogEntry]
    @Query(sort: \DailyNutritionGoal.effectiveFrom, order: .reverse) private var goals: [DailyNutritionGoal]
    let range: ProgressRange
    let now: Date

    init(range: ProgressRange, now: Date) {
        self.range = range
        self.now = now
        let start = range.startDate(now: now) ?? .distantPast
        _entries = Query(filter: #Predicate<FoodLogEntry> { $0.day >= start }, sort: \FoodLogEntry.day)
    }

    var body: some View {
        let days = Self.totalsByDay(entries)
        let snapshots = goals.map(\.snapshot)
        let currentTargets = GoalResolver.goal(on: now, from: snapshots)?.targets

        if days.isEmpty {
            Section {
                EmptyStateView(symbol: "fork.knife",
                               title: "No diary entries\(range == .all ? "" : " in this range")",
                               message: "Daily totals appear here once you log food. Days without entries are left out, not counted as zero.")
            }
        } else {
            ForEach([Nutrient.calories, .protein, .carbohydrates, .fat]) { nutrient in
                NutrientTrendSection(nutrient: nutrient,
                                     days: days,
                                     target: currentTargets?[nutrient],
                                     daysOnTarget: Self.daysOnTarget(days, nutrient: nutrient, goals: snapshots))
            }
        }
    }

    static func totalsByDay(_ entries: [FoodLogEntry]) -> [Date: NutritionTotals] {
        let calendar = Calendar.current
        var days: [Date: NutritionTotals] = [:]
        for entry in entries {
            days[calendar.startOfDay(for: entry.day), default: NutritionTotals()].add(entry.nutrition)
        }
        return days
    }

    /// Logged days (with this nutrient recorded) that reached the goal in effect *that day*.
    static func daysOnTarget(_ days: [Date: NutritionTotals], nutrient: Nutrient, goals: [NutritionGoalSnapshot]) -> (reached: Int, judged: Int)? {
        var reached = 0
        var judged = 0
        for (day, totals) in days where totals.missingCount(for: nutrient) < totals.entryCount {
            guard let target = GoalResolver.goal(on: day, from: goals)?.targets[nutrient] else { continue }
            let progress = TargetProgress(consumed: totals.total(for: nutrient), target: target,
                                          tolerance: nutrient == .calories ? 50 : 5)
            guard progress.hasTarget else { continue }
            judged += 1
            if progress.status == .reached { reached += 1 }
        }
        return judged > 0 ? (reached, judged) : nil
    }
}

private struct NutrientTrendSection: View {
    let nutrient: Nutrient
    let days: [Date: NutritionTotals]
    let target: Double?
    let daysOnTarget: (reached: Int, judged: Int)?

    @State private var selectedDate: Date?

    private var points: [SeriesPoint] {
        days.compactMap { day, totals in
            guard totals.entryCount > 0, totals.missingCount(for: nutrient) < totals.entryCount else { return nil }
            return SeriesPoint(date: day, value: totals.total(for: nutrient))
        }
        .sorted { $0.date < $1.date }
    }

    private var tint: Color {
        switch nutrient {
        case .calories: return .formAccent
        case .protein: return .formProtein
        case .carbohydrates: return .formCarbs
        case .fat: return .formFat
        }
    }

    var body: some View {
        let points = points
        let average = ProgressAnalytics.dailyAverage(days, nutrient: nutrient)
        let incompleteDays = days.values.filter { $0.missingCount(for: nutrient) > 0 }.count
        let selected = selectedDate.flatMap { ProgressAnalytics.nearest(to: $0, in: points) }

        Section {
            if points.isEmpty {
                Text("No \(nutrient.displayName.lowercased()) values recorded in this range.")
                    .formCaption()
            } else {
                HStack {
                    StatTile(title: "Daily average",
                             value: format(average?.average ?? 0),
                             caption: "over \(average?.days ?? 0) logged day\(average?.days == 1 ? "" : "s")")
                    if let target {
                        StatTile(title: "Current target", value: format(target))
                    }
                    if let daysOnTarget {
                        StatTile(title: "On target", value: "\(daysOnTarget.reached)/\(daysOnTarget.judged)", caption: "days")
                    }
                }
                Chart {
                    ForEach(points) { point in
                        BarMark(x: .value("Day", point.date, unit: .day), y: .value(nutrient.displayName, point.value))
                            .foregroundStyle(selected == nil || selected?.date == point.date ? tint : tint.opacity(0.45))
                    }
                    if let target {
                        RuleMark(y: .value("Target", target))
                            .foregroundStyle(Color.formTextSecondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("Target").font(.caption2).foregroundStyle(Color.formTextSecondary)
                            }
                    }
                    if let selected {
                        RuleMark(x: .value("Selected", selected.date, unit: .day))
                            .foregroundStyle(.clear)
                            .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                ChartValueBubble(title: selected.date.formatted(date: .abbreviated, time: .omitted),
                                                 value: format(selected.value))
                            }
                    }
                }
                .chartXSelection(value: $selectedDate)
                .frame(height: 180)
                .padding(.vertical, Spacing.xs)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(nutrient.displayName) per logged day")
                .accessibilityValue(accessibilitySummary(points: points, average: average?.average))
                .onChange(of: selected?.date) { old, new in
                    if new != nil && new != old { HapticsManager.shared.selectionChanged() }
                }
            }
        } header: {
            Text(nutrient.displayName)
        } footer: {
            if incompleteDays > 0 {
                Text("\(incompleteDays) day\(incompleteDays == 1 ? " has" : "s have") entries without a \(nutrient.displayName.lowercased()) value, so \(incompleteDays == 1 ? "its total is" : "their totals are") a lower bound.")
            }
        }
    }

    private func format(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0)))) \(nutrient.unitSymbol)"
    }

    private func accessibilitySummary(points: [SeriesPoint], average: Double?) -> String {
        var parts = ["\(points.count) logged days"]
        if let average { parts.append("average \(format(average))") }
        if let target { parts.append("target \(format(target))") }
        if let low = points.min(by: { $0.value < $1.value }), let high = points.max(by: { $0.value < $1.value }) {
            parts.append("lowest \(format(low.value)) on \(low.date.formatted(date: .abbreviated, time: .omitted))")
            parts.append("highest \(format(high.value)) on \(high.date.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: ", ")
    }
}
