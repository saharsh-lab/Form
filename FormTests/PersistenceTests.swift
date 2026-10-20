import XCTest
import SwiftData
import FormCore
@testable import FormApp

/// SwiftData behaviour that the rest of the app relies on.
@MainActor
final class PersistenceTests: XCTestCase {

    private func makeInMemoryContext() throws -> ModelContext {
        let container = try PersistenceController.makeContainer(location: .inMemory)
        return ModelContext(container)
    }

    private func makeFood(in context: ModelContext) -> Food {
        let food = Food(name: "Rolled oats",
                        servingDescription: "40 g",
                        serving: ServingDefinition(basis: .per100Grams, servingQuantity: 40, servingUnit: .gram),
                        nutrition: NutritionValues(calories: 380, protein: 13, carbohydrates: 60, fat: 7))
        context.insert(food)
        return food
    }

    // MARK: Historical nutrition snapshots

    func testEditingAFoodDoesNotChangeLoggedEntries() throws {
        let context = try makeInMemoryContext()
        let food = makeFood(in: context)
        let entry = FoodLogEntry(food: food, day: .now, meal: .breakfast, quantity: 50, unit: .gram)
        context.insert(entry)
        entry.food = food
        try context.save()

        food.calories = 999
        food.serving = ServingDefinition(basis: .perServing, servingQuantity: 1, servingUnit: .piece)
        try context.save()

        XCTAssertEqual(entry.nutrition.calories!, 190, accuracy: 1e-9)
        XCTAssertEqual(entry.snapshotServing.basis, .per100Grams)
    }

    func testMissingNutritionStaysUnspecifiedInEntries() throws {
        let context = try makeInMemoryContext()
        let food = makeFood(in: context)
        food.fat = nil
        let entry = FoodLogEntry(food: food, day: .now, meal: .lunch, quantity: 1, unit: .serving)
        context.insert(entry)
        entry.food = food
        try context.save()
        XCTAssertNil(entry.nutrition.fat)
        XCTAssertEqual(NutritionTotals([entry.nutrition]).missingCount(for: .fat), 1)
    }

    // MARK: Deleting records

    func testDeletingAFoodKeepsDiaryHistory() throws {
        let context = try makeInMemoryContext()
        let food = makeFood(in: context)
        let entry = FoodLogEntry(food: food, day: .now, meal: .dinner, quantity: 100, unit: .gram)
        context.insert(entry)
        entry.food = food
        try context.save()

        context.delete(food)
        try context.save()

        let entries = try context.fetch(FetchDescriptor<FoodLogEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(entries.first?.food)
        XCTAssertEqual(entries.first?.foodName, "Rolled oats")
        XCTAssertEqual(entries.first!.nutrition.calories!, 380, accuracy: 1e-9)
    }

    func testDeletingASessionCascadesToExercisesAndSets() throws {
        let context = try makeInMemoryContext()
        let exercise = Exercise(name: "Back Squat", muscleGroup: .quadriceps, equipment: .barbell)
        context.insert(exercise)
        let session = WorkoutSession(name: "Legs")
        context.insert(session)
        let workoutExercise = WorkoutExercise(exercise: exercise, sortIndex: 0)
        context.insert(workoutExercise)
        workoutExercise.session = session
        workoutExercise.exercise = exercise
        let set = WorkoutSet(sortIndex: 0, weightKilograms: 100, reps: 5)
        context.insert(set)
        set.workoutExercise = workoutExercise
        try context.save()

        context.delete(session)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutExercise>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSet>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 1, "deleting history never deletes the catalogue")
    }

    func testDeletingAnExerciseKeepsWorkoutHistoryName() throws {
        let context = try makeInMemoryContext()
        let exercise = Exercise(name: "Hip Thrust", muscleGroup: .glutes, equipment: .barbell)
        context.insert(exercise)
        let session = WorkoutSession(name: "Glutes")
        context.insert(session)
        let workoutExercise = WorkoutExercise(exercise: exercise, sortIndex: 0)
        context.insert(workoutExercise)
        workoutExercise.session = session
        workoutExercise.exercise = exercise
        try context.save()

        context.delete(exercise)
        try context.save()

        let history = try context.fetch(FetchDescriptor<WorkoutExercise>())
        XCTAssertEqual(history.count, 1)
        XCTAssertNil(history.first?.exercise)
        XCTAssertEqual(history.first?.exerciseName, "Hip Thrust")
    }

    // MARK: Workout state restoration

    func testActiveSessionRestTimerAndClockRoundTrip() throws {
        let context = try makeInMemoryContext()
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let session = WorkoutSession(name: "Push", startedAt: start)
        var clock = session.clock
        clock.pause(at: start.addingTimeInterval(600))
        clock.resume(at: start.addingTimeInterval(660))
        session.clock = clock
        var timer = RestTimer(duration: 120)
        timer.start(at: start.addingTimeInterval(700))
        session.restTimer = timer
        context.insert(session)
        try context.save()

        let restored = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertEqual(restored.status, .active)
        XCTAssertEqual(restored.clock.elapsed(at: start.addingTimeInterval(1_000)), 940, accuracy: 1e-6)
        XCTAssertEqual(restored.restTimer?.remaining(at: start.addingTimeInterval(760)) ?? -1, 60, accuracy: 1e-6)
    }

    // MARK: Persistence across launches

    func testDataPersistsAcrossContainerInstances() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("store")
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }

        do {
            let container = try PersistenceController.makeContainer(location: .file(url))
            let context = ModelContext(container)
            context.insert(BodyMeasurement(kind: .bodyWeight, value: 81.4, date: .now))
            context.insert(DailyNutritionGoal(effectiveFrom: .now, targets: NutritionValues(calories: 2_300, protein: 160)))
            try context.save()
        }

        let reopened = try PersistenceController.makeContainer(location: .file(url))
        let context = ModelContext(reopened)
        let weights = try context.fetch(FetchDescriptor<BodyMeasurement>())
        XCTAssertEqual(weights.first?.value, 81.4)
        let goals = try context.fetch(FetchDescriptor<DailyNutritionGoal>())
        XCTAssertEqual(goals.first?.targets.protein, 160)
        XCTAssertNil(goals.first?.targets.fat, "unset targets stay unset")
    }

    // MARK: Seeding

    func testSeedingIsIdempotent() throws {
        let context = try makeInMemoryContext()
        Seeder.seedIfNeeded(in: context)
        let exerciseCount = try context.fetchCount(FetchDescriptor<Exercise>())
        let routineCount = try context.fetchCount(FetchDescriptor<WorkoutRoutine>())
        XCTAssertEqual(exerciseCount, Seeder.exercises.count)
        XCTAssertEqual(routineCount, Seeder.routines.count)

        Seeder.seedIfNeeded(in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), exerciseCount)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutRoutine>()), routineCount)
    }

    func testSeedRoutinesReferenceCatalogueExercises() throws {
        let names = Set(Seeder.exercises.map(\.name))
        for routine in Seeder.routines {
            for item in routine.items {
                XCTAssertTrue(names.contains(item.exercise), "\(routine.name) references unknown \(item.exercise)")
            }
        }
        XCTAssertEqual(names.count, Seeder.exercises.count, "exercise names are unique")
    }

    func testPreferencesAreCreatedOnce() throws {
        let context = try makeInMemoryContext()
        let first = PreferencesStore.current(in: context)
        let second = PreferencesStore.current(in: context)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<UserPreferences>()), 1)
    }
}

@MainActor
final class RouterAndFilterTests: XCTestCase {

    func testDeepLinks() {
        let router = AppRouter()
        XCTAssertTrue(router.handle(url: URL(string: "form://nutrition")!))
        XCTAssertEqual(router.selectedTab, .nutrition)
        XCTAssertTrue(router.handle(url: URL(string: "form://log-weight")!))
        XCTAssertEqual(router.selectedTab, .today)
        XCTAssertEqual(router.presentedSheet, .logBodyWeight)
        XCTAssertFalse(router.handle(url: URL(string: "https://example.com")!))
        XCTAssertFalse(router.handle(url: URL(string: "form://unknown")!))
    }

    func testExerciseSearchIsCaseInsensitiveAndPartial() throws {
        // Model instances need a live container, so the test creates one first.
        let context = ModelContext(try PersistenceController.makeContainer(location: .inMemory))
        let exercises = [
            Exercise(name: "Barbell Bench Press", muscleGroup: .chest, equipment: .barbell),
            Exercise(name: "Dumbbell Bench Press", muscleGroup: .chest, equipment: .dumbbell),
            Exercise(name: "Back Squat", muscleGroup: .quadriceps, equipment: .barbell)
        ]
        exercises.forEach { context.insert($0) }
        XCTAssertEqual(ExerciseFilter.apply(exercises, search: "bench", muscle: nil, equipment: nil).count, 2)
        XCTAssertEqual(ExerciseFilter.apply(exercises, search: "BENCH", muscle: nil, equipment: .dumbbell).map(\.name), ["Dumbbell Bench Press"])
        XCTAssertEqual(ExerciseFilter.apply(exercises, search: "", muscle: .quadriceps, equipment: nil).map(\.name), ["Back Squat"])
        XCTAssertTrue(ExerciseFilter.apply(exercises, search: "deadlift", muscle: nil, equipment: nil).isEmpty)
    }
}
