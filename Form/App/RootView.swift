import SwiftUI
import SwiftData

/// Applies preferences (appearance, haptics), seeds first-launch data and hosts the tabs.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \UserPreferences.createdAt) private var preferences: [UserPreferences]
    @State private var pendingAction = PendingAppAction.shared
    @State private var widgetRefresh: Task<Void, Never>?

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
                WidgetSync.refresh(context: modelContext)
                consumePendingAction()
            }
            .onChange(of: pendingAction.url) { _, _ in consumePendingAction() }
            .onChange(of: router.isStartWorkoutRequested) { _, requested in
                if requested { startOrResumeWorkout() }
            }
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                scheduleWidgetRefresh()
            }
            .onChange(of: scenePhase) { _, phase in
                // Day and week roll-overs, and anything saved while in the background.
                if phase != .inactive { WidgetSync.refresh(context: modelContext) }
            }
            .onChange(of: preferences.first?.hapticsLevelRaw) { _, _ in
                HapticsManager.shared.level = preferences.first?.hapticsLevel ?? .full
            }
    }
}

extension RootView {
    /// Coalesces bursts of saves (for example typing set values) into one refresh.
    private func scheduleWidgetRefresh() {
        widgetRefresh?.cancel()
        widgetRefresh = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            WidgetSync.refresh(context: modelContext)
        }
    }

    private func consumePendingAction() {
        guard let url = pendingAction.url else { return }
        pendingAction.url = nil
        router.handle(url: url)
    }

    private func startOrResumeWorkout() {
        router.isStartWorkoutRequested = false
        let repository = WorkoutRepository(context: modelContext)
        if repository.activeSession() == nil {
            do {
                try repository.startEmptyWorkout()
            } catch {
                HapticsManager.shared.error()
                return
            }
        }
        router.isActiveWorkoutPresented = true
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
        .fullScreenCover(isPresented: $navigation.isActiveWorkoutPresented) {
            ActiveWorkoutContainer()
        }
    }
}
