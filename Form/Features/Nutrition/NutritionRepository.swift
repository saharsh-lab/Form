import Foundation
import SwiftData
import FormCore

/// Food and diary operations that touch several models at once.
/// Each method saves before returning, so callers trigger success feedback
/// only after the data is on disk. On failure, pending changes are rolled back.
@MainActor
struct NutritionRepository {
    let context: ModelContext

    enum RepositoryError: LocalizedError {
        case invalidQuantity(ScalingError)
        case saveFailed(Error)
        case emptyMeal

        var errorDescription: String? {
            switch self {
            case .invalidQuantity(.invalidQuantity):
                return "Enter a quantity greater than zero."
            case .invalidQuantity(.incompatibleUnit(let unit)):
                return "\(unit.displayName) can't be used with this food's serving basis."
            case .invalidQuantity(.invalidServingDefinition):
                return "This food's serving size is invalid. Edit the food and try again."
            case .saveFailed(let error):
                return "Couldn't save: \(error.localizedDescription)"
            case .emptyMeal:
                return "There are no foods to save."
            }
        }
    }

    // MARK: Foods

    /// Creates a copy of a food named "… (copy)". The copy is never a favourite and has no history.
    @discardableResult
    func duplicate(_ food: Food) throws -> Food {
        let copy = Food(name: Self.copyName(for: food.name),
                        servingDescription: food.servingDescription,
                        serving: food.serving,
                        nutrition: food.nutrition,
                        notes: food.notes)
        context.insert(copy)
        try save()
        return copy
    }

    func toggleFavourite(_ food: Food) throws {
        food.isFavourite.toggle()
        food.updatedAt = .now
        try save()
    }

    /// Deletes a food. Diary entries and saved-meal items keep their snapshots.
    func delete(_ food: Food) throws {
        context.delete(food)
        try save()
    }

    // MARK: Diary

    /// Logs `quantity` of `unit` of a food to a meal, storing a nutrition snapshot.
    @discardableResult
    func log(_ food: Food, quantity: Double, unit: QuantityUnit, meal: MealType, day: Date, now: Date = .now) throws -> FoodLogEntry {
        if case .failure(let error) = NutritionScaler.factor(quantity: quantity, unit: unit, serving: food.serving) {
            throw RepositoryError.invalidQuantity(error)
        }
        let entry = FoodLogEntry(food: food, day: day, meal: meal, quantity: quantity, unit: unit, loggedAt: now)
        context.insert(entry)
        entry.food = food
        food.lastLoggedAt = now
        try save()
        return entry
    }

    /// Changes an entry's quantity, unit and meal. The entry keeps its original snapshot.
    func update(_ entry: FoodLogEntry, quantity: Double, unit: QuantityUnit, meal: MealType) throws {
        if case .failure(let error) = NutritionScaler.factor(quantity: quantity, unit: unit, serving: entry.snapshotServing) {
            throw RepositoryError.invalidQuantity(error)
        }
        entry.quantity = quantity
        entry.quantityUnit = unit
        entry.meal = meal
        try save()
    }

    func move(_ entry: FoodLogEntry, to meal: MealType) throws {
        entry.meal = meal
        try save()
    }

    /// Copies an entry, including its snapshot, to a meal (by default the same one).
    @discardableResult
    func duplicate(_ entry: FoodLogEntry, to meal: MealType? = nil, now: Date = .now) throws -> FoodLogEntry {
        let copy = Self.copy(of: entry, now: now)
        if let meal { copy.meal = meal }
        context.insert(copy)
        copy.food = entry.food
        try save()
        return copy
    }

    /// Deletes an entry and returns a value copy that `restore(_:)` can re-insert for undo.
    @discardableResult
    func delete(_ entry: FoodLogEntry) throws -> DeletedLogEntry {
        let backup = DeletedLogEntry(entry)
        context.delete(entry)
        try save()
        return backup
    }

    @discardableResult
    func restore(_ backup: DeletedLogEntry) throws -> FoodLogEntry {
        let entry = backup.makeEntry()
        context.insert(entry)
        if let foodID = backup.foodID {
            var descriptor = FetchDescriptor<Food>(predicate: #Predicate<Food> { $0.id == foodID })
            descriptor.fetchLimit = 1
            entry.food = try? context.fetch(descriptor).first
        }
        try save()
        return entry
    }

    // MARK: Saved meals

    /// Saves the given diary entries as a reusable meal.
    @discardableResult
    func saveMeal(named name: String, from entries: [FoodLogEntry]) throws -> SavedMeal {
        guard !entries.isEmpty else { throw RepositoryError.emptyMeal }
        let meal = SavedMeal(name: name)
        context.insert(meal)
        for (index, entry) in entries.enumerated() {
            let item = SavedMealItem(entry: entry, sortIndex: index)
            context.insert(item)
            item.meal = meal
            item.food = entry.food
        }
        try save()
        return meal
    }

    /// Logs every item of a saved meal as its own editable diary entry.
    /// Items whose food still exists use the food's current values; items whose
    /// food was deleted use the snapshot stored in the item.
    @discardableResult
    func log(_ savedMeal: SavedMeal, to meal: MealType, day: Date, now: Date = .now) throws -> [FoodLogEntry] {
        let items = savedMeal.orderedItems
        guard !items.isEmpty else { throw RepositoryError.emptyMeal }
        var created: [FoodLogEntry] = []
        for (offset, item) in items.enumerated() {
            // Offsetting loggedAt by a millisecond keeps the saved order in the diary.
            let loggedAt = now.addingTimeInterval(Double(offset) / 1_000)
            let entry: FoodLogEntry
            if let food = item.food {
                entry = FoodLogEntry(food: food, day: day, meal: meal, quantity: item.quantity, unit: item.quantityUnit, loggedAt: loggedAt)
                context.insert(entry)
                entry.food = food
                food.lastLoggedAt = now
            } else {
                entry = FoodLogEntry(snapshotOf: item, day: day, meal: meal, loggedAt: loggedAt)
                context.insert(entry)
            }
            created.append(entry)
        }
        savedMeal.lastLoggedAt = now
        try save()
        return created
    }

    func rename(_ savedMeal: SavedMeal, to name: String) throws {
        savedMeal.name = name
        savedMeal.updatedAt = .now
        try save()
    }

    func delete(_ savedMeal: SavedMeal) throws {
        context.delete(savedMeal)
        try save()
    }

    func delete(_ item: SavedMealItem) throws {
        item.meal?.updatedAt = .now
        context.delete(item)
        try save()
    }

    // MARK: Helpers

    private func save() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw RepositoryError.saveFailed(error)
        }
    }

    static func copyName(for name: String) -> String {
        let suffix = " (copy)"
        let base = String(name.prefix(80 - suffix.count))
        return base + suffix
    }

    private static func copy(of entry: FoodLogEntry, now: Date) -> FoodLogEntry {
        DeletedLogEntry(entry).makeEntry(newID: true, loggedAt: now)
    }
}

/// A value copy of a diary entry, used for undo and duplication.
struct DeletedLogEntry {
    let id: UUID
    let day: Date
    let loggedAt: Date
    let mealRaw: String
    let quantity: Double
    let quantityUnitRaw: String
    let foodName: String
    let servingDescription: String
    let servingQuantity: Double
    let servingUnitRaw: String
    let basisRaw: String
    let calories: Double?
    let protein: Double?
    let carbohydrates: Double?
    let fat: Double?
    let notes: String
    let foodID: UUID?

    init(_ entry: FoodLogEntry) {
        id = entry.id
        day = entry.day
        loggedAt = entry.loggedAt
        mealRaw = entry.mealRaw
        quantity = entry.quantity
        quantityUnitRaw = entry.quantityUnitRaw
        foodName = entry.foodName
        servingDescription = entry.servingDescription
        servingQuantity = entry.snapshotServingQuantity
        servingUnitRaw = entry.snapshotServingUnitRaw
        basisRaw = entry.snapshotBasisRaw
        calories = entry.snapshotCalories
        protein = entry.snapshotProtein
        carbohydrates = entry.snapshotCarbohydrates
        fat = entry.snapshotFat
        notes = entry.notes
        foodID = entry.food?.id
    }

    func makeEntry(newID: Bool = false, loggedAt newLoggedAt: Date? = nil) -> FoodLogEntry {
        let entry = FoodLogEntry(id: newID ? UUID() : id,
                                 foodName: foodName,
                                 servingDescription: servingDescription,
                                 serving: ServingDefinition(basis: ServingBasis(rawValue: basisRaw) ?? .perServing,
                                                            servingQuantity: servingQuantity,
                                                            servingUnit: QuantityUnit(rawValue: servingUnitRaw) ?? .gram),
                                 nutrition: NutritionValues(calories: calories, protein: protein, carbohydrates: carbohydrates, fat: fat),
                                 day: day,
                                 meal: MealType(rawValue: mealRaw) ?? .snacks,
                                 quantity: quantity,
                                 unit: QuantityUnit(rawValue: quantityUnitRaw) ?? .serving,
                                 loggedAt: newLoggedAt ?? loggedAt)
        entry.notes = notes
        return entry
    }
}

extension FoodLogEntry {
    /// Creates an entry from a saved-meal item's snapshot (used when the item's food was deleted).
    convenience init(snapshotOf item: SavedMealItem, day: Date, meal: MealType, loggedAt: Date) {
        self.init(foodName: item.foodName,
                  servingDescription: item.servingDescription,
                  serving: item.snapshotServing,
                  nutrition: item.snapshotNutrition,
                  day: day,
                  meal: meal,
                  quantity: item.quantity,
                  unit: item.quantityUnit,
                  loggedAt: loggedAt)
    }
}
