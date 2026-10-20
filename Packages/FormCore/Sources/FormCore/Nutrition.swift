import Foundation

/// The four values Form tracks for every food.
public enum Nutrient: String, CaseIterable, Identifiable, Codable, Sendable {
    case calories
    case protein
    case carbohydrates
    case fat

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .calories: return "Calories"
        case .protein: return "Protein"
        case .carbohydrates: return "Carbs"
        case .fat: return "Fat"
        }
    }

    public var unitSymbol: String {
        self == .calories ? "kcal" : "g"
    }
}

/// Nutrition values for some amount of food.
///
/// Each value is optional: `nil` means the user did not enter it. Form never
/// treats a missing value as a verified zero, so totals keep track of how many
/// entries were missing each value.
public struct NutritionValues: Equatable, Hashable, Codable, Sendable {
    public var calories: Double?
    public var protein: Double?
    public var carbohydrates: Double?
    public var fat: Double?

    public init(calories: Double? = nil, protein: Double? = nil, carbohydrates: Double? = nil, fat: Double? = nil) {
        self.calories = calories
        self.protein = protein
        self.carbohydrates = carbohydrates
        self.fat = fat
    }

    public static let unspecified = NutritionValues()

    public subscript(nutrient: Nutrient) -> Double? {
        get {
            switch nutrient {
            case .calories: return calories
            case .protein: return protein
            case .carbohydrates: return carbohydrates
            case .fat: return fat
            }
        }
        set {
            switch nutrient {
            case .calories: calories = newValue
            case .protein: protein = newValue
            case .carbohydrates: carbohydrates = newValue
            case .fat: fat = newValue
            }
        }
    }

    /// True when every nutrient has a value.
    public var isComplete: Bool {
        Nutrient.allCases.allSatisfy { self[$0] != nil }
    }

    /// True when at least one nutrient has a value.
    public var hasAnyValue: Bool {
        Nutrient.allCases.contains { self[$0] != nil }
    }

    /// Multiplies every specified value by `factor`. Unspecified values stay unspecified.
    public func scaled(by factor: Double) -> NutritionValues {
        precondition(factor.isFinite && factor >= 0, "Scale factor must be a finite, non-negative number")
        return NutritionValues(
            calories: calories.map { $0 * factor },
            protein: protein.map { $0 * factor },
            carbohydrates: carbohydrates.map { $0 * factor },
            fat: fat.map { $0 * factor }
        )
    }
}

/// Sum of many `NutritionValues`, with a count of entries missing each value.
public struct NutritionTotals: Equatable, Sendable {
    public private(set) var calories: Double = 0
    public private(set) var protein: Double = 0
    public private(set) var carbohydrates: Double = 0
    public private(set) var fat: Double = 0
    public private(set) var entryCount: Int = 0
    private var missing: [Nutrient: Int] = [:]

    public init() {}

    public init<S: Sequence>(_ values: S) where S.Element == NutritionValues {
        for value in values { add(value) }
    }

    public mutating func add(_ values: NutritionValues) {
        entryCount += 1
        for nutrient in Nutrient.allCases {
            if let amount = values[nutrient] {
                switch nutrient {
                case .calories: calories += amount
                case .protein: protein += amount
                case .carbohydrates: carbohydrates += amount
                case .fat: fat += amount
                }
            } else {
                missing[nutrient, default: 0] += 1
            }
        }
    }

    public func total(for nutrient: Nutrient) -> Double {
        switch nutrient {
        case .calories: return calories
        case .protein: return protein
        case .carbohydrates: return carbohydrates
        case .fat: return fat
        }
    }

    /// Number of entries that had no value for `nutrient`.
    public func missingCount(for nutrient: Nutrient) -> Int {
        missing[nutrient, default: 0]
    }

    /// True when any entry is missing any nutrient value.
    public var isIncomplete: Bool {
        missing.values.contains { $0 > 0 }
    }
}
