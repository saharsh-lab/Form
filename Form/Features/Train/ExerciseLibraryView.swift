import SwiftUI
import SwiftData
import FormCore

/// Searchable, filterable list of the local exercise catalogue.
struct ExerciseLibraryView: View {
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var searchText = ""
    @State private var muscleFilter: MuscleGroup?
    @State private var equipmentFilter: Equipment?

    private var filtered: [Exercise] {
        ExerciseFilter.apply(exercises.filter { !$0.isArchived },
                             search: searchText,
                             muscle: muscleFilter,
                             equipment: equipmentFilter)
    }

    var body: some View {
        List {
            Section {
                filterBar
                    .listRowInsets(EdgeInsets(top: Spacing.xs, leading: 0, bottom: Spacing.xs, trailing: 0))
                    .listRowBackground(Color.clear)
            }
            Section {
                if filtered.isEmpty {
                    EmptyStateView(symbol: "magnifyingglass",
                                   title: "No matching exercises",
                                   message: "Try a different name or clear the filters.",
                                   actionTitle: hasFilters ? "Clear filters" : nil) {
                        clearFilters()
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(filtered) { exercise in
                        ExerciseRow(exercise: exercise)
                    }
                }
            } footer: {
                if !filtered.isEmpty {
                    Text("\(filtered.count) of \(exercises.filter { !$0.isArchived }.count) exercises")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .formPageBackground()
        .navigationTitle("Exercises")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
        .autocorrectionDisabled()
    }

    private var hasFilters: Bool {
        muscleFilter != nil || equipmentFilter != nil || !searchText.isEmpty
    }

    private func clearFilters() {
        muscleFilter = nil
        equipmentFilter = nil
        searchText = ""
    }

    private var filterBar: some View {
        HStack(spacing: Spacing.xs) {
            Menu {
                Picker("Muscle group", selection: $muscleFilter) {
                    Text("All muscle groups").tag(MuscleGroup?.none)
                    ForEach(MuscleGroup.allCases) { group in
                        Text(group.displayName).tag(MuscleGroup?.some(group))
                    }
                }
            } label: {
                FilterChip(title: muscleFilter?.displayName ?? "Muscle", isActive: muscleFilter != nil)
            }
            .accessibilityLabel("Filter by muscle group")
            .accessibilityValue(muscleFilter?.displayName ?? "All")

            Menu {
                Picker("Equipment", selection: $equipmentFilter) {
                    Text("All equipment").tag(Equipment?.none)
                    ForEach(Equipment.allCases) { equipment in
                        Text(equipment.displayName).tag(Equipment?.some(equipment))
                    }
                }
            } label: {
                FilterChip(title: equipmentFilter?.displayName ?? "Equipment", isActive: equipmentFilter != nil)
            }
            .accessibilityLabel("Filter by equipment")
            .accessibilityValue(equipmentFilter?.displayName ?? "All")

            Spacer()

            if muscleFilter != nil || equipmentFilter != nil {
                Button("Clear") {
                    muscleFilter = nil
                    equipmentFilter = nil
                }
                .font(.subheadline)
            }
        }
        .onChange(of: muscleFilter) { _, _ in HapticsManager.shared.selectionChanged() }
        .onChange(of: equipmentFilter) { _, _ in HapticsManager.shared.selectionChanged() }
    }
}

/// Pure filtering logic, kept out of the view so it can be tested.
enum ExerciseFilter {
    /// Case- and diacritic-insensitive partial name match, combined with optional filters.
    static func apply(_ exercises: [Exercise], search: String, muscle: MuscleGroup?, equipment: Equipment?) -> [Exercise] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return exercises.filter { exercise in
            if let muscle, exercise.muscleGroup != muscle { return false }
            if let equipment, exercise.equipment != equipment { return false }
            if query.isEmpty { return true }
            return exercise.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

struct FilterChip: View {
    let title: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Text(title)
            Image(systemName: "chevron.down")
                .imageScale(.small)
                .accessibilityHidden(true)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(isActive ? Color.formAccent : Color.formTextPrimary)
        .padding(.horizontal, Spacing.s)
        .frame(minHeight: 36)
        .background(
            Capsule().fill(isActive ? Color.formAccentSoft : Color.formSurface)
        )
        .overlay(
            Capsule().strokeBorder(isActive ? Color.formAccent.opacity(0.5) : Color.formSeparator, lineWidth: 0.5)
        )
        .contentShape(Capsule())
    }
}

struct ExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(exercise.name)
                .foregroundStyle(Color.formTextPrimary)
            HStack(spacing: Spacing.xxs) {
                Text(exercise.muscleGroup.displayName)
                Text("·")
                Text(exercise.equipment.displayName)
                if exercise.trackingType != .weightAndReps {
                    Text("·")
                    Text(exercise.trackingType.displayName)
                }
            }
            .formCaption()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
