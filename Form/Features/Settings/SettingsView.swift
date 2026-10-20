import SwiftUI
import SwiftData
import FormCore

/// App settings. Every control writes straight to the persisted `UserPreferences`.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserPreferences.createdAt) private var preferences: [UserPreferences]

    var body: some View {
        Group {
            if let preferences = preferences.first {
                SettingsForm(preferences: preferences)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { PreferencesStore.current(in: modelContext) }
            }
        }
        .formPageBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsForm: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var preferences: UserPreferences

    var body: some View {
        List {
            Section("Appearance") {
                Picker("Theme", selection: $preferences.appearance) {
                    ForEach(AppearancePreference.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section("Units") {
                Picker("Weight", selection: $preferences.weightUnit) {
                    ForEach(WeightUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                Picker("Body measurements", selection: $preferences.lengthUnit) {
                    ForEach(LengthUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
            }

            Section {
                NavigationLink {
                    NutritionGoalsView()
                } label: {
                    Label("Daily nutrition targets", systemImage: "target")
                }
            } header: {
                Text("Nutrition")
            }

            Section {
                Stepper(value: $preferences.defaultRestSeconds, in: UserPreferences.restDurationRange, step: 15) {
                    LabeledContent("Default rest", value: DurationText.clock(TimeInterval(preferences.defaultRestSeconds)))
                }
                .accessibilityValue(DurationText.summary(TimeInterval(preferences.defaultRestSeconds)))
            } header: {
                Text("Workouts")
            } footer: {
                Text("Used for the rest timer after completing a set. Individual routine exercises can override it.")
            }

            Section {
                Picker("Haptics", selection: $preferences.hapticsLevel) {
                    ForEach(HapticsLevel.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
            } header: {
                Text("Feedback")
            } footer: {
                Text(preferences.hapticsLevel.explanation)
            }

            Section {
                NavigationLink {
                    PrivacyView()
                } label: {
                    Label("Privacy", systemImage: "hand.raised")
                }
                LabeledContent("Version", value: Self.versionText)
            } header: {
                Text("About")
            } footer: {
                Text("Reminders, data export and deleting all data arrive in a later build (Phase 6).")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .onChange(of: preferences.weightUnitRaw) { _, _ in persist() }
        .onChange(of: preferences.lengthUnitRaw) { _, _ in persist() }
        .onChange(of: preferences.appearanceRaw) { _, _ in persist() }
        .onChange(of: preferences.hapticsLevelRaw) { _, _ in
            HapticsManager.shared.level = preferences.hapticsLevel
            persist()
        }
        .onChange(of: preferences.defaultRestSeconds) { _, _ in persist() }
    }

    private func persist() {
        if modelContext.saveReportingErrors() != nil {
            HapticsManager.shared.error()
        }
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }
}
