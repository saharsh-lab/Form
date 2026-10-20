import XCTest
import SwiftData
import FormCore
@testable import FormApp

@MainActor
final class DataManagementTests: XCTestCase {

    private var context: ModelContext!
    private let now = Date(timeIntervalSinceReferenceDate: 790_000_000)

    override func setUp() async throws {
        context = ModelContext(try PersistenceController.makeContainer(location: .inMemory))
        Seeder.seedIfNeeded(in: context)
    }

    /// One of everything: a finished workout, a food with a missing value logged once, a target and a weight.
    private func populate() throws {
        let workouts = WorkoutRepository(context: context)
        let weighted = ExerciseTrackingType.weightAndReps.rawValue
        let squat = try XCTUnwrap(try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.trackingTypeRaw == weighted })).first)
        let session = try workouts.startEmptyWorkout(now: now)
        let exercise = try workouts.addExercise(squat, to: session)
        try workouts.update(exercise.orderedSets[0], weightKilograms: .some(100), reps: .some(5))
        try workouts.toggleCompletion(of: exercise.orderedSets[0], restDuration: nil, now: now)
        try workouts.finish(session, now: now.addingTimeInterval(1_800))

        let food = Food(name: "Rice, cooked", servingDescription: "1 cup",
                        serving: ServingDefinition(basis: .per100Grams, servingQuantity: 100, servingUnit: .gram),
                        nutrition: NutritionValues(calories: 130, protein: 2.7, carbohydrates: 28, fat: nil))
        context.insert(food)
        try NutritionRepository(context: context).log(food, quantity: 150, unit: .gram, meal: .lunch, day: now)
        context.insert(DailyNutritionGoal(effectiveFrom: now, targets: NutritionValues(calories: 2_200)))
        context.insert(BodyMeasurement(kind: .bodyWeight, value: 75.5, date: now))
        try context.save()
    }

    func testJSONExportIsCompleteAndKeepsMissingValuesNull() throws {
        try populate()
        let data = try DataExporter.jsonData(from: context, now: now)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(ExportDocument.self, from: data)

        XCTAssertEqual(document.formatVersion, ExportDocument.currentFormatVersion)
        XCTAssertEqual(document.workouts.count, 1)
        XCTAssertEqual(document.workouts.first?.exercises.first?.sets.first?.weightKg, 100)
        XCTAssertEqual(document.diary.count, 1)
        XCTAssertEqual(document.diary.first?.nutrients.calories ?? 0, 195, accuracy: 1e-9)
        XCTAssertNil(document.diary.first?.nutrients.fat, "a value never entered is exported as null")
        XCTAssertEqual(document.bodyMeasurements.first?.unit, "kg")
        XCTAssertEqual(document.nutritionTargets.first?.nutrients.calories, 2_200)
        XCTAssertFalse(document.exercises.isEmpty)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"fat\" : null"))
    }

    func testCSVExportWritesBlankForMissingValues() throws {
        try populate()
        let tables = Dictionary(uniqueKeysWithValues: try DataExporter.csvTables(from: context))
        let diary = try XCTUnwrap(tables["food-diary"])
        XCTAssertEqual(diary.rows.count, 1)
        let row = diary.rows[0]
        XCTAssertEqual(row[diary.header.firstIndex(of: "food")!], "Rice, cooked")
        XCTAssertEqual(row[diary.header.firstIndex(of: "calories_kcal")!], "195")
        XCTAssertEqual(row[diary.header.firstIndex(of: "fat_g")!], "")
        XCTAssertTrue(diary.text.contains("\"Rice, cooked\""))

        let sets = try XCTUnwrap(tables["workout-sets"])
        XCTAssertEqual(sets.rows.count, 1)
        XCTAssertEqual(sets.rows[0][sets.header.firstIndex(of: "weight_kg")!], "100")
    }

    func testExportWritesFilesToShare() throws {
        try populate()
        let csv = try DataExporter.export(.csv, from: context, now: now)
        XCTAssertEqual(csv.map(\.lastPathComponent).sorted(),
                       ["body-measurements.csv", "food-diary.csv", "foods.csv", "nutrition-targets.csv", "workout-sets.csv"])
        let json = try DataExporter.export(.json, from: context, now: now)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(json.first).path))
    }

    func testDeleteEverythingResetsToAFreshInstall() throws {
        try populate()
        let preferences = PreferencesStore.current(in: context)
        preferences.weightUnit = preferences.weightUnit == .kilograms ? .pounds : .kilograms
        preferences.remindersEnabled = true
        try context.save()

        try DataReset.deleteEverything(in: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSet>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Food>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodLogEntry>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DailyNutritionGoal>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BodyMeasurement>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<UserPreferences>()), 1)
        XCTAssertEqual(PreferencesStore.current(in: context).weightUnit, UserPreferences.defaultWeightUnit)
        XCTAssertFalse(PreferencesStore.current(in: context).remindersEnabled)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), Seeder.exercises.count, "starter catalogue is back")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutRoutine>()), Seeder.routines.count)
    }
}
