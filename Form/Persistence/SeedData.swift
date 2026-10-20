import Foundation
import SwiftData
import FormCore

/// Inserts the starter exercise catalogue and routines once, on first launch.
/// Everything seeded is ordinary editable user data; nothing is fetched from a server.
@MainActor
enum Seeder {

    struct ExerciseSeed {
        let name: String
        let muscle: MuscleGroup
        let equipment: Equipment
        var tracking: ExerciseTrackingType = .weightAndReps
    }

    static let exercises: [ExerciseSeed] = [
        // Chest
        ExerciseSeed(name: "Barbell Bench Press", muscle: .chest, equipment: .barbell),
        ExerciseSeed(name: "Incline Barbell Bench Press", muscle: .chest, equipment: .barbell),
        ExerciseSeed(name: "Dumbbell Bench Press", muscle: .chest, equipment: .dumbbell),
        ExerciseSeed(name: "Incline Dumbbell Press", muscle: .chest, equipment: .dumbbell),
        ExerciseSeed(name: "Cable Fly", muscle: .chest, equipment: .cable),
        ExerciseSeed(name: "Machine Chest Press", muscle: .chest, equipment: .machine),
        ExerciseSeed(name: "Push-up", muscle: .chest, equipment: .bodyweight, tracking: .repsOnly),
        ExerciseSeed(name: "Dip", muscle: .chest, equipment: .bodyweight, tracking: .repsOnly),
        // Back
        ExerciseSeed(name: "Deadlift", muscle: .back, equipment: .barbell),
        ExerciseSeed(name: "Barbell Row", muscle: .back, equipment: .barbell),
        ExerciseSeed(name: "Pull-up", muscle: .back, equipment: .bodyweight, tracking: .repsOnly),
        ExerciseSeed(name: "Chin-up", muscle: .back, equipment: .bodyweight, tracking: .repsOnly),
        ExerciseSeed(name: "Lat Pulldown", muscle: .back, equipment: .cable),
        ExerciseSeed(name: "Seated Cable Row", muscle: .back, equipment: .cable),
        ExerciseSeed(name: "One-Arm Dumbbell Row", muscle: .back, equipment: .dumbbell),
        ExerciseSeed(name: "Chest-Supported Row", muscle: .back, equipment: .machine),
        // Shoulders
        ExerciseSeed(name: "Overhead Press", muscle: .shoulders, equipment: .barbell),
        ExerciseSeed(name: "Seated Dumbbell Shoulder Press", muscle: .shoulders, equipment: .dumbbell),
        ExerciseSeed(name: "Lateral Raise", muscle: .shoulders, equipment: .dumbbell),
        ExerciseSeed(name: "Cable Lateral Raise", muscle: .shoulders, equipment: .cable),
        ExerciseSeed(name: "Face Pull", muscle: .shoulders, equipment: .cable),
        ExerciseSeed(name: "Reverse Pec Deck", muscle: .shoulders, equipment: .machine),
        // Arms
        ExerciseSeed(name: "Barbell Curl", muscle: .biceps, equipment: .barbell),
        ExerciseSeed(name: "Dumbbell Curl", muscle: .biceps, equipment: .dumbbell),
        ExerciseSeed(name: "Hammer Curl", muscle: .biceps, equipment: .dumbbell),
        ExerciseSeed(name: "Cable Curl", muscle: .biceps, equipment: .cable),
        ExerciseSeed(name: "Triceps Pushdown", muscle: .triceps, equipment: .cable),
        ExerciseSeed(name: "Overhead Triceps Extension", muscle: .triceps, equipment: .cable),
        ExerciseSeed(name: "Skull Crusher", muscle: .triceps, equipment: .barbell),
        ExerciseSeed(name: "Close-Grip Bench Press", muscle: .triceps, equipment: .barbell),
        ExerciseSeed(name: "Wrist Curl", muscle: .forearms, equipment: .dumbbell),
        // Legs
        ExerciseSeed(name: "Back Squat", muscle: .quadriceps, equipment: .barbell),
        ExerciseSeed(name: "Front Squat", muscle: .quadriceps, equipment: .barbell),
        ExerciseSeed(name: "Leg Press", muscle: .quadriceps, equipment: .machine),
        ExerciseSeed(name: "Bulgarian Split Squat", muscle: .quadriceps, equipment: .dumbbell),
        ExerciseSeed(name: "Walking Lunge", muscle: .quadriceps, equipment: .dumbbell),
        ExerciseSeed(name: "Leg Extension", muscle: .quadriceps, equipment: .machine),
        ExerciseSeed(name: "Romanian Deadlift", muscle: .hamstrings, equipment: .barbell),
        ExerciseSeed(name: "Lying Leg Curl", muscle: .hamstrings, equipment: .machine),
        ExerciseSeed(name: "Seated Leg Curl", muscle: .hamstrings, equipment: .machine),
        ExerciseSeed(name: "Hip Thrust", muscle: .glutes, equipment: .barbell),
        ExerciseSeed(name: "Cable Glute Kickback", muscle: .glutes, equipment: .cable),
        ExerciseSeed(name: "Standing Calf Raise", muscle: .calves, equipment: .machine),
        ExerciseSeed(name: "Seated Calf Raise", muscle: .calves, equipment: .machine),
        // Core
        ExerciseSeed(name: "Plank", muscle: .core, equipment: .bodyweight, tracking: .duration),
        ExerciseSeed(name: "Hanging Leg Raise", muscle: .core, equipment: .bodyweight, tracking: .repsOnly),
        ExerciseSeed(name: "Cable Crunch", muscle: .core, equipment: .cable),
        ExerciseSeed(name: "Ab Wheel Rollout", muscle: .core, equipment: .other, tracking: .repsOnly),
        // Full body and conditioning
        ExerciseSeed(name: "Kettlebell Swing", muscle: .fullBody, equipment: .kettlebell),
        ExerciseSeed(name: "Farmer's Carry", muscle: .fullBody, equipment: .dumbbell, tracking: .distanceAndDuration),
        ExerciseSeed(name: "Rowing Machine", muscle: .cardio, equipment: .cardioMachine, tracking: .distanceAndDuration),
        ExerciseSeed(name: "Treadmill Run", muscle: .cardio, equipment: .cardioMachine, tracking: .distanceAndDuration),
        ExerciseSeed(name: "Stationary Bike", muscle: .cardio, equipment: .cardioMachine, tracking: .distanceAndDuration),
        ExerciseSeed(name: "Jump Rope", muscle: .cardio, equipment: .other, tracking: .duration)
    ]

    struct RoutineSeed {
        struct Item {
            let exercise: String
            let sets: Int
            let reps: ClosedRange<Int>?
        }
        let name: String
        let notes: String
        let items: [Item]
    }

    static let routines: [RoutineSeed] = [
        RoutineSeed(name: "Full Body A", notes: "A balanced starter session. Rest 2–3 minutes on the first two lifts.", items: [
            .init(exercise: "Back Squat", sets: 3, reps: 5...8),
            .init(exercise: "Barbell Bench Press", sets: 3, reps: 5...8),
            .init(exercise: "Barbell Row", sets: 3, reps: 8...10),
            .init(exercise: "Lateral Raise", sets: 2, reps: 12...15),
            .init(exercise: "Plank", sets: 2, reps: nil)
        ]),
        RoutineSeed(name: "Full Body B", notes: "Alternate with Full Body A.", items: [
            .init(exercise: "Romanian Deadlift", sets: 3, reps: 6...10),
            .init(exercise: "Overhead Press", sets: 3, reps: 6...8),
            .init(exercise: "Lat Pulldown", sets: 3, reps: 8...12),
            .init(exercise: "Walking Lunge", sets: 2, reps: 10...12),
            .init(exercise: "Hanging Leg Raise", sets: 2, reps: 10...15)
        ]),
        RoutineSeed(name: "Upper Body", notes: "", items: [
            .init(exercise: "Incline Dumbbell Press", sets: 3, reps: 8...12),
            .init(exercise: "Seated Cable Row", sets: 3, reps: 8...12),
            .init(exercise: "Seated Dumbbell Shoulder Press", sets: 3, reps: 8...12),
            .init(exercise: "Pull-up", sets: 3, reps: 6...10),
            .init(exercise: "Dumbbell Curl", sets: 2, reps: 10...12),
            .init(exercise: "Triceps Pushdown", sets: 2, reps: 10...12)
        ]),
        RoutineSeed(name: "Lower Body", notes: "", items: [
            .init(exercise: "Back Squat", sets: 4, reps: 5...8),
            .init(exercise: "Romanian Deadlift", sets: 3, reps: 8...10),
            .init(exercise: "Leg Press", sets: 3, reps: 10...12),
            .init(exercise: "Lying Leg Curl", sets: 3, reps: 10...12),
            .init(exercise: "Standing Calf Raise", sets: 3, reps: 10...15)
        ])
    ]

    /// Seeds the catalogue and routines if they have never been seeded.
    /// Safe to call on every launch.
    static func seedIfNeeded(in context: ModelContext) {
        let preferences = PreferencesStore.current(in: context)
        guard !preferences.hasSeededCatalogue else { return }

        let existingCount = (try? context.fetchCount(FetchDescriptor<Exercise>())) ?? 0
        if existingCount == 0 {
            insertCatalogue(in: context)
        }
        preferences.hasSeededCatalogue = true
        try? context.save()
    }

    private static func insertCatalogue(in context: ModelContext) {
        var byName: [String: Exercise] = [:]
        for seed in exercises {
            let exercise = Exercise(name: seed.name, muscleGroup: seed.muscle, equipment: seed.equipment, trackingType: seed.tracking)
            context.insert(exercise)
            byName[seed.name] = exercise
        }

        for (routineIndex, seed) in routines.enumerated() {
            let routine = WorkoutRoutine(name: seed.name, notes: seed.notes, sortIndex: routineIndex)
            context.insert(routine)
            for (itemIndex, item) in seed.items.enumerated() {
                guard let exercise = byName[item.exercise] else {
                    assertionFailure("Seed routine references unknown exercise \(item.exercise)")
                    continue
                }
                let entry = RoutineExercise(sortIndex: itemIndex,
                                            targetSets: item.sets,
                                            targetRepsLower: item.reps?.lowerBound,
                                            targetRepsUpper: item.reps?.upperBound)
                context.insert(entry)
                entry.exercise = exercise
                entry.routine = routine
            }
        }
    }
}
