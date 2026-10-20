import SwiftUI
import SwiftData
import WidgetKit
import FormCore

/// Creates a JSON or CSV export and offers it to the share sheet.
struct ExportDataView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var format: DataExporter.Format = .csv
    @State private var files: [URL] = []
    @State private var isExporting = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Picker("Format", selection: $format) {
                    ForEach(DataExporter.Format.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text(format == .json
                     ? "One file with everything: exercises, routines, workouts and sets, foods, diary entries with their saved nutrition values, saved meals, targets, measurements and preferences."
                     : "Separate files for workout sets, the food diary, foods, body measurements and nutrition targets. Values you never entered are left blank, not written as 0.")
            }

            Section {
                Button {
                    createExport()
                } label: {
                    HStack {
                        Label("Create export", systemImage: "doc.badge.arrow.up")
                        Spacer()
                        if isExporting { ProgressView() }
                    }
                }
                .disabled(isExporting)

                if !files.isEmpty {
                    ShareLink(items: files) {
                        Label(files.count == 1 ? "Share file" : "Share \(files.count) files", systemImage: "square.and.arrow.up")
                    }
                    ForEach(files, id: \.self) { url in
                        Label(url.lastPathComponent, systemImage: "doc.text")
                            .font(.footnote)
                            .foregroundStyle(Color.formTextSecondary)
                    }
                }
            } footer: {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Color.formDestructive)
                } else {
                    Text("Files are created on this iPhone. You choose where they go, for example Files, AirDrop or Mail. Weights are in kilograms and lengths in centimetres.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .formPageBackground()
        .navigationTitle("Export data")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: format) { _, _ in files = [] }
    }

    private func createExport() {
        isExporting = true
        defer { isExporting = false }
        do {
            files = try DataExporter.export(format, from: modelContext)
            errorMessage = nil
            HapticsManager.shared.saveSucceeded()
        } catch {
            files = []
            errorMessage = "Couldn't create the export: \(error.localizedDescription)"
            HapticsManager.shared.error()
        }
    }
}

/// Removes every record. Nothing is deleted until the person types DELETE.
@MainActor
enum DataReset {
    static let confirmationWord = "DELETE"

    static func deleteEverything(in context: ModelContext) throws {
        do {
            // Children first, so no object is left pointing at a deleted parent.
            try deleteAll(WorkoutSet.self, in: context)
            try deleteAll(WorkoutExercise.self, in: context)
            try deleteAll(WorkoutSession.self, in: context)
            try deleteAll(RoutineExercise.self, in: context)
            try deleteAll(WorkoutRoutine.self, in: context)
            try deleteAll(Exercise.self, in: context)
            try deleteAll(FoodLogEntry.self, in: context)
            try deleteAll(SavedMealItem.self, in: context)
            try deleteAll(SavedMeal.self, in: context)
            try deleteAll(Food.self, in: context)
            try deleteAll(DailyNutritionGoal.self, in: context)
            try deleteAll(BodyMeasurement.self, in: context)
            // Preferences are reset rather than deleted, so open screens never hold a deleted object.
            let preferences = PreferencesStore.current(in: context)
            let defaults = UserPreferences()
            preferences.appearanceRaw = defaults.appearanceRaw
            preferences.weightUnitRaw = defaults.weightUnitRaw
            preferences.lengthUnitRaw = defaults.lengthUnitRaw
            preferences.defaultRestSeconds = defaults.defaultRestSeconds
            preferences.hapticsLevelRaw = defaults.hapticsLevelRaw
            preferences.restTimerNotificationsEnabled = false
            preferences.remindersEnabled = false
            preferences.reminderHour = defaults.reminderHour
            preferences.reminderMinute = defaults.reminderMinute
            preferences.hasSeededCatalogue = false
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        WorkoutLiveActivityController.shared.endAll()
        NotificationScheduler.cancelAll()
        ReminderSync.reset()
        // Fresh start, as on first launch: the starter catalogue is seeded again.
        Seeder.seedIfNeeded(in: context)
        WidgetSync.refresh(context: context)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws {
        for object in try context.fetch(FetchDescriptor<T>()) {
            context.delete(object)
        }
    }
}

/// The "Delete all data" row with its two confirmation steps.
struct DeleteAllDataButton: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @State private var showsWarning = false
    @State private var showsTypedConfirmation = false
    @State private var typed = ""
    @State private var errorMessage: String?
    @State private var didDelete = false

    var body: some View {
        Button(role: .destructive) {
            showsWarning = true
        } label: {
            Label("Delete all data", systemImage: "trash")
                .foregroundStyle(Color.formDestructive)
        }
        .confirmationDialog("Delete all data?", isPresented: $showsWarning, titleVisibility: .visible) {
            Button("Continue", role: .destructive) {
                typed = ""
                showsTypedConfirmation = true
            }
        } message: {
            Text("This permanently removes every workout, routine, custom exercise, food, diary entry, saved meal, target and measurement from this iPhone. Consider exporting first. It can't be undone.")
        }
        .alert("Type \(DataReset.confirmationWord) to confirm", isPresented: $showsTypedConfirmation) {
            TextField(DataReset.confirmationWord, text: $typed)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Delete everything", role: .destructive) { delete() }
                .disabled(typed.trimmingCharacters(in: .whitespaces) != DataReset.confirmationWord)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Form will start fresh with the starter exercises and routines, like a new install.")
        }
        .alert("All data deleted", isPresented: $didDelete) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Form has been reset on this iPhone.")
        }
        .alert("Couldn't delete data", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nothing was deleted. \(errorMessage ?? "")")
        }
    }

    private func delete() {
        guard typed.trimmingCharacters(in: .whitespaces) == DataReset.confirmationWord else { return }
        router.isActiveWorkoutPresented = false
        do {
            try DataReset.deleteEverything(in: modelContext)
            HapticsManager.shared.level = PreferencesStore.current(in: modelContext).hapticsLevel
            didDelete = true
        } catch {
            errorMessage = error.localizedDescription
            HapticsManager.shared.error()
        }
    }
}
