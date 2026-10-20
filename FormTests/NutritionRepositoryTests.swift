import XCTest
import SwiftData
import FormCore
@testable import FormApp

@MainActor
final class NutritionRepositoryTests: XCTestCase {

    private var context: ModelContext!
    private var repository: NutritionRepository!

    override func setUp() async throws {
        context = ModelContext(try PersistenceController.makeContainer(location: .inMemory))
        repository = NutritionRepository(context: context)
    }

    private func makeEgg(calories: Double? = 78) throws -> Food {
        let egg = Food(name: "Egg",
                       servingDescription: "1 large egg",
                       serving: ServingDefinition(basis: .perServing, servingQuantity: 50, servingUnit: .gram),
                       nutrition: NutritionValues(calories: calories, protein: 6.3, carbohydrates: 0.6, fat: 5.3))
        context.insert(egg)
        try context.save()
        return egg
    }

    private func entries() throws -> [FoodLogEntry] {
        try context.fetch(FetchDescriptor<FoodLogEntry>(sortBy: [SortDescriptor(\.loggedAt)]))
    }

    func testLoggingScalesAndUpdatesTotalsImmediately() throws {
        let egg = try makeEgg()
        try repository.log(egg, quantity: 2, unit: .serving, meal: .breakfast, day: .now)
        try repository.log(egg, quantity: 25, unit: .gram, meal: .snacks, day: .now)

        let totals = NutritionTotals(try entries().map(\.nutrition))
        XCTAssertEqual(totals.calories, 78 * 2.5, accuracy: 1e-9)
        XCTAssertNotNil(egg.lastLoggedAt)
    }

    func testLoggingRejectsInvalidQuantitiesAndUnits() throws {
        let egg = try makeEgg()
        XCTAssertThrowsError(try repository.log(egg, quantity: 0, unit: .serving, meal: .lunch, day: .now))
        XCTAssertThrowsError(try repository.log(egg, quantity: 100, unit: .milliliter, meal: .lunch, day: .now))
        XCTAssertTrue(try entries().isEmpty)
    }

    func testEditingAnEntryKeepsItsSnapshot() throws {
        let egg = try makeEgg()
        let entry = try repository.log(egg, quantity: 1, unit: .serving, meal: .breakfast, day: .now)
        egg.calories = 500
        try context.save()

        try repository.update(entry, quantity: 3, unit: .serving, meal: .dinner)
        XCTAssertEqual(entry.meal, .dinner)
        XCTAssertEqual(entry.nutrition.calories!, 234, accuracy: 1e-9, "uses the snapshot (78 kcal), not the edited food")
    }

    func testDuplicateAndMove() throws {
        let egg = try makeEgg()
        let entry = try repository.log(egg, quantity: 1, unit: .serving, meal: .breakfast, day: .now)
        let copy = try repository.duplicate(entry)
        XCTAssertNotEqual(copy.id, entry.id)
        XCTAssertEqual(copy.foodName, "Egg")
        XCTAssertEqual(copy.meal, .breakfast)
        XCTAssertTrue(copy.food === egg)

        try repository.move(copy, to: .snacks)
        XCTAssertEqual(try entries().filter { $0.meal == .snacks }.count, 1)
    }

    func testDeleteAndUndoRestoresTheSameEntry() throws {
        let egg = try makeEgg()
        let entry = try repository.log(egg, quantity: 2, unit: .serving, meal: .lunch, day: .now)
        let id = entry.id

        let backup = try repository.delete(entry)
        XCTAssertTrue(try entries().isEmpty)

        let restored = try repository.restore(backup)
        XCTAssertEqual(restored.id, id)
        XCTAssertTrue(restored.food === egg)
        XCTAssertEqual(restored.nutrition.calories!, 156, accuracy: 1e-9)
        XCTAssertEqual(try entries().count, 1)
    }

    func testMissingValuesStayUnspecifiedThroughLogging() throws {
        let egg = try makeEgg(calories: nil)
        try repository.log(egg, quantity: 2, unit: .serving, meal: .breakfast, day: .now)
        let totals = NutritionTotals(try entries().map(\.nutrition))
        XCTAssertEqual(totals.missingCount(for: .calories), 1)
        XCTAssertEqual(totals.calories, 0)
        XCTAssertEqual(totals.protein, 12.6, accuracy: 1e-9)
    }

    func testDuplicateFoodIsIndependent() throws {
        let egg = try makeEgg()
        egg.isFavourite = true
        let copy = try repository.duplicate(egg)
        XCTAssertEqual(copy.name, "Egg (copy)")
        XCTAssertFalse(copy.isFavourite)
        copy.calories = 1
        XCTAssertEqual(egg.calories, 78)
    }

    func testSavedMealLogsEditableEntriesAndSurvivesFoodDeletion() throws {
        let egg = try makeEgg()
        let toast = Food(name: "Toast",
                         serving: ServingDefinition(basis: .per100Grams, servingQuantity: 35, servingUnit: .gram),
                         nutrition: NutritionValues(calories: 260, protein: 9, carbohydrates: 48, fat: 3))
        context.insert(toast)
        try context.save()

        let first = try repository.log(egg, quantity: 2, unit: .serving, meal: .breakfast, day: .now)
        let second = try repository.log(toast, quantity: 70, unit: .gram, meal: .breakfast, day: .now)
        let saved = try repository.saveMeal(named: "Eggs on toast", from: [first, second])
        XCTAssertEqual(saved.orderedItems.map(\.foodName), ["Egg", "Toast"])

        try repository.delete(toast)

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let logged = try repository.log(saved, to: .lunch, day: tomorrow)
        XCTAssertEqual(logged.count, 2)
        XCTAssertTrue(logged.allSatisfy { $0.meal == .lunch })
        XCTAssertNil(logged[1].food, "deleted food is logged from the saved snapshot")
        XCTAssertEqual(logged[1].nutrition.calories!, 182, accuracy: 1e-9)
        XCTAssertEqual(logged[0].nutrition.calories!, 156, accuracy: 1e-9)

        // Logged entries are ordinary, editable entries.
        try repository.update(logged[0], quantity: 1, unit: .serving, meal: .lunch)
        XCTAssertEqual(logged[0].nutrition.calories!, 78, accuracy: 1e-9)
    }

    func testSavingAnEmptyMealFails() {
        XCTAssertThrowsError(try repository.saveMeal(named: "Nothing", from: []))
    }

    func testCopyNameStaysWithinLimit() {
        let long = String(repeating: "a", count: 80)
        XCTAssertLessThanOrEqual(NutritionRepository.copyName(for: long).count, 80)
    }
}

@MainActor
final class FoodEditorModelTests: XCTestCase {

    func testEmptyNutrientFieldsAreSavedAsUnspecified() throws {
        let context = ModelContext(try PersistenceController.makeContainer(location: .inMemory))
        let model = FoodEditorModel(mode: .create(prefillName: "Homemade soup"))
        model.basis = .perServing
        model.normalizeServingUnit()
        model.servingQuantityText = "1"
        model.servingUnit = .cup
        model.nutrientText = [.calories: "180", .protein: ""]
        let food = try XCTUnwrap(model.save(in: context))
        XCTAssertEqual(food.calories, 180)
        XCTAssertNil(food.protein)
        XCTAssertNil(food.carbohydrates)
        XCTAssertNil(food.fat)
    }

    func testValidationRejectsBadInput() {
        let model = FoodEditorModel(mode: .create(prefillName: "  "))
        model.servingQuantityText = "0"
        model.nutrientText = [.fat: "-2", .protein: "abc"]
        XCTAssertNil(model.validate(locale: Locale(identifier: "en_US")))
        XCTAssertNotNil(model.errors[.name])
        XCTAssertNotNil(model.errors[.servingQuantity])
        XCTAssertNotNil(model.errors[.nutrient(.fat)])
        XCTAssertNotNil(model.errors[.nutrient(.protein)])
    }

    func testPer100GramsBasisForcesAMassServingUnit() {
        let model = FoodEditorModel(mode: .create(prefillName: "Milk"))
        model.basis = .perServing
        model.servingUnit = .cup
        model.basis = .per100Grams
        model.normalizeServingUnit()
        XCTAssertEqual(model.servingUnit, .gram)
        model.basis = .per100Milliliters
        model.normalizeServingUnit()
        XCTAssertEqual(model.servingUnit, .milliliter)
    }

    func testEditingAFoodDoesNotRewriteHistory() throws {
        let context = ModelContext(try PersistenceController.makeContainer(location: .inMemory))
        let food = Food(name: "Rice",
                        serving: ServingDefinition(basis: .per100Grams, servingQuantity: 150, servingUnit: .gram),
                        nutrition: NutritionValues(calories: 130, protein: 2.7, carbohydrates: 28, fat: 0.3))
        context.insert(food)
        let entry = try NutritionRepository(context: context).log(food, quantity: 200, unit: .gram, meal: .dinner, day: .now)

        let model = FoodEditorModel(mode: .edit(food))
        model.nutrientText[.calories] = "360"
        XCTAssertNotNil(model.save(in: context))
        XCTAssertEqual(food.calories, 360)
        XCTAssertEqual(entry.nutrition.calories!, 260, accuracy: 1e-9)
    }
}
