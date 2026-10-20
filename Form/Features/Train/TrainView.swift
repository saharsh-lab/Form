import SwiftUI
import SwiftData
import FormCore

/// Train tab root: resume or start a workout, manage routines, open the
/// exercise library and workout history.
struct TrainView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Query(sort: \WorkoutRoutine.sortIndex) private var routines: [WorkoutRoutine]
    @Query(filter: #Predicate<WorkoutSession> { $0.statusRaw == "active" }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var activeSessions: [WorkoutSession]
    @Query(filter: #Predicate<WorkoutSession> { $0.statusRaw == "completed" })
    private var completedSessions: [WorkoutSession]

    @State private var errorMessage: String?
    @State private var pendingDeletion: WorkoutRoutine?
    @State private var newRoutine: WorkoutRoutine?
    @State private var isStarting = false

    private var workoutRepository: WorkoutRepository { WorkoutRepository(context: modelContext) }
    private var routineRepository: RoutineRepository { RoutineRepository(context: modelContext) }

    var body: some View {
        List {
            Section {
                if let active = activeSessions.first {
                    ActiveWorkoutBanner(session: active) { router.isActiveWorkoutPresented = true }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } else {
                    Button {
                        start { try workoutRepository.startEmptyWorkout() }
                    } label: {
                        Label("Start empty workout", systemImage: "plus")
                    }
                    .buttonStyle(FormPrimaryButtonStyle())
                    .disabled(isStarting)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            } footer: {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.formDestructive)
                }
            }

            Section {
                if routines.isEmpty {
                    EmptyStateView(symbol: "list.bullet.rectangle",
                                   title: "No routines yet",
                                   message: "Routines are reusable workout plans with target sets and reps.",
                                   actionTitle: "Create routine", action: createRoutine)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(routines) { routine in
                        NavigationLink {
                            RoutineDetailView(routine: routine)
                        } label: {
                            RoutineRow(routine: routine)
                        }
                        .contextMenu {
                            Button { start { try workoutRepository.startWorkout(from: routine) } } label: {
                                Label("Start workout", systemImage: "play.fill")
                            }
                            .disabled(!activeSessions.isEmpty)
                            Button { perform { try routineRepository.duplicate(routine, sortIndex: routines.count) } } label: {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }
                            Button(role: .destructive) { pendingDeletion = routine } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { pendingDeletion = routine } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button { perform { try routineRepository.duplicate(routine, sortIndex: routines.count) } } label: {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }
                            .tint(Color.formFat)
                        }
                    }
                    .onMove { source, destination in
                        perform { try routineRepository.moveRoutines(routines, from: source, to: destination) }
                    }
                }
            } header: {
                HStack {
                    Text("Routines")
                    Spacer()
                    Button(action: createRoutine) {
                        Image(systemName: "plus")
                            .frame(minWidth: Metrics.minimumTouchTarget, minHeight: 32)
                    }
                    .accessibilityLabel("New routine")
                }
            }

            Section {
                NavigationLink {
                    WorkoutHistoryView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("History").foregroundStyle(Color.formTextPrimary)
                            Text("\(completedSessions.count) completed \(completedSessions.count == 1 ? "workout" : "workouts")")
                                .formCaption()
                        }
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(Color.formAccent)
                    }
                }
                NavigationLink {
                    ExerciseLibraryView()
                } label: {
                    Label("Exercise library", systemImage: "books.vertical")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .formPageBackground()
        .navigationTitle("Train")
        .toolbar {
            if !routines.isEmpty { EditButton() }
        }
        .navigationDestination(item: $newRoutine) { routine in
            RoutineEditorView(routine: routine)
        }
        .confirmationDialog("Delete this routine?",
                            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingDeletion) { routine in
            Button("Delete \(routine.name)", role: .destructive) {
                perform { try routineRepository.delete(routine) }
            }
        } message: { _ in
            Text("Workouts you've already logged from it stay in your history.")
        }
    }

    private func createRoutine() {
        perform {
            newRoutine = try routineRepository.create(named: "New routine", sortIndex: routines.count)
        }
    }

    private func start(_ action: () throws -> WorkoutSession) {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        perform {
            _ = try action()
            router.isActiveWorkoutPresented = true
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            errorMessage = nil
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
            HapticsManager.shared.error()
        }
    }
}

/// Shown at the top of Train while a workout is in progress.
struct ActiveWorkoutBanner: View {
    let session: WorkoutSession
    let resume: () -> Void

    var body: some View {
        Button(action: resume) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: Spacing.s) {
                    Image(systemName: session.clock.isPaused ? "pause.circle.fill" : "record.circle")
                        .font(.title2)
                        .foregroundStyle(Color.formOnAccent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.clock.isPaused ? "Workout paused" : "Workout in progress")
                            .font(.footnote)
                            .foregroundStyle(Color.formOnAccent.opacity(0.85))
                        Text(session.name)
                            .font(.headline)
                            .foregroundStyle(Color.formOnAccent)
                    }
                    Spacer()
                    Text(DurationText.clock(session.clock.elapsed(at: context.date)))
                        .formNumeric(.title3)
                        .foregroundStyle(Color.formOnAccent)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.formOnAccent)
                        .accessibilityHidden(true)
                }
                .padding(Spacing.m)
                .background(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).fill(Color.formAccent))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Resume \(session.name)")
    }
}

private struct RoutineRow: View {
    let routine: WorkoutRoutine

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(routine.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.formTextPrimary)
            Text(summary)
                .formCaption()
                .lineLimit(2)
        }
        .padding(.vertical, Spacing.xxs)
    }

    private var summary: String {
        let names = routine.orderedExercises.compactMap { $0.exercise?.name }
        if names.isEmpty { return "No exercises" }
        return "\(names.count) exercises · " + names.joined(separator: ", ")
    }
}

struct RoutineDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Query(filter: #Predicate<WorkoutSession> { $0.statusRaw == "active" }) private var activeSessions: [WorkoutSession]
    let routine: WorkoutRoutine
    @State private var errorMessage: String?

    var body: some View {
        List {
            if !routine.notes.isEmpty {
                Section {
                    Text(routine.notes)
                        .font(.subheadline)
                        .foregroundStyle(Color.formTextSecondary)
                }
            }
            Section("Exercises") {
                if routine.exercises.isEmpty {
                    Text("No exercises yet. Use Edit to add some.")
                        .foregroundStyle(Color.formTextSecondary)
                }
                ForEach(routine.orderedExercises) { entry in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.exercise?.name ?? "Deleted exercise")
                                .foregroundStyle(Color.formTextPrimary)
                            if let exercise = entry.exercise {
                                Text("\(exercise.muscleGroup.displayName) · \(exercise.equipment.displayName)")
                                    .formCaption()
                            }
                        }
                        Spacer()
                        Text(targetText(entry))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(Color.formTextSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(Color.formDestructive) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .formPageBackground()
        .navigationTitle(routine.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Edit") { RoutineEditorView(routine: routine) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Spacing.xxs) {
                Button(activeSessions.isEmpty ? "Start workout" : "Workout already in progress", action: start)
                    .buttonStyle(FormPrimaryButtonStyle())
                    .disabled(!activeSessions.isEmpty || routine.exercises.isEmpty)
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.xs)
            .background(Color.formBackground.opacity(0.96))
        }
    }

    private func start() {
        do {
            try WorkoutRepository(context: modelContext).startWorkout(from: routine)
            router.isActiveWorkoutPresented = true
        } catch {
            errorMessage = error.localizedDescription
            HapticsManager.shared.error()
        }
    }

    private func targetText(_ entry: RoutineExercise) -> String {
        if let reps = entry.repTargetText, entry.exercise?.trackingType != .duration, entry.exercise?.trackingType != .distanceAndDuration {
            return "\(entry.targetSets) × \(reps)"
        }
        return "\(entry.targetSets) sets"
    }
}
