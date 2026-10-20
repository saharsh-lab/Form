import SwiftUI
import SwiftData
import FormCore

/// Train tab root: routines and the exercise library.
///
/// Phase 1 scope: browse routines and the catalogue. Starting and logging
/// workouts, and editing routines, arrive in Phase 3.
struct TrainView: View {
    @Query(sort: \WorkoutRoutine.sortIndex) private var routines: [WorkoutRoutine]
    @Query private var exercises: [Exercise]

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ExerciseLibraryView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Exercise library")
                                .foregroundStyle(Color.formTextPrimary)
                            Text("\(exercises.filter { !$0.isArchived }.count) exercises")
                                .formCaption()
                        }
                    } icon: {
                        Image(systemName: "books.vertical")
                            .foregroundStyle(Color.formAccent)
                    }
                }
            }

            Section {
                if routines.isEmpty {
                    EmptyStateView(symbol: "list.bullet.rectangle",
                                   title: "No routines yet",
                                   message: "Routines are reusable workout plans. Creating your own arrives with workout logging.")
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(routines) { routine in
                        NavigationLink {
                            RoutineDetailView(routine: routine)
                        } label: {
                            RoutineRow(routine: routine)
                        }
                    }
                }
            } header: {
                Text("Routines")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .formPageBackground()
        .navigationTitle("Train")
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
    let routine: WorkoutRoutine

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
            Section {
                InlineNotice(symbol: "hammer", text: "Starting this routine and logging sets arrive in the next build (Phase 3).")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .formPageBackground()
        .navigationTitle(routine.name)
    }

    private func targetText(_ entry: RoutineExercise) -> String {
        if let reps = entry.repTargetText {
            return "\(entry.targetSets) × \(reps)"
        }
        return "\(entry.targetSets) sets"
    }
}
