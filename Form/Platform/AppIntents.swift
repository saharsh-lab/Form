import AppIntents
import Foundation
import Observation
import FormCore

/// Hands an action from an App Intent to the running UI. Intents that open the
/// app set a deep link here; `RootView` routes it once the interface is ready.
@MainActor
@Observable
final class PendingAppAction {
    static let shared = PendingAppAction()
    var url: URL?

    private init() {}

    func request(_ string: String) {
        url = URL(string: string)
    }
}

struct StartWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Workout"
    static var description = IntentDescription("Opens Form and starts an empty workout, or returns to the one in progress.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingAppAction.shared.request("form://start-workout")
        return .result()
    }
}

struct LogBodyWeightIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Body Weight"
    static var description = IntentDescription("Opens Form ready to record your body weight.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingAppAction.shared.request("form://log-weight")
        return .result()
    }
}

struct OpenFoodDiaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Food Diary"
    static var description = IntentDescription("Opens today's food diary in Form.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingAppAction.shared.request("form://nutrition")
        return .result()
    }
}

/// Answers without opening the app, from the snapshot the app last saved.
struct TodayNutritionIntent: AppIntent {
    static var title: LocalizedStringResource = "Today's Nutrition"
    static var description = IntentDescription("Tells you how many calories and how much protein you've logged today.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let url = AppGroup.widgetSnapshotURL, let snapshot = WidgetSnapshotStore.read(from: url) else {
            return .result(dialog: "Open Form once so it can share today's totals.")
        }
        let text = Self.summary(snapshot.nutrition(on: Date()))
        return .result(dialog: "\(text)")
    }

    static func summary(_ nutrition: WidgetSnapshot.Nutrition) -> String {
        guard nutrition.entryCount > 0 else { return "You haven't logged any food today." }
        var parts: [String] = []
        if let calories = nutrition.consumed.calories {
            var text = "\(Int(calories.rounded())) calories"
            if let target = nutrition.targets.calories { text += " of \(Int(target.rounded()))" }
            parts.append(text)
        }
        if let protein = nutrition.consumed.protein {
            var text = "\(Int(protein.rounded())) grams of protein"
            if let target = nutrition.targets.protein { text += " of \(Int(target.rounded()))" }
            parts.append(text)
        }
        guard !parts.isEmpty else { return "Today's entries don't have calorie or protein values." }
        var sentence = "So far today: " + parts.joined(separator: " and ") + "."
        if nutrition.entriesMissingCalories > 0 {
            sentence += " \(nutrition.entriesMissingCalories) entries have no calorie value."
        }
        return sentence
    }
}

struct FormShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartWorkoutIntent(),
                    phrases: ["Start a workout in \(.applicationName)", "Start \(.applicationName) workout"],
                    shortTitle: "Start Workout", systemImageName: "figure.strengthtraining.traditional")
        AppShortcut(intent: LogBodyWeightIntent(),
                    phrases: ["Log my weight in \(.applicationName)"],
                    shortTitle: "Log Weight", systemImageName: "scalemass")
        AppShortcut(intent: OpenFoodDiaryIntent(),
                    phrases: ["Open my food diary in \(.applicationName)", "Log food in \(.applicationName)"],
                    shortTitle: "Food Diary", systemImageName: "fork.knife")
        AppShortcut(intent: TodayNutritionIntent(),
                    phrases: ["How many calories today in \(.applicationName)", "\(.applicationName) nutrition today"],
                    shortTitle: "Today's Nutrition", systemImageName: "chart.pie")
    }
}
