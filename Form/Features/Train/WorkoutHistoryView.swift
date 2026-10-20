import SwiftUI
import SwiftData
import FormCore

/// Completed workouts, newest first, grouped by month.
struct WorkoutHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<WorkoutSession> { $0.statusRaw == "completed" },
           sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]
    @Query(sort: \UserPreferences.createdAt) private var preferences: [UserPreferences]
    @State private var pendingDeletion: WorkoutSession?
    @State private var errorMessage: String?

    private var weightUnit: WeightUnit { preferences.first?.weightUnit ?? .kilograms }

    private struct MonthGroup: Identifiable {
        let month: Date
        let sessions: [WorkoutSession]
        var id: Date { month }
    }

    private var groups: [MonthGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sessions) { session in
            calendar.dateInterval(of: .month, for: session.startedAt)?.start ?? session.startedAt
        }
        return grouped.keys.sorted(by: >).map { MonthGroup(month: $0, sessions: grouped[$0] ?? []) }
    }

    var body: some View {
        List {
            if sessions.isEmpty {
                EmptyStateView(symbol: "clock.arrow.circlepath",
                               title: "No workouts yet",
                               message: "Finished workouts appear here. You can review and correct them at any time.")
                    .listRowBackground(Color.clear)
            }
            ForEach(groups) { group in
                Section(group.month.formatted(.dateTime.month(.wide).year())) {
                    ForEach(group.sessions) { session in
                        NavigationLink {
                            WorkoutSessionDetailView(session: session)
                        } label: {
                            HistoryRow(session: session, weightUnit: weightUnit)
                        }
                        .swipeActions {
                            Button(role: .destructive) { pendingDeletion = session } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(Color.formDestructive) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .formPageBackground()
        .navigationTitle("History")
        .confirmationDialog("Delete this workout?",
                            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingDeletion) { session in
            Button("Delete workout", role: .destructive) {
                do {
                    try WorkoutRepository(context: modelContext).delete(session)
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                    HapticsManager.shared.error()
                }
            }
        } message: { session in
            Text("\(session.name) on \(session.startedAt.formatted(date: .abbreviated, time: .omitted)) will be removed from your history and records. This can't be undone.")
        }
    }
}

private struct HistoryRow: View {
    let session: WorkoutSession
    let weightUnit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.name).foregroundStyle(Color.formTextPrimary)
            HStack(spacing: Spacing.xs) {
                Text(session.startedAt.formatted(.dateTime.weekday(.abbreviated).day().hour().minute()))
                Text("·")
                Text(DurationText.summary(session.clock.elapsed(at: session.endedAt ?? session.startedAt)))
                Text("·")
                Text("\(session.completedSetCount) sets")
                if session.totalVolumeKilograms > 0 {
                    Text("·")
                    Text(NumberText.weight(kilograms: session.totalVolumeKilograms, unit: weightUnit))
                }
            }
            .formCaption()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Review and correct a completed workout: name, sets, values and completion.
struct WorkoutSessionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \UserPreferences.createdAt) private var preferences: [UserPreferences]
    @Bindable var session: WorkoutSession

    @State private var errorMessage: String?
    @State private var showingPicker = false
    @State private var confirmDelete = false

    private var weightUnit: WeightUnit { preferences.first?.weightUnit ?? .kilograms }
    private var repository: WorkoutRepository { WorkoutRepository(context: modelContext) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.m) {
                FormCard {
                    TextField("Workout name", text: $session.name)
                        .font(.title3.weight(.semibold))
                        .onSubmit(saveName)
                    Text(session.startedAt.formatted(date: .complete, time: .shortened)).formCaption()
                    HStack {
                        StatTile(title: "Duration", value: DurationText.summary(session.clock.elapsed(at: session.endedAt ?? session.startedAt)))
                        StatTile(title: "Sets", value: "\(session.completedSetCount)")
                        StatTile(title: "Volume", value: session.totalVolumeKilograms > 0 ? NumberText.weight(kilograms: session.totalVolumeKilograms, unit: weightUnit) : "—")
                    }
                }
                if let errorMessage {
                    InlineNotice(symbol: "exclamationmark.triangle", text: errorMessage, tint: .formDestructive)
                }
                ForEach(session.orderedExercises) { workoutExercise in
                    ExerciseLogCard(workoutExercise: workoutExercise,
                                    previous: [],
                                    weightUnit: weightUnit,
                                    isFirst: workoutExercise.sortIndex == session.orderedExercises.first?.sortIndex,
                                    isLast: workoutExercise.sortIndex == session.orderedExercises.last?.sortIndex,
                                    perform: perform,
                                    onSetCompleted: { set in perform { try repository.toggleCompletion(of: set, restDuration: nil) } },
                                    showsPrevious: false)
                }
                Button {
                    showingPicker = true
                } label: {
                    Label("Add exercise", systemImage: "plus")
                }
                .buttonStyle(FormSecondaryButtonStyle())
                Button("Delete workout", role: .destructive) { confirmDelete = true }
                    .frame(maxWidth: .infinity, minHeight: Metrics.minimumTouchTarget)
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .formPageBackground()
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPicker) {
            ExercisePickerSheet { exercise in perform { try repository.addExercise(exercise, to: session) } }
        }
        .confirmationDialog("Delete this workout?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete workout", role: .destructive) {
                do {
                    try repository.delete(session)
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } message: {
            Text("It will be removed from your history and records. This can't be undone.")
        }
        .onDisappear(perform: saveName)
    }

    private func saveName() {
        guard !session.isDeleted else { return }
        if case .failure = InputValidator.name(session.name, maximumLength: 60) {
            session.name = WorkoutRepository.defaultName(for: session.startedAt)
        }
        perform { try modelContext.save() }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            HapticsManager.shared.error()
        }
    }
}
