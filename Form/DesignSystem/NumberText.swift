import Foundation
import FormCore

/// Locale-aware number formatting for display.
enum NumberText {
    /// Whole numbers for large amounts, one decimal for small ones: "1,240", "62", "7.5".
    static func amount(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if abs(value) >= 100 {
            return value.formatted(.number.precision(.fractionLength(0)))
        }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// A value with up to `digits` decimals, for editable fields.
    static func editable(_ value: Double?, maxFractionDigits digits: Int = 2) -> String {
        guard let value, value.isFinite else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...digits)).grouping(.never))
    }

    /// A stored kilogram value in the user's unit: "82.5 kg", "181.9 lb".
    static func weight(kilograms: Double, unit: WeightUnit) -> String {
        let converted = unit.fromKilograms(kilograms)
        return "\(converted.formatted(.number.precision(.fractionLength(0...1)))) \(unit.symbol)"
    }

    /// A stored centimetre value in the user's unit.
    static func length(centimeters: Double, unit: LengthUnit) -> String {
        let converted = unit.fromCentimeters(centimeters)
        return "\(converted.formatted(.number.precision(.fractionLength(0...1)))) \(unit.symbol)"
    }
}
