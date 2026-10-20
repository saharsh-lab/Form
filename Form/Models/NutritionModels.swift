import Foundation
import SwiftData
import FormCore

/// A food in the user's own catalogue. All values are entered by the user;
/// a `nil` nutrient means "not specified", never zero.
@Model
final class Food {
    @Attribute(.unique) var id: UUID
    var name: String
    /// Free text such as "1 medium egg" or "1 cup cooked".
    var servingDescription: String
    var servingQuantity: Double
    var servingUnitRaw: String
    var basisRaw: String
    var calories: Double?
    var protein: Double?
    var carbohydrates: Double?
    var fat: Double?
    var notes: String
    var isFavourite: Bool
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var lastLoggedAt: Date?

    @Relationship(deleteRule: .nullify, inverse: \FoodLogEntry.food)
    var logEntries: [FoodLogEntry] = []

    @Relationship(deleteRule: .nullify, inverse: \SavedMealItem.food)
    var savedMealItems: [SavedMealItem] = []

    init(id: UUID = UUID(),
         name: String,
         servingDescription: String = "",
         serving: ServingDefinition,
         nutrition: NutritionValues,
         notes: String = "",
         isFavourite: Bool = false,
         createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.servingDescription = servingDescription
        self.servingQuantity = serving.servingQuantity
        self.servingUnitRaw = serving.servingUnit.rawValue
        self.basisRaw = serving.basis.rawValue
        self.calories = nutrition.calories
        self.protein = nutrition.protein
        self.carbohydrates = nutrition.carbohydrates
        self.fat = nutrition.fat
        self.notes = notes
        self.isFavourite = isFavourite
        self.isArchived = false
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.lastLoggedAt = nil
    }

    var serving: ServingDefinition {
        get {
            ServingDefinition(basis: ServingBasis(rawValue: basisRaw) ?? .perServing,
                              servingQuantity: servingQuantity,
                              servingUnit: QuantityUnit(rawValue: servingUnitRaw) ?? .gram)
        }
        set {
            basisRaw = newValue.basis.rawValue
            servingQuantity = newValue.servingQuantity
            servingUnitRaw = newValue.servingUnit.rawValue
        }
    }

    /// Stored values, relative to `serving.basis`.
    var nutrition: NutritionValues {
        get { NutritionValues(calories: calories, protein: protein, carbohydrates: carbohydrates, fat: fat) }
        set {
            calories = newValue.calories
            protein = newValue.protein
            carbohydrates = newValue.carbohydrates
            fat = newValue.fat
        }
    }
}

/// A diary entry. It stores a full snapshot of the food's serving definition
/// and nutrition at the time it was logged, so later edits to the food never
/// silently change history.
@Model
final class FoodLogEntry {
    @Attribute(.unique) var id: UUID
    /// Start of the diary day this entry belongs to.
    var day: Date
    var loggedAt: Date
    var mealRaw: String
    var quantity: Double
    var quantityUnitRaw: String

    // Snapshot of the food when logged.
    var foodName: String
    var servingDescription: String
    var snapshotServingQuantity: Double
    var snapshotServingUnitRaw: String
    var snapshotBasisRaw: String
    var snapshotCalories: Double?
    var snapshotProtein: Double?
    var snapshotCarbohydrates: Double?
    var snapshotFat: Double?

    var notes: String
    var food: Food?

    /// Copies the food's current values as the entry's snapshot. Insert the
    /// instance into a context before linking `food`.
    init(id: UUID = UUID(),
         food: Food,
         day: Date,
         meal: MealType,
         quantity: Double,
         unit: QuantityUnit,
         loggedAt: Date = .now,
         calendar: Calendar = .current) {
        self.id = id
        self.day = calendar.startOfDay(for: day)
        self.loggedAt = loggedAt
        self.mealRaw = meal.rawValue
        self.quantity = quantity
        self.quantityUnitRaw = unit.rawValue
        self.foodName = food.name
        self.servingDescription = food.servingDescription
        self.snapshotServingQuantity = food.servingQuantity
        self.snapshotServingUnitRaw = food.servingUnitRaw
        self.snapshotBasisRaw = food.basisRaw
        self.snapshotCalories = food.calories
        self.snapshotProtein = food.protein
        self.snapshotCarbohydrates = food.carbohydrates
        self.snapshotFat = food.fat
        self.notes = ""
    }

    var meal: MealType {
        get { MealType(rawValue: mealRaw) ?? .snacks }
        set { mealRaw = newValue.rawValue }
    }

    var quantityUnit: QuantityUnit {
        get { QuantityUnit(rawValue: quantityUnitRaw) ?? .serving }
        set { quantityUnitRaw = newValue.rawValue }
    }

    var snapshotServing: ServingDefinition {
        ServingDefinition(basis: ServingBasis(rawValue: snapshotBasisRaw) ?? .perServing,
                          servingQuantity: snapshotServingQuantity,
                          servingUnit: QuantityUnit(rawValue: snapshotServingUnitRaw) ?? .gram)
    }

    var snapshotNutrition: NutritionValues {
        NutritionValues(calories: snapshotCalories, protein: snapshotProtein, carbohydrates: snapshotCarbohydrates, fat: snapshotFat)
    }

    /// Nutrition for the logged quantity. If the stored quantity cannot be
    /// scaled (corrupt data), every value is reported as unspecified rather than zero.
    var nutrition: NutritionValues {
        (try? NutritionScaler.values(base: snapshotNutrition,
                                     serving: snapshotServing,
                                     quantity: quantity,
                                     unit: quantityUnit).get()) ?? .unspecified
    }
}

/// A saved combination of foods that can be logged in one step.
@Model
final class SavedMeal {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var lastLoggedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \SavedMealItem.meal)
    var items: [SavedMealItem] = []

    init(id: UUID = UUID(), name: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.lastLoggedAt = nil
    }

    var orderedItems: [SavedMealItem] {
        items.sorted { $0.sortIndex < $1.sortIndex }
    }
}

/// A component of a saved meal. Keeps a snapshot so the meal still works if
/// the food is deleted; while the food exists, its current values are used.
@Model
final class SavedMealItem {
    @Attribute(.unique) var id: UUID
    var sortIndex: Int
    var quantity: Double
    var quantityUnitRaw: String

    var foodName: String
    var servingDescription: String
    var snapshotServingQuantity: Double
    var snapshotServingUnitRaw: String
    var snapshotBasisRaw: String
    var snapshotCalories: Double?
    var snapshotProtein: Double?
    var snapshotCarbohydrates: Double?
    var snapshotFat: Double?

    var meal: SavedMeal?
    var food: Food?

    /// Insert the instance into a context before linking `meal` and `food`.
    init(id: UUID = UUID(), food: Food, quantity: Double, unit: QuantityUnit, sortIndex: Int) {
        self.id = id
        self.sortIndex = sortIndex
        self.quantity = quantity
        self.quantityUnitRaw = unit.rawValue
        self.foodName = food.name
        self.servingDescription = food.servingDescription
        self.snapshotServingQuantity = food.servingQuantity
        self.snapshotServingUnitRaw = food.servingUnitRaw
        self.snapshotBasisRaw = food.basisRaw
        self.snapshotCalories = food.calories
        self.snapshotProtein = food.protein
        self.snapshotCarbohydrates = food.carbohydrates
        self.snapshotFat = food.fat
    }

    var quantityUnit: QuantityUnit {
        get { QuantityUnit(rawValue: quantityUnitRaw) ?? .serving }
        set { quantityUnitRaw = newValue.rawValue }
    }
}

/// A daily nutrition target that applies from `effectiveFrom` onwards.
/// Keeping a history of goals means past days are judged against the goal
/// that applied at the time.
@Model
final class DailyNutritionGoal {
    @Attribute(.unique) var id: UUID
    /// Start of the first day this goal applies to.
    var effectiveFrom: Date
    var calories: Double?
    var protein: Double?
    var carbohydrates: Double?
    var fat: Double?
    var updatedAt: Date

    init(id: UUID = UUID(), effectiveFrom: Date, targets: NutritionValues, calendar: Calendar = .current) {
        self.id = id
        self.effectiveFrom = calendar.startOfDay(for: effectiveFrom)
        self.calories = targets.calories
        self.protein = targets.protein
        self.carbohydrates = targets.carbohydrates
        self.fat = targets.fat
        self.updatedAt = .now
    }

    var targets: NutritionValues {
        get { NutritionValues(calories: calories, protein: protein, carbohydrates: carbohydrates, fat: fat) }
        set {
            calories = newValue.calories
            protein = newValue.protein
            carbohydrates = newValue.carbohydrates
            fat = newValue.fat
            updatedAt = .now
        }
    }

    var snapshot: NutritionGoalSnapshot {
        NutritionGoalSnapshot(effectiveFrom: effectiveFrom, targets: targets)
    }
}
