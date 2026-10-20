import Foundation

/// Unit used to display and enter loads and body weight.
/// Form always stores mass in kilograms; this unit only affects presentation.
public enum WeightUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case kilograms
    case pounds

    public static let poundsPerKilogram = 2.204_622_621_8

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .kilograms: return "kg"
        case .pounds: return "lb"
        }
    }

    public var displayName: String {
        switch self {
        case .kilograms: return "Kilograms"
        case .pounds: return "Pounds"
        }
    }

    /// Converts a stored kilogram value into this unit.
    public func fromKilograms(_ kilograms: Double) -> Double {
        switch self {
        case .kilograms: return kilograms
        case .pounds: return kilograms * Self.poundsPerKilogram
        }
    }

    /// Converts a value entered in this unit into kilograms for storage.
    public func toKilograms(_ value: Double) -> Double {
        switch self {
        case .kilograms: return value
        case .pounds: return value / Self.poundsPerKilogram
        }
    }

    /// The smallest sensible increment for weight steppers in this unit.
    public var increment: Double {
        switch self {
        case .kilograms: return 2.5
        case .pounds: return 5
        }
    }
}

/// Unit used for body measurements such as waist circumference.
/// Form stores lengths in centimetres.
public enum LengthUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case centimeters
    case inches

    public static let centimetersPerInch = 2.54

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .centimeters: return "cm"
        case .inches: return "in"
        }
    }

    public var displayName: String {
        switch self {
        case .centimeters: return "Centimetres"
        case .inches: return "Inches"
        }
    }

    public func fromCentimeters(_ centimeters: Double) -> Double {
        switch self {
        case .centimeters: return centimeters
        case .inches: return centimeters / Self.centimetersPerInch
        }
    }

    public func toCentimeters(_ value: Double) -> Double {
        switch self {
        case .centimeters: return value
        case .inches: return value * Self.centimetersPerInch
        }
    }
}

/// Unit used for cardio distances. Form stores distances in metres.
public enum DistanceUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case kilometers
    case miles

    public static let metersPerMile = 1_609.344

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .kilometers: return "km"
        case .miles: return "mi"
        }
    }

    public func fromMeters(_ meters: Double) -> Double {
        switch self {
        case .kilometers: return meters / 1_000
        case .miles: return meters / Self.metersPerMile
        }
    }

    public func toMeters(_ value: Double) -> Double {
        switch self {
        case .kilometers: return value * 1_000
        case .miles: return value * Self.metersPerMile
        }
    }

    /// Distance unit that pairs naturally with a weight unit preference.
    public static func matching(_ weightUnit: WeightUnit) -> DistanceUnit {
        weightUnit == .pounds ? .miles : .kilometers
    }
}
