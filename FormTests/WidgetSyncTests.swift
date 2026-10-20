import XCTest
import SwiftData
import FormCore
@testable import FormApp

@MainActor
final class WidgetSyncTests: XCTestCase {

    private var context: ModelContext!
    private let now = Date(timeIntervalSinceReferenceDate: 790_000_000)

    override func setUp() async throws {
        context = ModelContext(try PersistenceController.makeContainer(location: .inMemory))
    }

    func testEmptyStoreProducesAnHonestEmptySnapshot() {
        let snapshot = WidgetSync.makeSnapshot(context: context, now: now)
        XCTAssertEqual(snapshot.nutrition.entryCount, 0)
        XCTAssertNil(snapshot.nutrition.consumed.calories, "nothing logged is not the same as zero")
        XCTAssertNil(snapshot.nutrition.targets.calories)
        XCTAssertNil(snapshot.training.active)
        XCTAssertNil(snapshot.latestBodyWeight)
        XCTAssertEqual(snapshot.training.workoutsThisWeek, 0)
    }

    func testSnapshotReflectsTodaysDiaryGoalAndWeight() throws {
        let food = Food(name: "Oats", servingDescription: "40 g",
                        serving: ServingDefinition(basis: .perServing, servingQuantity: 40, servingUnit: .gram),
                        nutrition: NutritionValues(calories: 150, protein: 5, carbohydrates: nil, fat: 3))
        context.insert(food)
        try NutritionRepository(context: context).log(food, quantity: 2, unit: .serving, meal: .breakfast, day: now)
        // Yesterday's entry must not count.
        try NutritionRepository(context: context).log(food, quantity: 1, unit: .serving, meal: .breakfast, day: now.addingTimeInterval(-86_400))
        context.insert(DailyNutritionGoal(effectiveFrom: now.addingTimeInterval(-10 * 86_400),
                                          targets: NutritionValues(calories: 2_000, protein: 120)))
        context.insert(BodyMeasurement(kind: .bodyWeight, value: 81, date: now.addingTimeInterval(-3 * 86_400)))
        context.insert(BodyMeasurement(kind: .bodyWeight, value: 80, date: now.addingTimeInterval(-86_400)))
        try context.save()

        let snapshot = WidgetSync.makeSnapshot(context: context, now: now)
        XCTAssertEqual(snapshot.nutrition.entryCount, 1)
        XCTAssertEqual(snapshot.nutrition.consumed.calories ?? 0, 300, accuracy: 1e-9)
        XCTAssertNil(snapshot.nutrition.consumed.carbohydrates, "carbs were never entered")
        XCTAssertEqual(snapshot.nutrition.targets.calories, 2_000)
        XCTAssertEqual(snapshot.latestBodyWeight?.kilograms, 80)
    }

    func testSnapshotIncludesActiveWorkoutAndWeeklyCounts() throws {
        let repository = WorkoutRepository(context: context)
        let earlier = try repository.startEmptyWorkout(now: now.addingTimeInterval(-3_600))
        try repository.finish(earlier, now: now.addingTimeInterval(-1_800))
        let active = try repository.startEmptyWorkout(now: now)

        let snapshot = WidgetSync.makeSnapshot(context: context, now: now.addingTimeInterval(60))
        XCTAssertEqual(snapshot.training.active?.name, active.name)
        XCTAssertEqual(snapshot.training.workoutsThisWeek, 1)
        XCTAssertEqual(snapshot.training.weeklyStreak, 1)
        XCTAssertEqual(snapshot.training.lastWorkoutName, earlier.name)
    }

    func testLiveActivityStateFollowsPauseAndRest() throws {
        let squat = Exercise(name: "Back Squat", muscleGroup: .quadriceps, equipment: .barbell)
        context.insert(squat)
        let repository = WorkoutRepository(context: context)
        let session = try repository.startEmptyWorkout(now: now)
        let exercise = try repository.addExercise(squat, to: session)
        try repository.addSet(to: exercise)
        try repository.toggleCompletion(of: exercise.orderedSets[0], restDuration: 90, now: now.addingTimeInterval(60))

        var state = WorkoutLiveActivityController.contentState(for: session, now: now.addingTimeInterval(70))
        XCTAssertEqual(state.completedSets, 1)
        XCTAssertEqual(state.currentExercise, "Back Squat")
        XCTAssertEqual(state.restEndsAt, now.addingTimeInterval(150))
        XCTAssertNil(state.pausedElapsed)

        try repository.pause(session, now: now.addingTimeInterval(100))
        state = WorkoutLiveActivityController.contentState(for: session, now: now.addingTimeInterval(200))
        XCTAssertEqual(state.pausedElapsed ?? 0, 100, accuracy: 1e-6)
        XCTAssertNil(state.restEndsAt)
        XCTAssertEqual(state.restPausedRemaining ?? 0, 50, accuracy: 1e-6)
    }

    func testStartWorkoutDeepLink() {
        let router = AppRouter()
        XCTAssertTrue(router.handle(url: URL(string: "form://start-workout")!))
        XCTAssertEqual(router.selectedTab, .train)
        XCTAssertTrue(router.isStartWorkoutRequested)
    }

    func testSpokenNutritionSummary() {
        let empty = WidgetSnapshot.Nutrition(day: now, consumed: .unspecified, targets: .unspecified, entryCount: 0, entriesMissingCalories: 0)
        XCTAssertEqual(TodayNutritionIntent.summary(empty), "You haven't logged any food today.")

        let logged = WidgetSnapshot.Nutrition(day: now, consumed: NutritionValues(calories: 1_234.4, protein: 80),
                                              targets: NutritionValues(calories: 2_000), entryCount: 4, entriesMissingCalories: 1)
        XCTAssertEqual(TodayNutritionIntent.summary(logged),
                       "So far today: 1234 calories of 2000 and 80 grams of protein. 1 entries have no calorie value.")
    }
}
