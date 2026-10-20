import SwiftUI
import SwiftData
import FormCore

/// Routine operations.
@MainActor
struct RoutineRepository {
    let context: ModelContext

    @discardableResult
    func create(named name: String, sortIndex: Int) throws -> WorkoutRoutine {
        let routine = WorkoutRoutine(name: name, sortIndex: sortIndex)
        context.insert(routine)
        try context.save()
        return routine
    }

    @discardableResult
    func duplicate(_ routine: WorkoutRoutine, sortIndex: Int) throws -> WorkoutRoutine {
        let copy = WorkoutRoutine(name: NutritionRepository.copyName(for: routine.name), notes: routine.notes, sortIndex: sortIndex)
        context.insert(copy)
        for entry in routine.orderedExercises {
            let newEntry = RoutineExercise(sortIndex: entry.sortIndex, targetSets: entry.targetSets,
                                           targetRepsLower: entry.targetRepsLower, targetRepsUpper: entry.targetRepsUpper,
                                           restSeconds: entry.restSeconds, notes: entry.notes)
            context.insert(newEntry)
            newEntry.routine = copy
            newEntry.exercise = entry.exercise
        }
        try context.save()
        return copy
    }

    func delete(_ routine: WorkoutRoutine) throws {
        context.delete(routine)
        try context.save()
    }

    func add(_ exercise: Exercise, to routine: WorkoutRoutine) throws {
        let entry = RoutineExercise(sortIndex: (routine.exercises.map(\.sortIndex).max() ?? -1) + 1,
                                    targetSets: 3, targetRepsLower: 8, targetRepsUpper: 12)
        context.insert(entry)
        entry.routine = routine
        entry.exercise = exercise
        routine.updatedAt = .now
        try context.save()
    }

    func remove(_ entry: RoutineExercise) throws {
        let routine = entry.routine
        context.delete(entry)
        if let routine {
            for (index, remaining) in routine.orderedExercises.filter({ $0.id != entry.id }).enumerated() {
                remaining.sortIndex = index
            }
            routine.updatedAt = .now
        }
        try context.save()
    }

    /// Applies a List `onMove` to a routine's exercises.
    func moveExercises(in routine: WorkoutRoutine, from source: IndexSet, to destination: Int) throws {
        var ordered = routine.orderedExercises
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, entry) in ordered.enumerated() { entry.sortIndex = index }
        routine.updatedAt = .now
        try context.save()
    }

    /// Applies a List `onMove` to the routine list.
    func moveRoutines(_ routines: [WorkoutRoutine], from source: IndexSet, to destination: Int) throws {
        var ordered = routines
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, routine) in ordered.enumerated() { routine.sortIndex = index }
        try context.save()
    }
}

/// Edit a routine's name, notes, exercises, order and targets.
struct RoutineEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var routine: WorkoutRoutine

    @State private var showingPicker = false
    @State private var errorMessage: String?
    @State private var nameError: String?

    private var repository: RoutineRepository { RoutineRepository(context: modelContext) }

    var body: some View {
        List {
            Section {
                TextField("Routine name", text: $routine.name)
                    .textInputAutocapitalization(.words)
                if let nameError {
                    Text(nameError).font(.footnote).foregroundStyle(Color.formDestructive)
                }
                TextField("Notes (optional)", text: $routine.notes, axis: .vertical)
                    .lineLimit(1...4)
            }

            Section {
                ForEach(routine.orderedExercises) { entry in
                    RoutineEntryEditor(entry: entry, onChange: save)
                }
                .onDelete { offsets in
                    let ordered = routine.orderedExercises
                    perform { for index in offsets { try repository.remove(ordered[index]) } }
                }
                .onMove { source, destination in
                    perform { try repository.moveExercises(in: routine, from: source, to: destination) }
                }
                Button {
                    showingPicker = true
                } label: {
                    Label("Add exercise", systemImage: "plus")
                }
            } header: {
                Text("Exercises")
            } footer: {
                Text("Use Edit to reorder or delete exercises.")
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(Color.formDestructive) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .formPageBackground()
        .navigationTitle("Edit routine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .sheet(isPresented: $showingPicker) {
            ExercisePickerSheet { exercise in
                perform { try repository.add(exercise, to: routine) }
            }
        }
        .onDisappear(perform: save)
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            errorMessage = nil
        } catch {
            modelContext.rollback()
            errorMessage = "Couldn't save: \(error.localizedDescription)"
            HapticsManager.shared.error()
        }
    }

    private func save() {
        switch InputValidator.name(routine.name, maximumLength: 60) {
        case .success(let valid):
            nameError = nil
            if routine.name != valid { routine.name = valid }
        case .failure(let error):
            nameError = error.localizedDescription
            if routine.name.trimmingCharacters(in: .whitespaces).isEmpty { routine.name = "Untitled routine" }
        }
        routine.updatedAt = .now
        perform { try modelContext.save() }
    }
}

/// Target sets and rep range for one routine exercise.
private struct RoutineEntryEditor: View {
    @Bindable var entry: RoutineExercise
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(entry.exercise?.name ?? "Deleted exercise")
                .font(.body.weight(.medium))
                .foregroundStyle(Color.formTextPrimary)
            Stepper(value: $entry.targetSets, in: 1...10) {
                Text("\(entry.targetSets) \(entry.targetSets == 1 ? "set" : "sets")").monospacedDigit()
            }
            .onChange(of: entry.targetSets) { _, _ in onChange() }
            if entry.exercise?.trackingType != .duration && entry.exercise?.trackingType != .distanceAndDuration {
                HStack {
                    Text("Reps").formCaption()
                    Spacer()
                    Stepper(value: lowerBinding, in: 1...50) {
                        Text("\(entry.targetRepsLower ?? 8)–\(entry.targetRepsUpper ?? entry.targetRepsLower ?? 12)")
                            .monospacedDigit()
                    }
                    .accessibilityLabel("Minimum reps")
                }
                Stepper(value: upperBinding, in: 1...50) {
                    Text("Up to \(entry.targetRepsUpper ?? entry.targetRepsLower ?? 12)").formCaption()
                }
                .accessibilityLabel("Maximum reps")
            }
        }
        .padding(.vertical, Spacing.xxs)
    }

    private var lowerBinding: Binding<Int> {
        Binding(get: { entry.targetRepsLower ?? 8 }, set: { value in
            entry.targetRepsLower = value
            if let upper = entry.targetRepsUpper, upper < value { entry.targetRepsUpper = value }
            onChange()
        })
    }

    private var upperBinding: Binding<Int> {
        Binding(get: { entry.targetRepsUpper ?? entry.targetRepsLower ?? 12 }, set: { value in
            entry.targetRepsUpper = value
            if let lower = entry.targetRepsLower, lower > value { entry.targetRepsLower = value }
            onChange()
        })
    }
}
