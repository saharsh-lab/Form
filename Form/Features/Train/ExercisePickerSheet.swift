import SwiftUI
import SwiftData
import FormCore

/// Search and pick an exercise from the local catalogue, or create one.
struct ExercisePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Exercise> { !$0.isArchived }, sort: \Exercise.name) private var exercises: [Exercise]
    let onPick: (Exercise) -> Void

    @State private var searchText = ""
    @State private var muscleFilter: MuscleGroup?
    @State private var creating = false

    private var filtered: [Exercise] {
        let byFilter = ExerciseFilter.apply(exercises, search: "", muscle: muscleFilter, equipment: nil)
        return TextSearch.rank(byFilter, query: searchText, name: { $0.name })
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.xs) {
                            chip(nil, title: "All")
                            ForEach(MuscleGroup.allCases) { group in chip(group, title: group.displayName) }
                        }
                        .padding(.horizontal, Spacing.m)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                Section {
                    Button {
                        creating = true
                    } label: {
                        Label(searchText.isEmpty ? "Create exercise" : "Create \u{201C}\(searchText)\u{201D}", systemImage: "plus.circle.fill")
                    }
                    ForEach(filtered) { exercise in
                        Button {
                            onPick(exercise)
                            dismiss()
                        } label: {
                            ExerciseRow(exercise: exercise)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .formPageBackground()
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
            .autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .navigationDestination(isPresented: $creating) {
                ExerciseEditorView(exercise: nil, prefillName: searchText.trimmingCharacters(in: .whitespaces)) { exercise in
                    onPick(exercise)
                    dismiss()
                }
            }
        }
    }

    private func chip(_ group: MuscleGroup?, title: String) -> some View {
        Button {
            muscleFilter = group
            HapticsManager.shared.selectionChanged()
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(muscleFilter == group ? Color.formAccent : Color.formTextPrimary)
                .padding(.horizontal, Spacing.s)
                .frame(minHeight: 36)
                .background(Capsule().fill(muscleFilter == group ? Color.formAccentSoft : Color.formSurface))
                .overlay(Capsule().strokeBorder(Color.formSeparator, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(muscleFilter == group ? .isSelected : [])
    }
}

/// Create or edit a catalogue exercise.
struct ExerciseEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let exercise: Exercise?
    var onSaved: ((Exercise) -> Void)?

    @State private var name: String
    @State private var muscle: MuscleGroup
    @State private var equipment: Equipment
    @State private var tracking: ExerciseTrackingType
    @State private var notes: String
    @State private var errorMessage: String?
    @State private var confirmArchive = false

    init(exercise: Exercise?, prefillName: String = "", onSaved: ((Exercise) -> Void)? = nil) {
        self.exercise = exercise
        self.onSaved = onSaved
        _name = State(initialValue: exercise?.name ?? prefillName)
        _muscle = State(initialValue: exercise?.muscleGroup ?? .chest)
        _equipment = State(initialValue: exercise?.equipment ?? .barbell)
        _tracking = State(initialValue: exercise?.trackingType ?? .weightAndReps)
        _notes = State(initialValue: exercise?.notes ?? "")
    }

    /// Tracking type can't change once the exercise has history, so records stay comparable.
    private var hasHistory: Bool { !(exercise?.workoutEntries.isEmpty ?? true) }

    var body: some View {
        List {
            Section {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                Picker("Muscle group", selection: $muscle) {
                    ForEach(MuscleGroup.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Equipment", selection: $equipment) {
                    ForEach(Equipment.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Records", selection: $tracking) {
                    ForEach(ExerciseTrackingType.allCases) { Text($0.displayName).tag($0) }
                }
                .disabled(hasHistory)
            } footer: {
                if hasHistory {
                    Text("The tracking type can't change after the exercise has been logged, so its history and records stay comparable.")
                }
            }
            Section("Notes") {
                TextField("Optional", text: $notes, axis: .vertical).lineLimit(1...5)
            }
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(Color.formDestructive)
                }
            }
            if exercise != nil {
                Section {
                    Button(hasHistory ? "Archive exercise" : "Delete exercise", role: .destructive) { confirmArchive = true }
                } footer: {
                    Text(hasHistory ? "Archived exercises are hidden from the library but stay in your workout history." : "")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .formPageBackground()
        .navigationTitle(exercise == nil ? "New exercise" : "Edit exercise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
        }
        .confirmationDialog(hasHistory ? "Archive this exercise?" : "Delete this exercise?", isPresented: $confirmArchive, titleVisibility: .visible) {
            Button(hasHistory ? "Archive" : "Delete", role: .destructive, action: archiveOrDelete)
        }
    }

    private func save() {
        let validName: String
        switch InputValidator.name(name, maximumLength: 60) {
        case .success(let value): validName = value
        case .failure(let error):
            errorMessage = error.localizedDescription
            HapticsManager.shared.error()
            return
        }
        let target: Exercise
        if let exercise {
            target = exercise
            target.name = validName
            target.muscleGroup = muscle
            target.equipment = equipment
            if !hasHistory { target.trackingType = tracking }
            target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            target = Exercise(name: validName, muscleGroup: muscle, equipment: equipment, trackingType: tracking,
                              isCustom: true, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines))
            modelContext.insert(target)
        }
        do {
            try modelContext.save()
            HapticsManager.shared.saveSucceeded()
            if let onSaved { onSaved(target) } else { dismiss() }
        } catch {
            modelContext.rollback()
            errorMessage = "Couldn't save: \(error.localizedDescription)"
            HapticsManager.shared.error()
        }
    }

    private func archiveOrDelete() {
        guard let exercise else { return }
        if hasHistory {
            exercise.isArchived = true
        } else {
            modelContext.delete(exercise)
        }
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = "Couldn't update: \(error.localizedDescription)"
        }
    }
}
