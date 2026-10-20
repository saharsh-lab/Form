import Foundation
import SwiftData
import FormCore

/// A body-weight or body-measurement record. Values are stored canonically:
/// kilograms for weight, centimetres for lengths, percent for body fat.
@Model
final class BodyMeasurement {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var value: Double
    var date: Date
    var notes: String
    var createdAt: Date

    init(id: UUID = UUID(), kind: MeasurementKind, value: Double, date: Date, notes: String = "") {
        self.id = id
        self.kindRaw = kind.rawValue
        self.value = value
        self.date = date
        self.notes = notes
        self.createdAt = .now
    }

    var kind: MeasurementKind {
        get { MeasurementKind(rawValue: kindRaw) ?? .bodyWeight }
        set { kindRaw = newValue.rawValue }
    }

    /// The value formatted in the user's preferred units.
    func displayValue(weightUnit: WeightUnit, lengthUnit: LengthUnit) -> String {
        switch kind.dimension {
        case .mass: return NumberText.weight(kilograms: value, unit: weightUnit)
        case .length: return NumberText.length(centimeters: value, unit: lengthUnit)
        case .percentage: return "\(value.formatted(.number.precision(.fractionLength(0...1)))) %"
        }
    }
}

/// App-wide preferences. There is exactly one instance; use `PreferencesStore.current(in:)`.
@Model
final class UserPreferences {
    @Attribute(.unique) var id: UUID
    var appearanceRaw: String
    var weightUnitRaw: String
    var lengthUnitRaw: String
    var defaultRestSeconds: Int
    var hapticsLevelRaw: String
    var restTimerNotificationsEnabled: Bool
    var remindersEnabled: Bool
    var reminderHour: Int
    var reminderMinute: Int
    var hasSeededCatalogue: Bool
    var createdAt: Date

    init(id: UUID = UUID()) {
        self.id = id
        self.appearanceRaw = AppearancePreference.system.rawValue
        self.weightUnitRaw = Self.defaultWeightUnit.rawValue
        self.lengthUnitRaw = Self.defaultWeightUnit == .pounds ? LengthUnit.inches.rawValue : LengthUnit.centimeters.rawValue
        self.defaultRestSeconds = 90
        self.hapticsLevelRaw = HapticsLevel.full.rawValue
        self.restTimerNotificationsEnabled = false
        self.remindersEnabled = false
        self.reminderHour = 19
        self.reminderMinute = 0
        self.hasSeededCatalogue = false
        self.createdAt = .now
    }

    var appearance: AppearancePreference {
        get { AppearancePreference(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }

    var weightUnit: WeightUnit {
        get { WeightUnit(rawValue: weightUnitRaw) ?? .kilograms }
        set { weightUnitRaw = newValue.rawValue }
    }

    var lengthUnit: LengthUnit {
        get { LengthUnit(rawValue: lengthUnitRaw) ?? .centimeters }
        set { lengthUnitRaw = newValue.rawValue }
    }

    var hapticsLevel: HapticsLevel {
        get { HapticsLevel(rawValue: hapticsLevelRaw) ?? .full }
        set { hapticsLevelRaw = newValue.rawValue }
    }
}

extension UserPreferences {
    /// Pounds in regions that use US customary measurement, kilograms elsewhere.
    static var defaultWeightUnit: WeightUnit {
        Locale.current.measurementSystem == .us ? .pounds : .kilograms
    }

    static let restDurationRange = 15...600
}
