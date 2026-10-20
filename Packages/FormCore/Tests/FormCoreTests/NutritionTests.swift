import XCTest
@testable import FormCore

final class ServingScalingTests: XCTestCase {

    private let oats = ServingDefinition(basis: .per100Grams, servingQuantity: 40, servingUnit: .gram)
    private let egg = ServingDefinition(basis: .perServing, servingQuantity: 1, servingUnit: .piece)
    private let yoghurtPot = ServingDefinition(basis: .perServing, servingQuantity: 150, servingUnit: .gram)
    private let milk = ServingDefinition(basis: .per100Milliliters, servingQuantity: 250, servingUnit: .milliliter)

    func testPer100GramsWithGrams() throws {
        XCTAssertEqual(try NutritionScaler.factor(quantity: 40, unit: .gram, serving: oats).get(), 0.4, accuracy: 1e-9)
    }

    func testPer100GramsWithServingsUsesServingWeight() throws {
        XCTAssertEqual(try NutritionScaler.factor(quantity: 2, unit: .serving, serving: oats).get(), 0.8, accuracy: 1e-9)
    }

    func testPer100GramsWithOunces() throws {
        XCTAssertEqual(try NutritionScaler.factor(quantity: 1, unit: .ounce, serving: oats).get(), 0.283_495, accuracy: 1e-6)
    }

    func testPer100GramsRejectsVolume() {
        XCTAssertEqual(NutritionScaler.factor(quantity: 100, unit: .milliliter, serving: oats), .failure(.incompatibleUnit(.milliliter)))
    }

    func testPerServingWithServingCount() throws {
        XCTAssertEqual(try NutritionScaler.factor(quantity: 3, unit: .serving, serving: egg).get(), 3, accuracy: 1e-9)
    }

    func testPerServingWithPieces() throws {
        XCTAssertEqual(try NutritionScaler.factor(quantity: 2, unit: .piece, serving: egg).get(), 2, accuracy: 1e-9)
    }

    func testPerServingWithMassConvertsThroughServingWeight() throws {
        XCTAssertEqual(try NutritionScaler.factor(quantity: 75, unit: .gram, serving: yoghurtPot).get(), 0.5, accuracy: 1e-9)
        XCTAssertEqual(try NutritionScaler.factor(quantity: 0.3, unit: .kilogram, serving: yoghurtPot).get(), 2, accuracy: 1e-9)
    }

    func testPerServingPieceRejectsGrams() {
        XCTAssertEqual(NutritionScaler.factor(quantity: 50, unit: .gram, serving: egg), .failure(.incompatibleUnit(.gram)))
    }

    func testPer100MillilitersWithCups() throws {
        XCTAssertEqual(try NutritionScaler.factor(quantity: 1, unit: .cup, serving: milk).get(), 2.4, accuracy: 1e-9)
        XCTAssertEqual(try NutritionScaler.factor(quantity: 1, unit: .serving, serving: milk).get(), 2.5, accuracy: 1e-9)
    }

    func testInvalidQuantitiesAreRejected() {
        for bad in [0, -1, Double.nan, Double.infinity] as [Double] {
            XCTAssertEqual(NutritionScaler.factor(quantity: bad, unit: .gram, serving: oats), .failure(.invalidQuantity), "\(bad)")
        }
    }

    func testInvalidServingDefinitionsAreRejected() {
        let zero = ServingDefinition(basis: .perServing, servingQuantity: 0, servingUnit: .gram)
        let selfReferential = ServingDefinition(basis: .perServing, servingQuantity: 1, servingUnit: .serving)
        XCTAssertEqual(NutritionScaler.factor(quantity: 1, unit: .serving, serving: zero), .failure(.invalidServingDefinition))
        XCTAssertEqual(NutritionScaler.factor(quantity: 1, unit: .serving, serving: selfReferential), .failure(.invalidServingDefinition))
    }

    func testScaledValuesKeepMissingValuesUnspecified() throws {
        let base = NutritionValues(calories: 389, protein: 16.9, carbohydrates: nil, fat: 6.9)
        let scaled = try NutritionScaler.values(base: base, serving: oats, quantity: 50, unit: .gram).get()
        XCTAssertEqual(scaled.calories!, 194.5, accuracy: 1e-9)
        XCTAssertEqual(scaled.protein!, 8.45, accuracy: 1e-9)
        XCTAssertNil(scaled.carbohydrates)
        XCTAssertEqual(scaled.fat!, 3.45, accuracy: 1e-9)
    }

    func testCompatibleUnits() {
        XCTAssertEqual(NutritionScaler.compatibleUnits(for: egg), [.serving, .piece])
        let oatUnits = NutritionScaler.compatibleUnits(for: oats)
        XCTAssertTrue(oatUnits.contains(.gram))
        XCTAssertTrue(oatUnits.contains(.serving))
        XCTAssertFalse(oatUnits.contains(.cup))
    }
}

final class NutritionTotalsTests: XCTestCase {

    func testSumsSpecifiedValuesAndCountsMissing() {
        let totals = NutritionTotals([
            NutritionValues(calories: 200, protein: 10, carbohydrates: 30, fat: 5),
            NutritionValues(calories: 150, protein: nil, carbohydrates: 20, fat: nil),
            NutritionValues(calories: nil, protein: 25, carbohydrates: nil, fat: 3)
        ])
        XCTAssertEqual(totals.entryCount, 3)
        XCTAssertEqual(totals.calories, 350, accuracy: 1e-9)
        XCTAssertEqual(totals.protein, 35, accuracy: 1e-9)
        XCTAssertEqual(totals.carbohydrates, 50, accuracy: 1e-9)
        XCTAssertEqual(totals.fat, 8, accuracy: 1e-9)
        XCTAssertEqual(totals.missingCount(for: .calories), 1)
        XCTAssertEqual(totals.missingCount(for: .protein), 1)
        XCTAssertEqual(totals.missingCount(for: .carbohydrates), 1)
        XCTAssertEqual(totals.missingCount(for: .fat), 1)
        XCTAssertTrue(totals.isIncomplete)
    }

    func testEmptyTotals() {
        let totals = NutritionTotals([NutritionValues]())
        XCTAssertEqual(totals.entryCount, 0)
        XCTAssertEqual(totals.calories, 0)
        XCTAssertFalse(totals.isIncomplete)
    }

    func testCompleteness() {
        XCTAssertTrue(NutritionValues(calories: 0, protein: 0, carbohydrates: 0, fat: 0).isComplete)
        XCTAssertFalse(NutritionValues(calories: 100).isComplete)
        XCTAssertFalse(NutritionValues.unspecified.hasAnyValue)
    }
}

final class TargetProgressTests: XCTestCase {

    func testUnderTarget() {
        let progress = TargetProgress(consumed: 1_500, target: 2_000)
        XCTAssertEqual(progress.status, .underTarget)
        XCTAssertEqual(progress.fraction!, 0.75, accuracy: 1e-9)
        XCTAssertEqual(progress.remaining!, 500, accuracy: 1e-9)
        XCTAssertEqual(progress.overflowFraction, 0)
    }

    func testExceededIsDistinctFromReached() {
        let exceeded = TargetProgress(consumed: 2_500, target: 2_000)
        XCTAssertEqual(exceeded.status, .exceeded)
        XCTAssertEqual(exceeded.clampedFraction, 1)
        XCTAssertEqual(exceeded.overflowFraction, 0.25, accuracy: 1e-9)
        XCTAssertEqual(exceeded.remaining!, -500, accuracy: 1e-9)

        XCTAssertEqual(TargetProgress(consumed: 2_000.2, target: 2_000).status, .reached)
    }

    func testZeroNegativeAndMissingTargetsAreSafe() {
        for target in [nil, 0, -10, Double.nan, Double.infinity] as [Double?] {
            let progress = TargetProgress(consumed: 300, target: target)
            XCTAssertEqual(progress.status, .noTarget)
            XCTAssertNil(progress.fraction)
            XCTAssertNil(progress.remaining)
            XCTAssertEqual(progress.clampedFraction, 0)
        }
    }

    func testInvalidConsumedIsTreatedAsZero() {
        XCTAssertEqual(TargetProgress(consumed: .nan, target: 100).consumed, 0)
        XCTAssertEqual(TargetProgress(consumed: -5, target: 100).consumed, 0)
    }
}

final class GoalResolverTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func day(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: string)!
    }

    func testUsesGoalInEffectOnThatDay() {
        let goals = [
            NutritionGoalSnapshot(effectiveFrom: day("2026-01-01"), targets: NutritionValues(calories: 2_000)),
            NutritionGoalSnapshot(effectiveFrom: day("2026-03-01"), targets: NutritionValues(calories: 2_400))
        ]
        XCTAssertEqual(GoalResolver.goal(on: day("2026-02-15"), from: goals, calendar: calendar)?.targets.calories, 2_000)
        XCTAssertEqual(GoalResolver.goal(on: day("2026-03-01"), from: goals, calendar: calendar)?.targets.calories, 2_400)
        XCTAssertNil(GoalResolver.goal(on: day("2025-12-31"), from: goals, calendar: calendar))
    }
}
