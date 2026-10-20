import Foundation

/// A small, read-only summary of today that the app writes to the shared App Group
/// container and the widgets read. Widgets never open the database themselves, so
/// they can't block or corrupt it, and they show only values the app has saved.
public struct WidgetSnapshot: Codable, Equatable, Sendable {

    public struct Nutrition: Codable, Equatable, Sendable {
        /// The calendar day these totals belong to (start of day).
        public var day: Date
        public var consumed: NutritionValues
        public var targets: NutritionValues
        public var entryCount: Int
        /// Entries with no calorie value, so the calorie total is a lower bound.
        public var entriesMissingCalories: Int

        public init(day: Date, consumed: NutritionValues, targets: NutritionValues, entryCount: Int, entriesMissingCalories: Int) {
            self.day = day
            self.consumed = consumed
            self.targets = targets
            self.entryCount = entryCount
            self.entriesMissingCalories = entriesMissingCalories
        }

        public func progress(for nutrient: Nutrient) -> TargetProgress {
            TargetProgress(consumed: consumed[nutrient] ?? 0, target: targets[nutrient],
                           tolerance: nutrient == .calories ? 5 : 0.5)
        }
    }

    public struct ActiveWorkout: Codable, Equatable, Sendable {
        public var name: String
        public var clock: WorkoutClock
        public var completedSets: Int
        public var restTimer: RestTimer?

        public init(name: String, clock: WorkoutClock, completedSets: Int, restTimer: RestTimer?) {
            self.name = name
            self.clock = clock
            self.completedSets = completedSets
            self.restTimer = restTimer
        }
    }

    public struct Training: Codable, Equatable, Sendable {
        public var active: ActiveWorkout?
        /// Name and finish time of the most recent completed workout, if any.
        public var lastWorkoutName: String?
        public var lastWorkoutDate: Date?
        public var workoutsThisWeek: Int
        public var weeklyStreak: Int

        public init(active: ActiveWorkout?, lastWorkoutName: String?, lastWorkoutDate: Date?, workoutsThisWeek: Int, weeklyStreak: Int) {
            self.active = active
            self.lastWorkoutName = lastWorkoutName
            self.lastWorkoutDate = lastWorkoutDate
            self.workoutsThisWeek = workoutsThisWeek
            self.weeklyStreak = weeklyStreak
        }
    }

    public struct BodyWeight: Codable, Equatable, Sendable {
        public var kilograms: Double
        public var date: Date

        public init(kilograms: Double, date: Date) {
            self.kilograms = kilograms
            self.date = date
        }
    }

    /// Bumped when the format changes incompatibly; older files are ignored.
    public static let currentVersion = 1

    public var version: Int
    public var generatedAt: Date
    public var weightUnit: WeightUnit
    public var nutrition: Nutrition
    public var training: Training
    public var latestBodyWeight: BodyWeight?

    public init(generatedAt: Date, weightUnit: WeightUnit, nutrition: Nutrition, training: Training, latestBodyWeight: BodyWeight?) {
        self.version = Self.currentVersion
        self.generatedAt = generatedAt
        self.weightUnit = weightUnit
        self.nutrition = nutrition
        self.training = training
        self.latestBodyWeight = latestBodyWeight
    }

    /// Today's nutrition as of `now`. If the snapshot was written on an earlier day,
    /// nothing has been logged today yet: consumed values are empty, and the targets
    /// carry over because goals apply from their start date onwards.
    public func nutrition(on now: Date, calendar: Calendar = .current) -> Nutrition {
        if calendar.isDate(nutrition.day, inSameDayAs: now) { return nutrition }
        return Nutrition(day: calendar.startOfDay(for: now), consumed: .unspecified,
                         targets: nutrition.targets, entryCount: 0, entriesMissingCalories: 0)
    }

    /// Workouts this week as of `now`; zero once a new week has started since the snapshot.
    public func workoutsThisWeek(on now: Date, calendar: Calendar = .current) -> Int {
        let snapshotWeek = calendar.dateInterval(of: .weekOfYear, for: generatedAt)?.start
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start
        return snapshotWeek == currentWeek ? training.workoutsThisWeek : 0
    }

    /// A placeholder used in the widget gallery. It is clearly sample data and is
    /// never shown in place of the user's own data.
    public static func sample(now: Date = Date()) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: now,
            weightUnit: .kilograms,
            nutrition: Nutrition(day: Calendar.current.startOfDay(for: now),
                                 consumed: NutritionValues(calories: 1_450, protein: 96, carbohydrates: 160, fat: 48),
                                 targets: NutritionValues(calories: 2_200, protein: 150, carbohydrates: 240, fat: 70),
                                 entryCount: 6, entriesMissingCalories: 0),
            training: Training(active: nil, lastWorkoutName: "Upper body", lastWorkoutDate: now.addingTimeInterval(-86_400),
                               workoutsThisWeek: 3, weeklyStreak: 4),
            latestBodyWeight: BodyWeight(kilograms: 74.2, date: now.addingTimeInterval(-86_400))
        )
    }
}

/// Reads and writes the snapshot file atomically.
public enum WidgetSnapshotStore {
    public static let fileName = "widget-snapshot.json"

    public static func url(in container: URL) -> URL {
        container.appendingPathComponent(fileName)
    }

    public static func write(_ snapshot: WidgetSnapshot, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: [.atomic])
    }

    /// `nil` when there is no file yet, it can't be read, or it was written by an incompatible version.
    public static func read(from url: URL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.version == WidgetSnapshot.currentVersion else { return nil }
        return snapshot
    }
}
