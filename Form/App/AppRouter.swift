import SwiftUI
import Observation

enum AppTab: String, Hashable, CaseIterable {
    case today, train, nutrition, progress
}

/// Sheets presented over the whole app, for example from quick actions and deep links.
enum AppSheet: String, Identifiable {
    case logBodyWeight

    var id: String { rawValue }
}

/// Owns tab selection and each tab's navigation path, so every tab keeps its
/// own stack when you switch away and back. Also routes `form://` deep links,
/// used by widgets, the Live Activity and App Intents.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .today
    var todayPath = NavigationPath()
    var trainPath = NavigationPath()
    var nutritionPath = NavigationPath()
    var progressPath = NavigationPath()
    var presentedSheet: AppSheet?
    /// Shows the in-progress workout full screen. Closing it keeps the workout running.
    var isActiveWorkoutPresented = false
    /// Set by `form://start-workout`; `RootView` starts or resumes the workout and clears it.
    var isStartWorkoutRequested = false

    /// Selecting the current tab again pops it to its root, matching system apps.
    func select(_ tab: AppTab) {
        if tab == selectedTab {
            popToRoot(tab)
        }
        selectedTab = tab
    }

    func popToRoot(_ tab: AppTab) {
        switch tab {
        case .today: todayPath = NavigationPath()
        case .train: trainPath = NavigationPath()
        case .nutrition: nutritionPath = NavigationPath()
        case .progress: progressPath = NavigationPath()
        }
    }

    /// Handles URLs such as `form://nutrition`, `form://workout`, `form://start-workout` or `form://log-weight`.
    /// Returns false for URLs Form does not understand.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard url.scheme == "form", let host = url.host() else { return false }
        switch host {
        case "today": selectedTab = .today
        case "train": selectedTab = .train
        case "nutrition": selectedTab = .nutrition
        case "progress": selectedTab = .progress
        case "workout":
            selectedTab = .train
            isActiveWorkoutPresented = true
        case "start-workout":
            selectedTab = .train
            isStartWorkoutRequested = true
        case "log-weight":
            selectedTab = .today
            presentedSheet = .logBodyWeight
        default:
            return false
        }
        return true
    }
}
