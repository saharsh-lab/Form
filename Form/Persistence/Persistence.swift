import Foundation
import SwiftData

/// The shared App Group, used so the widget extension (Phase 5) can read the same store.
enum AppGroup {
    static let fallbackIdentifier = "group.com.example.form"

    /// Read from Info.plist (`FormAppGroupIdentifier`), which XcodeGen fills from the `FORM_APP_GROUP` build setting.
    static var identifier: String {
        (Bundle.main.object(forInfoDictionaryKey: "FormAppGroupIdentifier") as? String)
            .flatMap { $0.isEmpty || $0.hasPrefix("$(") ? nil : $0 } ?? fallbackIdentifier
    }

    /// The shared container, or nil when the App Group entitlement is unavailable
    /// (for example a signing team without App Group support).
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

enum PersistenceController {

    static let schema = Schema([
        Exercise.self,
        WorkoutRoutine.self,
        RoutineExercise.self,
        WorkoutSession.self,
        WorkoutExercise.self,
        WorkoutSet.self,
        Food.self,
        FoodLogEntry.self,
        SavedMeal.self,
        SavedMealItem.self,
        DailyNutritionGoal.self,
        BodyMeasurement.self,
        UserPreferences.self
    ])

    enum StoreLocation {
        /// The App Group container if available, otherwise the app's Application Support directory.
        case automatic
        case inMemory
        case file(URL)
    }

    /// Opens (or creates) the store. Data never leaves the device: CloudKit sync is explicitly disabled.
    static func makeContainer(location: StoreLocation = .automatic) throws -> ModelContainer {
        let configuration: ModelConfiguration
        switch location {
        case .inMemory:
            configuration = ModelConfiguration("Form", schema: schema, isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none)
        case .file(let url):
            configuration = ModelConfiguration("Form", schema: schema, url: url, cloudKitDatabase: .none)
        case .automatic:
            if let groupURL = AppGroup.containerURL {
                let url = groupURL.appendingPathComponent("Form.store")
                configuration = ModelConfiguration("Form", schema: schema, url: url, cloudKitDatabase: .none)
            } else {
                configuration = ModelConfiguration("Form", schema: schema, isStoredInMemoryOnly: false, groupContainer: .none, cloudKitDatabase: .none)
            }
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Where the on-disk store lives, for display in Settings › Privacy.
    static var storeDescription: String {
        AppGroup.containerURL == nil ? "App container (on this iPhone)" : "Shared app group container (on this iPhone)"
    }
}

@MainActor
enum PreferencesStore {
    /// Returns the single preferences record, creating it on first launch.
    @discardableResult
    static func current(in context: ModelContext) -> UserPreferences {
        var descriptor = FetchDescriptor<UserPreferences>(sortBy: [SortDescriptor(\.createdAt)])
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let preferences = UserPreferences()
        context.insert(preferences)
        try? context.save()
        return preferences
    }
}

extension ModelContext {
    /// Saves pending changes, returning the error instead of throwing so callers can show it.
    @discardableResult
    func saveReportingErrors() -> Error? {
        guard hasChanges else { return nil }
        do {
            try save()
            return nil
        } catch {
            return error
        }
    }
}
