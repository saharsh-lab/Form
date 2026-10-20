import Foundation
import SwiftData
import FormCore

/// Exports everything in the local database as JSON (complete) or CSV (spreadsheet-friendly).
/// Files are written to a temporary folder and handed to the share sheet; Form never uploads them.
@MainActor
enum DataExporter {

    enum Format: String, CaseIterable, Identifiable {
        case json, csv
        var id: String { rawValue }
        var title: String { self == .json ? "JSON (complete)" : "CSV (spreadsheets)" }
    }

    /// Writes the export and returns the file URLs to share.
    static func export(_ format: Format, from context: ModelContext, now: Date = .now) throws -> [URL] {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Form Export \(CSVTable.day(now))", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        switch format {
        case .json:
            let url = folder.appendingPathComponent("form-export.json")
            try jsonData(from: context, now: now).write(to: url, options: .atomic)
            return [url]
        case .csv:
            return try csvTables(from: context).map { name, table in
                let url = folder.appendingPathComponent("\(name).csv")
                try Data(table.text.utf8).write(to: url, options: .atomic)
                return url
            }
        }
    }

    // MARK: JSON

    static func jsonData(from context: ModelContext, now: Date) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(ExportDocument(context: context, now: now))
    }

    // MARK: CSV

    static func csvTables(from context: ModelContext) throws -> [(String, CSVTable)] {
        func all<T: PersistentModel>(_ type: T.Type, sortBy: [SortDescriptor<T>] = []) throws -> [T] {
            try context.fetch(FetchDescriptor<T>(sortBy: sortBy))
        }

        var workouts = CSVTable(header: ["workout_id", "workout_name", "status", "started_at", "ended_at", "duration_seconds",
                                         "exercise_order", "exercise", "skipped", "set_order", "set_kind",
                                         "weight_kg", "reps", "duration_s", "distance_m", "completed", "completed_at"])
        for session in try all(WorkoutSession.self, sortBy: [SortDescriptor(\.startedAt)]) where session.status != .discarded {
            let duration = session.endedAt.map { session.clock.elapsed(at: $0) }
            for exercise in session.orderedExercises {
                let sets = exercise.orderedSets
                if sets.isEmpty {
                    workouts.append([session.id.uuidString, session.name, session.statusRaw, CSVTable.timestamp(session.startedAt),
                                     CSVTable.timestamp(session.endedAt), CSVTable.number(duration, maxFractionDigits: 0),
                                     "\(exercise.sortIndex + 1)", exercise.exerciseName, exercise.isSkipped ? "yes" : "no",
                                     nil, nil, nil, nil, nil, nil, nil, nil])
                }
                for (index, set) in sets.enumerated() {
                    workouts.append([session.id.uuidString, session.name, session.statusRaw, CSVTable.timestamp(session.startedAt),
                                     CSVTable.timestamp(session.endedAt), CSVTable.number(duration, maxFractionDigits: 0),
                                     "\(exercise.sortIndex + 1)", exercise.exerciseName, exercise.isSkipped ? "yes" : "no",
                                     "\(index + 1)", set.kindRaw, CSVTable.number(set.weightKilograms), set.reps.map(String.init),
                                     CSVTable.number(set.durationSeconds), CSVTable.number(set.distanceMeters),
                                     set.isCompleted ? "yes" : "no", CSVTable.timestamp(set.completedAt)])
                }
            }
        }

        var diary = CSVTable(header: ["date", "meal", "food", "quantity", "unit", "calories_kcal", "protein_g", "carbs_g", "fat_g",
                                      "logged_at", "notes"])
        for entry in try all(FoodLogEntry.self, sortBy: [SortDescriptor(\.day), SortDescriptor(\.loggedAt)]) {
            let values = entry.nutrition
            diary.append([CSVTable.day(entry.day), entry.mealRaw, entry.foodName, CSVTable.number(entry.quantity), entry.quantityUnitRaw,
                          CSVTable.number(values.calories, maxFractionDigits: 1), CSVTable.number(values.protein, maxFractionDigits: 1),
                          CSVTable.number(values.carbohydrates, maxFractionDigits: 1), CSVTable.number(values.fat, maxFractionDigits: 1),
                          CSVTable.timestamp(entry.loggedAt), entry.notes])
        }

        var foods = CSVTable(header: ["food", "basis", "serving_quantity", "serving_unit", "serving_description",
                                      "calories_kcal", "protein_g", "carbs_g", "fat_g", "favourite", "archived", "notes"])
        for food in try all(Food.self, sortBy: [SortDescriptor(\.name)]) {
            foods.append([food.name, food.basisRaw, CSVTable.number(food.servingQuantity), food.servingUnitRaw, food.servingDescription,
                          CSVTable.number(food.calories), CSVTable.number(food.protein), CSVTable.number(food.carbohydrates),
                          CSVTable.number(food.fat), food.isFavourite ? "yes" : "no", food.isArchived ? "yes" : "no", food.notes])
        }

        var measurements = CSVTable(header: ["date", "measurement", "value", "unit", "notes"])
        for measurement in try all(BodyMeasurement.self, sortBy: [SortDescriptor(\.date)]) {
            measurements.append([CSVTable.timestamp(measurement.date), measurement.kindRaw, CSVTable.number(measurement.value),
                                 measurement.kind.canonicalUnitSymbol, measurement.notes])
        }

        var goals = CSVTable(header: ["effective_from", "calories_kcal", "protein_g", "carbs_g", "fat_g"])
        for goal in try all(DailyNutritionGoal.self, sortBy: [SortDescriptor(\.effectiveFrom)]) {
            goals.append([CSVTable.day(goal.effectiveFrom), CSVTable.number(goal.calories), CSVTable.number(goal.protein),
                          CSVTable.number(goal.carbohydrates), CSVTable.number(goal.fat)])
        }

        return [("workout-sets", workouts), ("food-diary", diary), ("foods", foods),
                ("body-measurements", measurements), ("nutrition-targets", goals)]
    }
}

extension MeasurementKind {
    /// The unit values are stored in.
    var canonicalUnitSymbol: String {
        switch dimension {
        case .mass: return "kg"
        case .length: return "cm"
        case .percentage: return "%"
        }
    }
}

// MARK: - JSON document

/// A complete, versioned copy of the database. Missing values are `null`, never 0.
/// Weights are kilograms, lengths centimetres, distances metres.
struct ExportDocument: Codable {
    static let currentFormatVersion = 1

    var formatVersion = ExportDocument.currentFormatVersion
    var exportedAt: Date
    var appVersion: String
    var units = "Weights in kg, lengths in cm, distances in m, energy in kcal, macros in g"
    var preferences: Preferences?
    var exercises: [ExerciseRecord]
    var routines: [Routine]
    var workouts: [Workout]
    var foods: [FoodRecord]
    var diary: [DiaryEntry]
    var savedMeals: [SavedMealRecord]
    var nutritionTargets: [Target]
    var bodyMeasurements: [Measurement]

    struct Preferences: Codable {
        var weightUnit: String
        var lengthUnit: String
        var defaultRestSeconds: Int
        var haptics: String
        var appearance: String
    }

    struct ExerciseRecord: Codable {
        var id: UUID; var name: String; var muscleGroup: String; var equipment: String; var trackingType: String
        var isCustom: Bool; var isArchived: Bool; var notes: String
    }

    struct Routine: Codable {
        struct Entry: Codable {
            var exerciseID: UUID?; var exerciseName: String?; var targetSets: Int
            var targetRepsLower: Int?; var targetRepsUpper: Int?; var restSeconds: Int?; var notes: String
        }
        var id: UUID; var name: String; var notes: String; var entries: [Entry]
    }

    struct Workout: Codable {
        struct Set: Codable {
            var kind: String; var weightKg: Double?; var reps: Int?; var durationSeconds: Double?; var distanceMeters: Double?
            var completed: Bool; var completedAt: Date?

            enum CodingKeys: String, CodingKey {
                case kind, weightKg, reps, durationSeconds, distanceMeters, completed, completedAt
            }

            /// Writes unentered values as explicit `null` (JSONEncoder would otherwise omit them).
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(kind, forKey: .kind)
                try container.encode(weightKg, forKey: .weightKg)
                try container.encode(reps, forKey: .reps)
                try container.encode(durationSeconds, forKey: .durationSeconds)
                try container.encode(distanceMeters, forKey: .distanceMeters)
                try container.encode(completed, forKey: .completed)
                try container.encode(completedAt, forKey: .completedAt)
            }
        }
        struct Exercise: Codable {
            var exerciseID: UUID?; var name: String; var trackingType: String; var skipped: Bool; var notes: String; var sets: [Set]
        }
        var id: UUID; var name: String; var status: String; var startedAt: Date; var endedAt: Date?
        var pausedSeconds: Double; var routineID: UUID?; var notes: String; var exercises: [Exercise]
    }

    struct Nutrients: Codable {
        var calories: Double?; var protein: Double?; var carbohydrates: Double?; var fat: Double?
        init(_ values: NutritionValues) {
            calories = values.calories; protein = values.protein; carbohydrates = values.carbohydrates; fat = values.fat
        }

        enum CodingKeys: String, CodingKey { case calories, protein, carbohydrates, fat }

        /// Writes unentered values as explicit `null` (JSONEncoder would otherwise omit them).
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(calories, forKey: .calories)
            try container.encode(protein, forKey: .protein)
            try container.encode(carbohydrates, forKey: .carbohydrates)
            try container.encode(fat, forKey: .fat)
        }
    }

    struct FoodRecord: Codable {
        var id: UUID; var name: String; var basis: String; var servingQuantity: Double; var servingUnit: String
        var servingDescription: String; var nutrients: Nutrients; var isFavourite: Bool; var isArchived: Bool; var notes: String
    }

    struct DiaryEntry: Codable {
        var id: UUID; var day: Date; var loggedAt: Date; var meal: String; var foodID: UUID?; var foodName: String
        var quantity: Double; var unit: String
        /// The food's values when it was logged, per its serving basis.
        var snapshotBasis: String; var snapshotServingQuantity: Double; var snapshotServingUnit: String; var snapshotNutrients: Nutrients
        /// The values for the logged quantity.
        var nutrients: Nutrients
        var notes: String
    }

    struct SavedMealRecord: Codable {
        struct Item: Codable {
            var foodID: UUID?; var foodName: String; var quantity: Double; var unit: String; var snapshotNutrients: Nutrients
        }
        var id: UUID; var name: String; var items: [Item]
    }

    struct Target: Codable {
        var effectiveFrom: Date; var nutrients: Nutrients
    }

    struct Measurement: Codable {
        var id: UUID; var kind: String; var value: Double; var unit: String; var date: Date; var notes: String
    }
}

extension ExportDocument {
    @MainActor
    init(context: ModelContext, now: Date) throws {
        func all<T: PersistentModel>(_ type: T.Type) throws -> [T] { try context.fetch(FetchDescriptor<T>()) }

        exportedAt = now
        appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
        preferences = try all(UserPreferences.self).first.map {
            Preferences(weightUnit: $0.weightUnitRaw, lengthUnit: $0.lengthUnitRaw, defaultRestSeconds: $0.defaultRestSeconds,
                        haptics: $0.hapticsLevelRaw, appearance: $0.appearanceRaw)
        }
        exercises = try all(FormApp.Exercise.self).sorted { $0.name < $1.name }.map {
            ExerciseRecord(id: $0.id, name: $0.name, muscleGroup: $0.muscleGroupRaw, equipment: $0.equipmentRaw,
                           trackingType: $0.trackingTypeRaw, isCustom: $0.isCustom, isArchived: $0.isArchived, notes: $0.notes)
        }
        routines = try all(WorkoutRoutine.self).sorted { $0.sortIndex < $1.sortIndex }.map { routine in
            Routine(id: routine.id, name: routine.name, notes: routine.notes, entries: routine.orderedExercises.map {
                Routine.Entry(exerciseID: $0.exercise?.id, exerciseName: $0.exercise?.name, targetSets: $0.targetSets,
                              targetRepsLower: $0.targetRepsLower, targetRepsUpper: $0.targetRepsUpper,
                              restSeconds: $0.restSeconds, notes: $0.notes)
            })
        }
        workouts = try all(WorkoutSession.self).filter { $0.status != .discarded }.sorted { $0.startedAt < $1.startedAt }.map { session in
            Workout(id: session.id, name: session.name, status: session.statusRaw, startedAt: session.startedAt,
                    endedAt: session.endedAt, pausedSeconds: session.accumulatedPauseSeconds, routineID: session.routineID,
                    notes: session.notes, exercises: session.orderedExercises.map { exercise in
                        Workout.Exercise(exerciseID: exercise.exerciseID, name: exercise.exerciseName,
                                         trackingType: exercise.trackingTypeRaw, skipped: exercise.isSkipped, notes: exercise.notes,
                                         sets: exercise.orderedSets.map {
                                             Workout.Set(kind: $0.kindRaw, weightKg: $0.weightKilograms, reps: $0.reps,
                                                         durationSeconds: $0.durationSeconds, distanceMeters: $0.distanceMeters,
                                                         completed: $0.isCompleted, completedAt: $0.completedAt)
                                         })
                    })
        }
        foods = try all(Food.self).sorted { $0.name < $1.name }.map {
            FoodRecord(id: $0.id, name: $0.name, basis: $0.basisRaw, servingQuantity: $0.servingQuantity, servingUnit: $0.servingUnitRaw,
                       servingDescription: $0.servingDescription, nutrients: Nutrients($0.nutrition), isFavourite: $0.isFavourite,
                       isArchived: $0.isArchived, notes: $0.notes)
        }
        diary = try all(FoodLogEntry.self).sorted { ($0.day, $0.loggedAt) < ($1.day, $1.loggedAt) }.map {
            DiaryEntry(id: $0.id, day: $0.day, loggedAt: $0.loggedAt, meal: $0.mealRaw, foodID: $0.food?.id, foodName: $0.foodName,
                       quantity: $0.quantity, unit: $0.quantityUnitRaw, snapshotBasis: $0.snapshotBasisRaw,
                       snapshotServingQuantity: $0.snapshotServingQuantity, snapshotServingUnit: $0.snapshotServingUnitRaw,
                       snapshotNutrients: Nutrients($0.snapshotNutrition), nutrients: Nutrients($0.nutrition), notes: $0.notes)
        }
        savedMeals = try all(SavedMeal.self).sorted { $0.name < $1.name }.map { meal in
            SavedMealRecord(id: meal.id, name: meal.name, items: meal.items.sorted { $0.sortIndex < $1.sortIndex }.map {
                SavedMealRecord.Item(foodID: $0.food?.id, foodName: $0.foodName, quantity: $0.quantity, unit: $0.quantityUnitRaw,
                                     snapshotNutrients: Nutrients($0.snapshotNutrition))
            })
        }
        nutritionTargets = try all(DailyNutritionGoal.self).sorted { $0.effectiveFrom < $1.effectiveFrom }.map {
            Target(effectiveFrom: $0.effectiveFrom, nutrients: Nutrients($0.snapshot.targets))
        }
        bodyMeasurements = try all(BodyMeasurement.self).sorted { $0.date < $1.date }.map {
            Measurement(id: $0.id, kind: $0.kindRaw, value: $0.value, unit: $0.kind.canonicalUnitSymbol, date: $0.date, notes: $0.notes)
        }
    }
}
