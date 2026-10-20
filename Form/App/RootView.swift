import SwiftUI
import SwiftData

/// Applies preferences (appearance, haptics), seeds first-launch data and hosts the tabs.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Query(sort: \UserPreferences.createdAt) private var preferences: [UserPreferences]

    private var appearance: AppearancePreference {
        preferences.first?.appearance ?? .system
    }

    var body: some View {
        @Bindable var navigation = router
        RootTabView()
            .tint(Color.formAccent)
            .preferredColorScheme(appearance.colorScheme)
            .sheet(item: $navigation.presentedSheet) { sheet in
                switch sheet {
                case .logBodyWeight:
                    MeasurementEntrySheet(kind: .bodyWeight)
                }
            }
            .task {
                Seeder.seedIfNeeded(in: modelContext)
                HapticsManager.shared.level = PreferencesStore.current(in: modelContext).hapticsLevel
            }
            .onChange(of: preferences.first?.hapticsLevelRaw) { _, _ in
                HapticsManager.shared.level = preferences.first?.hapticsLevel ?? .full
            }
    }
}

struct RootTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        // A custom binding lets re-selecting the current tab pop it to its root.
        let selection = Binding<AppTab>(
            get: { self.router.selectedTab },
            set: { self.router.select($0) }
        )
        @Bindable var navigation = router

        TabView(selection: selection) {
            NavigationStack(path: $navigation.todayPath) {
                TodayView()
            }
            .tabItem { Label("Today", systemImage: "sun.max") }
            .tag(AppTab.today)

            NavigationStack(path: $navigation.trainPath) {
                TrainView()
            }
            .tabItem { Label("Train", systemImage: "dumbbell") }
            .tag(AppTab.train)

            NavigationStack(path: $navigation.nutritionPath) {
                NutritionView()
            }
            .tabItem { Label("Nutrition", systemImage: "fork.knife") }
            .tag(AppTab.nutrition)

            NavigationStack(path: $navigation.progressPath) {
                ProgressHomeView()
            }
            .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }
            .tag(AppTab.progress)
        }
    }
}
