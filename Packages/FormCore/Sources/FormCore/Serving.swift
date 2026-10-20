import Foundation

/// Units a food quantity can be logged in.
public enum QuantityUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case serving
    case gram
    case kilogram
    case ounce
    case pound
    case milliliter
    case liter
    case fluidOunce
    case cup
    case tablespoon
    case teaspoon
    case piece

    public enum Dimension: Sendable {
        case serving
        case mass
        case volume
        case count
    }

    public var id: String { rawValue }

    public var dimension: Dimension {
        switch self {
        case .serving: return .serving
        case .gram, .kilogram, .ounce, .pound: return .mass
        case .milliliter, .liter, .fluidOunce, .cup, .tablespoon, .teaspoon: return .volume
        case .piece: return .count
        }
    }

    /// Grams per unit for mass units, millilitres per unit for volume units,
    /// and 1 for count units. `nil` for `.serving`, which has no fixed size.
    ///
    /// Volume measures use US customary sizes: 1 cup = 240 ml,
    /// 1 tbsp = 15 ml, 1 tsp = 5 ml, 1 fl oz = 29.5735 ml.
    public var baseFactor: Double? {
        switch self {
        case .serving: return nil
        case .gram: return 1
        case .kilogram: return 1_000
        case .ounce: return 28.349_523_125
        case .pound: return 453.592_37
        case .milliliter: return 1
        case .liter: return 1_000
        case .fluidOunce: return 29.573_529_562_5
        case .cup: return 240
        case .tablespoon: return 15
        case .teaspoon: return 5
        case .piece: return 1
        }
    }

    public var symbol: String {
        switch self {
        case .serving: return "serving"
        case .gram: return "g"
        case .kilogram: return "kg"
        case .ounce: return "oz"
        case .pound: return "lb"
        case .milliliter: return "ml"
        case .liter: return "l"
        case .fluidOunce: return "fl oz"
        case .cup: return "cup"
        case .tablespoon: return "tbsp"
        case .teaspoon: return "tsp"
        case .piece: return "piece"
        }
    }

    public var displayName: String {
        switch self {
        case .serving: return "Servings"
        case .gram: return "Grams"
        case .kilogram: return "Kilograms"
        case .ounce: return "Ounces"
        case .pound: return "Pounds"
        case .milliliter: return "Millilitres"
        case .liter: return "Litres"
        case .fluidOunce: return "Fluid ounces"
        case .cup: return "Cups"
        case .tablespoon: return "Tablespoons"
        case .teaspoon: return "Teaspoons"
        case .piece: return "Pieces"
        }
    }

    /// Units that make sense as a food's serving size.
    public static var servingSizeUnits: [QuantityUnit] {
        allCases.filter { $0 != .serving }
    }
}

/// What the stored nutrition values of a food refer to.
public enum ServingBasis: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Values describe one serving, as defined by the food's serving size.
    case perServing
    /// Values describe 100 grams of the food.
    case per100Grams
    /// Values describe 100 millilitres of the food.
    case per100Milliliters

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .perServing: return "Per serving"
        case .per100Grams: return "Per 100 g"
        case .per100Milliliters: return "Per 100 ml"
        }
    }
}

/// A food's serving definition: the basis of its nutrition values and the
/// size of one serving (for example 30 g, 250 ml or 1 piece).
public struct ServingDefinition: Equatable, Hashable, Codable, Sendable {
    public var basis: ServingBasis
    public var servingQuantity: Double
    public var servingUnit: QuantityUnit

    public init(basis: ServingBasis, servingQuantity: Double, servingUnit: QuantityUnit) {
        self.basis = basis
        self.servingQuantity = servingQuantity
        self.servingUnit = servingUnit
    }
}

public enum ScalingError: Error, Equatable, Sendable {
    /// The logged quantity was zero, negative, or not a number.
    case invalidQuantity
    /// The food's serving size is zero, negative, not a number, or uses `.serving` as its own unit.
    case invalidServingDefinition
    /// The logged unit cannot be converted to the food's nutrition basis,
    /// for example millilitres for a food described per 100 g.
    case incompatibleUnit(QuantityUnit)
}

/// Converts a logged quantity into a multiplier for a food's stored nutrition values.
public enum NutritionScaler {

    /// The factor to multiply the food's stored values by for `quantity` of `unit`.
    public static func factor(quantity: Double, unit: QuantityUnit, serving: ServingDefinition) -> Result<Double, ScalingError> {
        guard quantity.isFinite, quantity > 0 else { return .failure(.invalidQuantity) }
        guard serving.servingQuantity.isFinite,
              serving.servingQuantity > 0,
              serving.servingUnit != .serving,
              let servingFactor = serving.servingUnit.baseFactor else {
            return .failure(.invalidServingDefinition)
        }
        // Size of one serving in base units (grams, millilitres, or pieces).
        let servingSizeInBase = serving.servingQuantity * servingFactor

        switch serving.basis {
        case .perServing:
            if unit == .serving { return .success(quantity) }
            guard unit.dimension == serving.servingUnit.dimension, let unitFactor = unit.baseFactor else {
                return .failure(.incompatibleUnit(unit))
            }
            return .success(quantity * unitFactor / servingSizeInBase)

        case .per100Grams, .per100Milliliters:
            let required: QuantityUnit.Dimension = serving.basis == .per100Grams ? .mass : .volume
            if unit == .serving {
                guard serving.servingUnit.dimension == required else { return .failure(.incompatibleUnit(unit)) }
                return .success(quantity * servingSizeInBase / 100)
            }
            guard unit.dimension == required, let unitFactor = unit.baseFactor else {
                return .failure(.incompatibleUnit(unit))
            }
            return .success(quantity * unitFactor / 100)
        }
    }

    /// Nutrition values for `quantity` of `unit` of a food whose stored values are `base`.
    public static func values(base: NutritionValues, serving: ServingDefinition, quantity: Double, unit: QuantityUnit) -> Result<NutritionValues, ScalingError> {
        factor(quantity: quantity, unit: unit, serving: serving).map { base.scaled(by: $0) }
    }

    /// Units a food can be logged in, in a sensible display order.
    public static func compatibleUnits(for serving: ServingDefinition) -> [QuantityUnit] {
        QuantityUnit.allCases.filter {
            if case .success = factor(quantity: 1, unit: $0, serving: serving) { return true }
            return false
        }
    }
}
