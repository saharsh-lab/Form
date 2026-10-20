import SwiftUI
import SwiftData
import FormCore

/// Finds the in-progress workout and shows it; closes itself if there is none.
struct ActiveWorkoutContainer: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<WorkoutSession> { $0.statusRaw == "active" },
           sort: \WorkoutSession.startedAt, order: .reverse)
    private var activeSessions: [WorkoutSession]
    @State private var finishedSummary: FinishedWorkout?

    var body: some View {
        NavigationStack {
            if let summary = finishedSummary {
                WorkoutSummaryView(summary: summary) { dismiss() }
            } else if let session = activeSessions.first {
                ActiveWorkoutView(session: session) { summary in
                    finishedSummary = summary
                }
            } else {
                EmptyStateView(symbol: "dumbbell", title: "No workout in progress",
                               message: "Start a workout from the Train tab.",
                               actionTitle: "Close") { dismiss() }
                    .formPageBackground()
            }
        }
    }
}

/// What the summary screen shows after finishing.
struct FinishedWorkout: Identifiable {
    let id = UUID()
    let name: String
    let duration: TimeInterval
    let completedSets: Int
    let volumeKilograms: Double
    let records: [WorkoutRepository.AchievedRecord]
}

/// The live workout logger: exercises, set rows with previous values,
/// elapsed time, rest timer, pause/resume, finish and discard.
struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \UserPreferences.createdAt) private var preferences: [UserPreferences]

    @Bindable var session: WorkoutSession
    var onFinished: (FinishedWorkout) -> Void

    @State private var showingExercisePicker = false
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var errorMessage: String?
    @State private var isFinishing = false

    private var repository: WorkoutRepository { WorkoutRepository(context: modelContext) }
    private var weightUnit: WeightUnit { preferences.first?.weightUnit ?? .kilograms }
    private var defaultRest: TimeInterval { TimeInterval(preferences.first?.defaultRestSeconds ?? 90) }
    private var notificationsEnabled: Bool { preferences.first?.restTimerNotificationsEnabled ?? false }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.m) {
                header
                if let errorMessage {
                    InlineNotice(symbol: "exclamationmark.triangle", text: errorMessage, tint: .formDestructive)
                }
                if session.exercises.isEmpty {
                    FormCard {
                        EmptyStateView(symbol: "plus.circle", title: "Add your first exercise",
                                       message: "Pick from your exercise library. Sets, weights and reps are saved as you go.",
                                       actionTitle: "Add exercise") { showingExercisePicker = true }
                    }
                }
                ForEach(session.orderedExercises) { workoutExercise in
                    ExerciseLogCard(workoutExercise: workoutExercise,
                                    previous: repository.previousPerformance(for: workoutExercise.exerciseID ?? UUID(), excluding: session.id),
                                    weightUnit: weightUnit,
                                    isFirst: workoutExercise.sortIndex == session.orderedExercises.first?.sortIndex,
                                    isLast: workoutExercise.sortIndex == session.orderedExercises.last?.sortIndex,
                                    perform: perform,
                                    onSetCompleted: setCompleted)
                }
                if !session.exercises.isEmpty {
                    Button {
                        showingExercisePicker = true
                    } label: {
                        Label("Add exercise", systemImage: "plus")
                    }
                    .buttonStyle(FormSecondaryButtonStyle())
                }
                Button("Discard workout", role: .destructive) { confirmDiscard = true }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: Metrics.minimumTouchTarget)
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .formPageBackground()
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            RestTimerBar(session: session, defaultDuration: defaultRest, perform: perform, onTimerChange: syncNotification)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .frame(minWidth: Metrics.minimumTouchTarget, minHeight: Metrics.minimumTouchTarget)
                }
                .accessibilityLabel("Minimise workout")
                .accessibilityHint("The workout keeps running")
            }
            ToolbarItem(placement: .principal) {
                Button {
                    newName = session.name
                    renaming = true
                } label: {
                    Text(session.name).font(.headline).foregroundStyle(Color.formTextPrimary)
                }
                .accessibilityHint("Renames the workout")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Finish") { confirmFinish = true }
                    .fontWeight(.semibold)
                    .disabled(isFinishing)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerSheet { exercise in
                perform { try repository.addExercise(exercise, to: session) }
            }
        }
        .confirmationDialog("Finish workout?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish workout", action: finish)
            Button("Keep training", role: .cancel) {}
        } message: {
            Text(finishMessage)
        }
        .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard workout", role: .destructive, action: discard)
            Button("Keep workout", role: .cancel) {}
        } message: {
            Text("Everything logged in this workout will be deleted. This can't be undone.")
        }
        .alert("Rename workout", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Save") {
                if case .success(let name) = InputValidator.name(newName, maximumLength: 60) {
                    session.name = name
                    perform { try modelContext.save() }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { HapticsManager.shared.prepareForSetLogging() }
    }

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(DurationText.clock(session.clock.elapsed(at: context.date)))
                        .formNumeric(.largeTitle, weight: .bold)
                        .foregroundStyle(session.clock.isPaused ? Color.formTextSecondary : Color.formTextPrimary)
                        .accessibilityLabel("Elapsed time \(DurationText.summary(session.clock.elapsed(at: context.date)))")
                    HStack(spacing: Spacing.s) {
                        if session.clock.isPaused {
                            Label("Paused", systemImage: "pause.circle.fill")
                                .foregroundStyle(Color.formWarning)
                        }
                        Text("\(session.completedSetCount) sets")
                        if session.totalVolumeKilograms > 0 {
                            Text(NumberText.weight(kilograms: session.totalVolumeKilograms, unit: weightUnit))
                        }
                    }
                    .formCaption()
                }
                Spacer()
                Button {
                    if session.clock.isPaused {
                        perform { try repository.resume(session) }
                    } else {
                        perform { try repository.pause(session) }
                        NotificationScheduler.cancelRestTimerAlert()
                    }
                } label: {
                    Label(session.clock.isPaused ? "Resume" : "Pause",
                          systemImage: session.clock.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(FormSecondaryButtonStyle(fullWidth: false))
            }
            .padding(.top, Spacing.xs)
        }
    }

    private var finishMessage: String {
        let incomplete = session.exercises.filter { !$0.isSkipped }.flatMap(\.sets).filter { !$0.isCompleted }.count
        if session.completedSetCount == 0 {
            return "No sets are marked complete yet. The workout will be saved with no completed sets."
        }
        if incomplete > 0 {
            return "\(incomplete) \(incomplete == 1 ? "set isn't" : "sets aren't") marked complete and won't count towards volume or records."
        }
        return "Your workout will be saved to your history."
    }

    // MARK: Actions

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            HapticsManager.shared.error()
        }
    }

    private func setCompleted(_ set: WorkoutSet) {
        perform {
            let completed = try repository.toggleCompletion(of: set, restDuration: defaultRest)
            if completed { HapticsManager.shared.setCompleted() }
        }
        syncNotification()
    }

    /// Keeps the optional "rest finished" notification in step with the timer.
    private func syncNotification() {
        guard notificationsEnabled, let timer = session.restTimer, let end = timer.endDate else {
            NotificationScheduler.cancelRestTimerAlert()
            return
        }
        let current = session.orderedExercises.last { $0.sets.contains { $0.isCompleted } }?.exerciseName
        NotificationScheduler.scheduleRestTimerAlert(at: end, exerciseName: current)
    }

    private func finish() {
        guard !isFinishing else { return }
        isFinishing = true
        defer { isFinishing = false }
        do {
            let records = try repository.finish(session)
            NotificationScheduler.cancelRestTimerAlert()
            let summary = FinishedWorkout(name: session.name,
                                          duration: session.clock.elapsed(at: .now),
                                          completedSets: session.completedSetCount,
                                          volumeKilograms: session.totalVolumeKilograms,
                                          records: records)
            if records.isEmpty {
                HapticsManager.shared.saveSucceeded()
            } else {
                HapticsManager.shared.personalRecord()
            }
            onFinished(summary)
        } catch {
            errorMessage = error.localizedDescription
            HapticsManager.shared.error()
        }
    }

    private func discard() {
        do {
            try repository.discard(session)
            NotificationScheduler.cancelRestTimerAlert()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            HapticsManager.shared.error()
        }
    }
}

/// One exercise in the active workout with its set rows.
struct ExerciseLogCard: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var workoutExercise: WorkoutExercise
    let previous: [SetPerformance]
    let weightUnit: WeightUnit
    let isFirst: Bool
    let isLast: Bool
    let perform: (() throws -> Void) -> Void
    let onSetCompleted: (WorkoutSet) -> Void
    /// False when reviewing history, where "previous" values don't apply.
    var showsPrevious = true

    private var repository: WorkoutRepository { WorkoutRepository(context: modelContext) }

    var body: some View {
        FormCard(padding: Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workoutExercise.exerciseName)
                        .font(.headline)
                        .foregroundStyle(workoutExercise.isSkipped ? Color.formTextSecondary : Color.formTextPrimary)
                        .strikethrough(workoutExercise.isSkipped)
                    if workoutExercise.isSkipped {
                        Text("Skipped").formCaption()
                    } else if showsPrevious && previous.isEmpty {
                        Text("First time logging this exercise").formCaption()
                    }
                }
                Spacer()
                menu
            }

            if !workoutExercise.isSkipped {
                SetColumnsHeader(trackingType: workoutExercise.trackingType, weightUnit: weightUnit)
                ForEach(Array(workoutExercise.orderedSets.enumerated()), id: \.element.id) { index, set in
                    SetRow(set: set,
                           label: label(for: set, at: index),
                           previous: index < previous.count ? previous[index] : nil,
                           trackingType: workoutExercise.trackingType,
                           weightUnit: weightUnit,
                           perform: perform,
                           onToggle: { onSetCompleted(set) })
                }
                HStack {
                    Button {
                        perform { try repository.addSet(to: workoutExercise) }
                    } label: {
                        Label("Add set", systemImage: "plus")
                            .font(.subheadline.weight(.medium))
                            .frame(minHeight: Metrics.minimumTouchTarget)
                    }
                    Spacer()
                }
            }
        }
    }

    private var menu: some View {
        Menu {
            if !workoutExercise.isSkipped {
                Button { perform { try repository.addSet(to: workoutExercise, kind: .warmUp) } } label: {
                    Label("Add warm-up set", systemImage: "flame")
                }
                Button { perform { try repository.addSet(to: workoutExercise, kind: .drop) } } label: {
                    Label("Add drop set", systemImage: "arrow.down.right")
                }
            }
            Button { perform { try repository.setSkipped(workoutExercise, !workoutExercise.isSkipped) } } label: {
                Label(workoutExercise.isSkipped ? "Unskip exercise" : "Skip exercise",
                      systemImage: workoutExercise.isSkipped ? "arrow.uturn.backward" : "forward")
            }
            if !isFirst {
                Button { perform { try repository.move(workoutExercise, by: -1) } } label: { Label("Move up", systemImage: "arrow.up") }
            }
            if !isLast {
                Button { perform { try repository.move(workoutExercise, by: 1) } } label: { Label("Move down", systemImage: "arrow.down") }
            }
            Button(role: .destructive) { perform { try repository.remove(workoutExercise) } } label: {
                Label("Remove exercise", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .frame(minWidth: Metrics.minimumTouchTarget, minHeight: Metrics.minimumTouchTarget)
        }
        .accessibilityLabel("\(workoutExercise.exerciseName) options")
    }

    /// Working sets are numbered; warm-up and drop sets show a letter.
    private func label(for set: WorkoutSet, at index: Int) -> String {
        if let badge = set.kind.badge { return badge }
        let workingBefore = workoutExercise.orderedSets.prefix(index).filter { $0.kind == .working }.count
        return "\(workingBefore + 1)"
    }
}

struct SetColumnsHeader: View {
    let trackingType: ExerciseTrackingType
    let weightUnit: WeightUnit

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Text("Set").frame(width: 32)
            Text("Previous").frame(maxWidth: .infinity, alignment: .leading)
            switch trackingType {
            case .weightAndReps:
                Text(weightUnit.symbol).frame(width: 72)
                Text("Reps").frame(width: 56)
            case .repsOnly:
                Text("Reps").frame(width: 72)
            case .duration:
                Text("Seconds").frame(width: 80)
            case .distanceAndDuration:
                Text(DistanceUnit.matching(weightUnit).symbol).frame(width: 64)
                Text("Sec").frame(width: 64)
            }
            Image(systemName: "checkmark").frame(width: Metrics.minimumTouchTarget)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color.formTextSecondary)
        .accessibilityHidden(true)
    }
}

/// One set: kind badge, previous value, editable fields and a completion button.
struct SetRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var set: WorkoutSet
    let label: String
    let previous: SetPerformance?
    let trackingType: ExerciseTrackingType
    let weightUnit: WeightUnit
    let perform: (() throws -> Void) -> Void
    let onToggle: () -> Void

    private var repository: WorkoutRepository { WorkoutRepository(context: modelContext) }
    private var distanceUnit: DistanceUnit { DistanceUnit.matching(weightUnit) }
    private let numberFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2)).grouping(.never)

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Menu {
                Picker("Set type", selection: Binding(get: { set.kind }, set: { kind in
                    perform { try repository.update(set, kind: kind) }
                })) {
                    ForEach(SetKind.allCases) { kind in Text(kind.displayName).tag(kind) }
                }
                Button(role: .destructive) { perform { try repository.remove(set) } } label: {
                    Label("Delete set", systemImage: "trash")
                }
            } label: {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(set.kind == .working ? Color.formTextPrimary : Color.formWarning)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.formSurfaceSecondary))
            }
            .accessibilityLabel("\(set.kind.displayName) set \(label)")
            .accessibilityHint("Change set type or delete")

            Text(previousText)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Color.formTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(previous == nil ? "No previous value" : "Previous \(previousText)")

            fields

            Button(action: onToggle) {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(set.isCompleted ? Color.formAccent : Color.formTextSecondary)
                    .frame(width: Metrics.minimumTouchTarget, height: Metrics.minimumTouchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(set.isCompleted ? "Completed" : "Mark complete")
            .accessibilityAddTraits(set.isCompleted ? .isSelected : [])
        }
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(set.isCompleted ? Color.formAccentSoft.opacity(0.6) : Color.clear)
        )
    }

    @ViewBuilder
    private var fields: some View {
        switch trackingType {
        case .weightAndReps:
            numberField("Weight", value: weightBinding, width: 72)
            integerField("Reps", value: repsBinding, width: 56)
        case .repsOnly:
            integerField("Reps", value: repsBinding, width: 72)
        case .duration:
            numberField("Seconds", value: durationBinding, width: 80)
        case .distanceAndDuration:
            numberField("Distance", value: distanceBinding, width: 64)
            numberField("Seconds", value: durationBinding, width: 64)
        }
    }

    private func numberField(_ title: String, value: Binding<Double?>, width: CGFloat) -> some View {
        TextField(title, value: value, format: numberFormat)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .frame(width: width, height: 36)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.formSurfaceSecondary))
            .accessibilityLabel(title)
    }

    private func integerField(_ title: String, value: Binding<Int?>, width: CGFloat) -> some View {
        TextField(title, value: value, format: .number.grouping(.never))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .frame(width: width, height: 36)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.formSurfaceSecondary))
            .accessibilityLabel(title)
    }

    // Bindings convert between the user's units and canonical storage and save on commit.

    private var weightBinding: Binding<Double?> {
        Binding(
            get: { set.weightKilograms.map { weightUnit.fromKilograms($0) } },
            set: { newValue in
                let clamped = newValue.map { min(max($0, 0), 2_000) }
                perform { try repository.update(set, weightKilograms: .some(clamped.map { weightUnit.toKilograms($0) })) }
            }
        )
    }

    private var repsBinding: Binding<Int?> {
        Binding(
            get: { set.reps },
            set: { newValue in perform { try repository.update(set, reps: .some(newValue.map { min(max($0, 0), 1_000) })) } }
        )
    }

    private var durationBinding: Binding<Double?> {
        Binding(
            get: { set.durationSeconds },
            set: { newValue in perform { try repository.update(set, durationSeconds: .some(newValue.map { min(max($0, 0), 86_400) })) } }
        )
    }

    private var distanceBinding: Binding<Double?> {
        Binding(
            get: { set.distanceMeters.map { distanceUnit.fromMeters($0) } },
            set: { newValue in
                perform { try repository.update(set, distanceMeters: .some(newValue.map { distanceUnit.toMeters(min(max($0, 0), 1_000)) })) }
            }
        )
    }

    private var previousText: String {
        guard let previous else { return "—" }
        switch trackingType {
        case .weightAndReps:
            let weight = previous.weightKilograms.map { NumberText.weight(kilograms: $0, unit: weightUnit) } ?? "–"
            return "\(weight) × \(previous.reps.map(String.init) ?? "–")"
        case .repsOnly:
            return previous.reps.map { "\($0) reps" } ?? "—"
        case .duration:
            return previous.durationSeconds.map { DurationText.clock($0) } ?? "—"
        case .distanceAndDuration:
            let distance = previous.distanceMeters.map {
                "\(distanceUnit.fromMeters($0).formatted(.number.precision(.fractionLength(0...2)))) \(distanceUnit.symbol)"
            } ?? "–"
            return "\(distance) · \(previous.durationSeconds.map { DurationText.clock($0) } ?? "–")"
        }
    }
}

/// Bottom bar with the rest countdown and its controls.
struct RestTimerBar: View {
    @Bindable var session: WorkoutSession
    let defaultDuration: TimeInterval
    let perform: (() throws -> Void) -> Void
    let onTimerChange: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var repository: WorkoutRepository { WorkoutRepository(context: modelContext) }
    private var timer: RestTimer { session.restTimer ?? RestTimer(duration: defaultDuration) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let now = context.date
            let remaining = timer.remaining(at: now)
            let finished = timer.phase == .finished || (timer.isRunning && remaining <= 0)
            VStack(spacing: Spacing.xs) {
                HStack(spacing: Spacing.s) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(finished ? "Rest complete" : (timer.isActive ? "Rest" : "Rest timer"))
                            .formCaption()
                        Text(finished ? "Go!" : DurationText.clock(remaining))
                            .formNumeric(.title2, weight: .bold)
                            .foregroundStyle(finished ? Color.formAccent : Color.formTextPrimary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(finished ? "Rest complete" : "Rest, \(DurationText.summary(remaining)) remaining")
                    Spacer()
                    controls(finished: finished)
                }
                ProgressView(value: finished ? 1 : timer.progress(at: now))
                    .tint(Color.formAccent)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .background(.bar)
        }
        .task(id: session.restTimerData) {
            await waitForCompletion()
        }
        .disabled(session.clock.isPaused)
    }

    @ViewBuilder
    private func controls(finished: Bool) -> some View {
        HStack(spacing: Spacing.xs) {
            if timer.isActive {
                timerButton("minus", label: "Subtract 15 seconds") { change { $0.adjust(by: -15, at: .now) } }
                timerButton("plus", label: "Add 15 seconds") { change { $0.adjust(by: 15, at: .now) } }
                if timer.isRunning {
                    timerButton("pause.fill", label: "Pause rest") { change { $0.pause(at: .now) } }
                } else {
                    timerButton("play.fill", label: "Resume rest") { change { $0.resume(at: .now) } }
                }
                timerButton("forward.end.fill", label: "Skip rest") { change { $0.skip() } }
            } else if finished {
                timerButton("arrow.counterclockwise", label: "Reset rest timer") { change { $0.reset() } }
            } else {
                timerButton("minus", label: "Shorter rest") { change { $0.adjust(by: -15, at: .now) } }
                timerButton("plus", label: "Longer rest") { change { $0.adjust(by: 15, at: .now) } }
                Button("Start") { change { $0.start(at: .now) } }
                    .buttonStyle(FormPrimaryButtonStyle(fullWidth: false))
            }
        }
    }

    private func timerButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: Metrics.minimumTouchTarget, height: Metrics.minimumTouchTarget)
                .background(Circle().fill(Color.formSurfaceSecondary))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.formTextPrimary)
        .accessibilityLabel(label)
    }

    private func change(_ mutation: @escaping (inout RestTimer) -> Void) {
        perform { try repository.updateRestTimer(of: session, mutation, defaultDuration: defaultDuration) }
        onTimerChange()
    }

    /// Sleeps until the timer's end date, then marks it finished and gives
    /// feedback. Only runs while the view is on screen; elapsed time is always
    /// derived from the stored end date, so nothing drifts in the background.
    private func waitForCompletion() async {
        guard let end = session.restTimer?.endDate else { return }
        let wait = end.timeIntervalSinceNow
        if wait > 0 {
            try? await Task.sleep(for: .seconds(wait))
        }
        guard !Task.isCancelled, var timer = session.restTimer else { return }
        if timer.refresh(at: .now) {
            session.restTimer = timer
            try? modelContext.save()
            HapticsManager.shared.timerFinished()
            UIAccessibility.post(notification: .announcement, argument: "Rest complete")
        }
    }
}

/// Shown after finishing: duration, sets, volume and any personal records.
struct WorkoutSummaryView: View {
    @Query(sort: \UserPreferences.createdAt) private var preferences: [UserPreferences]
    let summary: FinishedWorkout
    let onDone: () -> Void

    private var weightUnit: WeightUnit { preferences.first?.weightUnit ?? .kilograms }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                Image(systemName: summary.records.isEmpty ? "checkmark.seal.fill" : "trophy.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(summary.records.isEmpty ? Color.formAccent : Color.formCarbs)
                    .padding(.top, Spacing.xl)
                    .accessibilityHidden(true)
                VStack(spacing: Spacing.xxs) {
                    Text("Workout saved")
                        .font(.title.weight(.bold))
                    Text(summary.name).formCaption()
                }
                FormCard {
                    HStack {
                        StatTile(title: "Duration", value: DurationText.summary(summary.duration))
                        StatTile(title: "Sets", value: "\(summary.completedSets)")
                        StatTile(title: "Volume", value: summary.volumeKilograms > 0 ? NumberText.weight(kilograms: summary.volumeKilograms, unit: weightUnit) : "—")
                    }
                }
                if !summary.records.isEmpty {
                    FormCard {
                        SectionHeader("Personal records")
                        ForEach(summary.records) { record in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.exerciseName).foregroundStyle(Color.formTextPrimary)
                                    Text(record.kind.displayName).formCaption()
                                }
                                Spacer()
                                Text(RecordFormatter.text(record.kind, value: record.value, weightUnit: weightUnit))
                                    .font(.body.weight(.semibold))
                                    .monospacedDigit()
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.m)
        }
        .formPageBackground()
        .safeAreaInset(edge: .bottom) {
            Button("Done", action: onDone)
                .buttonStyle(FormPrimaryButtonStyle())
                .padding(Spacing.m)
        }
        .navigationBarBackButtonHidden()
    }
}

enum RecordFormatter {
    static func text(_ kind: RecordKind, value: Double, weightUnit: WeightUnit) -> String {
        switch kind {
        case .heaviestWeight, .bestEstimatedOneRepMax, .bestSetVolume:
            return NumberText.weight(kilograms: value, unit: weightUnit)
        case .mostReps:
            return "\(Int(value)) reps"
        case .longestDuration:
            return DurationText.clock(value)
        case .longestDistance:
            let unit = DistanceUnit.matching(weightUnit)
            return "\(unit.fromMeters(value).formatted(.number.precision(.fractionLength(0...2)))) \(unit.symbol)"
        }
    }
}
