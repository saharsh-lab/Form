import SwiftUI

// Enumerations persisted by the SwiftData models. Models store the `rawValue`
// string (which keeps predicates and migrations simple) and expose a typed
// computed property; unknown raw values fall back to a safe default.

enum MuscleGroup: String, CaseIterable, Identifiable, Codable {
    case chest, back, shoulders, biceps, triceps, forearms
    case quadriceps, hamstrings, glutes, calves, core
    case fullBody, cardio, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: return "Chest"
        case .back: return "Back"
        case .shoulders: return "Shoulders"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .forearms: return "Forearms"
        case .quadriceps: return "Quads"
        case .hamstrings: return "Hamstrings"
        case .glutes: return "Glutes"
        case .calves: return "Calves"
        case .core: return "Core"
        case .fullBody: return "Full body"
        case .cardio: return "Cardio"
        case .other: return "Other"
        }
    }
}

enum Equipment: String, CaseIterable, Identifiable, Codable {
    case barbell, dumbbell, machine, cable, kettlebell, bodyweight, band, smithMachine, cardioMachine, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .barbell: return "Barbell"
        case .dumbbell: return "Dumbbell"
        case .machine: return "Machine"
        case .cable: return "Cable"
        case .kettlebell: return "Kettlebell"
        case .bodyweight: return "Body weight"
        case .band: return "Band"
        case .smithMachine: return "Smith machine"
        case .cardioMachine: return "Cardio machine"
        case .other: return "Other"
        }
    }
}

enum MealType: String, CaseIterable, Identifiable, Codable {
    case breakfast, lunch, dinner, snacks

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        case .snacks: return "Snacks"
        }
    }

    var symbol: String {
        switch self {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .dinner: return "moon.stars"
        case .snacks: return "carrot"
        }
    }

    /// A sensible default meal for the time of day.
    static func suggested(for date: Date, calendar: Calendar = .current) -> MealType {
        switch calendar.component(.hour, from: date) {
        case 4..<11: return .breakfast
        case 11..<15: return .lunch
        case 17..<22: return .dinner
        default: return .snacks
        }
    }
}

enum WorkoutStatus: String, Codable {
    case active, completed, discarded
}

enum MeasurementKind: String, CaseIterable, Identifiable, Codable {
    case bodyWeight, bodyFat, waist, chest, hips, neck, arm, thigh

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bodyWeight: return "Body weight"
        case .bodyFat: return "Body fat"
        case .waist: return "Waist"
        case .chest: return "Chest"
        case .hips: return "Hips"
        case .neck: return "Neck"
        case .arm: return "Arm"
        case .thigh: return "Thigh"
        }
    }

    var symbol: String {
        switch self {
        case .bodyWeight: return "scalemass"
        case .bodyFat: return "percent"
        default: return "ruler"
        }
    }

    enum Dimension { case mass, length, percentage }

    /// How the canonical stored value is measured: kilograms, centimetres or percent.
    var dimension: Dimension {
        switch self {
        case .bodyWeight: return .mass
        case .bodyFat: return .percentage
        default: return .length
        }
    }

    /// Accepted range for the canonical stored value.
    var validRange: ClosedRange<Double> {
        switch dimension {
        case .mass: return 20...400        // kg
        case .percentage: return 2...70    // %
        case .length: return 10...250      // cm
        }
    }
}

enum AppearancePreference: String, CaseIterable, Identifiable, Codable {
    case system, light, dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum HapticsLevel: String, CaseIterable, Identifiable, Codable {
    /// All app haptics: set completion, selections, saves, records, timers.
    case full
    /// Only saves, records, timer completion and errors.
    case reduced
    /// No app-specific haptics.
    case off

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .full: return "Full"
        case .reduced: return "Reduced"
        case .off: return "Off"
        }
    }

    var explanation: String {
        switch self {
        case .full: return "Feedback for completed sets, selections, saves, records and timers."
        case .reduced: return "Feedback only for saves, records, timer completion and errors."
        case .off: return "No app-specific haptics. System controls keep their own feedback."
        }
    }
}
