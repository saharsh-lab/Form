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
    @State private var notificationsDenied = false
    @State private var reminderNotificationsDenied = false

    /// Turning the reminder on asks for notification permission first.
    private var remindersBinding: Binding<Bool> {
        Binding(
            get: { preferences.remindersEnabled },
            set: { enabled in
                guard enabled else {
                    preferences.remindersEnabled = false
                    persistAndReschedule()
                    return
                }
                Task {
                    let granted = await NotificationScheduler.requestAuthorization()
                    preferences.remindersEnabled = granted
                    reminderNotificationsDenied = !granted
                    persistAndReschedule()
                }
            }
        )
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: preferences.reminderHour, minute: preferences.reminderMinute, second: 0, of: .now) ?? .now
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                preferences.reminderHour = components.hour ?? 19
                preferences.reminderMinute = components.minute ?? 0
                persistAndReschedule()
            }
        )
    }

    /// Turning alerts on asks for notification permission first; denial leaves the toggle off.
    private var restAlertsBinding: Binding<Bool> {
        Binding(
            get: { preferences.restTimerNotificationsEnabled },
            set: { enabled in
                guard enabled else {
                    preferences.restTimerNotificationsEnabled = false
                    NotificationScheduler.cancelRestTimerAlert()
                    persist()
                    return
                }
                Task {
                    let granted = await NotificationScheduler.requestAuthorization()
                    preferences.restTimerNotificationsEnabled = granted
                    notificationsDenied = !granted
                    persist()
                }
            }
        )
    }

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
                Toggle("Rest timer alerts", isOn: restAlertsBinding)
            } header: {
                Text("Workouts")
            } footer: {
                if notificationsDenied {
                    Text("Notifications are turned off for Form in the Settings app, so rest alerts can't be shown.")
                } else {
                    Text("The rest timer starts when you complete a set. With alerts on, a local notification tells you when rest is over while Form is in the background.")
                }
            }

            Section {
                Toggle("Daily logging reminder", isOn: remindersBinding)
                if preferences.remindersEnabled {
                    DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Reminders")
            } footer: {
                if reminderNotificationsDenied {
                    Text("Notifications are turned off for Form in the Settings app, so reminders can't be shown.")
                } else {
                    Text("A quiet notification at this time on days when nothing is in your food diary yet. It's scheduled on this iPhone; nothing is sent anywhere.")
                }
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
                    ExportDataView()
                } label: {
                    Label("Export data", systemImage: "square.and.arrow.up")
                }
                DeleteAllDataButton()
            } header: {
                Text("Your data")
            } footer: {
                Text("Exports are JSON or CSV files you can save or send yourself. Deleting all data can't be undone.")
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
                Text("Widgets and the workout Live Activity can be turned off from the Home Screen and in iOS Settings › Form.")
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

    private func persistAndReschedule() {
        persist()
        ReminderSync.update(preferences: preferences, hasLoggedToday: Self.hasLoggedToday(in: modelContext))
    }

    private static func hasLoggedToday(in context: ModelContext) -> Bool {
        let today = DayBounds.range(containing: .now)
        let start = today.lowerBound
        let end = today.upperBound
        let count = (try? context.fetchCount(FetchDescriptor<FoodLogEntry>(predicate: #Predicate { $0.day >= start && $0.day < end }))) ?? 0
        return count > 0
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
