import Foundation

/// The role of a set within an exercise.
public enum SetKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case warmUp
    case working
    case drop

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .warmUp: return "Warm-up"
        case .working: return "Working"
        case .drop: return "Drop"
        }
    }

    /// One-letter badge used in set rows (W, D) — working sets show their number instead.
    public var badge: String? {
        switch self {
        case .warmUp: return "W"
        case .working: return nil
        case .drop: return "D"
        }
    }
}

/// What an exercise records for each set. Records are only ever compared
/// between sets of the same exercise and tracking type.
public enum ExerciseTrackingType: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Load and repetitions, for example barbell squat.
    case weightAndReps
    /// Repetitions only, for example pull-ups at body weight.
    case repsOnly
    /// Time only, for example plank.
    case duration
    /// Distance and time, for example rowing or running.
    case distanceAndDuration

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .weightAndReps: return "Weight × reps"
        case .repsOnly: return "Reps only"
        case .duration: return "Duration"
        case .distanceAndDuration: return "Distance & duration"
        }
    }

    /// Whether weight × reps volume applies to this exercise.
    public var supportsVolume: Bool { self == .weightAndReps }

    public var recordKinds: [RecordKind] {
        switch self {
        case .weightAndReps: return [.heaviestWeight, .bestEstimatedOneRepMax, .bestSetVolume]
        case .repsOnly: return [.mostReps]
        case .duration: return [.longestDuration]
        case .distanceAndDuration: return [.longestDistance, .longestDuration]
        }
    }
}

/// A logged set reduced to the values calculations need. Weight is in kilograms,
/// duration in seconds and distance in metres.
public struct SetPerformance: Equatable, Hashable, Codable, Sendable {
    public var kind: SetKind
    public var weightKilograms: Double?
    public var reps: Int?
    public var durationSeconds: Double?
    public var distanceMeters: Double?
    public var isCompleted: Bool

    public init(kind: SetKind = .working,
                weightKilograms: Double? = nil,
                reps: Int? = nil,
                durationSeconds: Double? = nil,
                distanceMeters: Double? = nil,
                isCompleted: Bool = true) {
        self.kind = kind
        self.weightKilograms = weightKilograms
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.isCompleted = isCompleted
    }

    /// Completed warm-ups are excluded from volume, set counts and records.
    public var countsAsWorkSet: Bool {
        isCompleted && kind != .warmUp
    }
}

public enum WorkoutCalculator {

    /// weight × reps for a completed working or drop set with a positive load and reps; otherwise 0.
    public static func volume(of set: SetPerformance) -> Double {
        guard set.countsAsWorkSet,
              let weight = set.weightKilograms, weight.isFinite, weight > 0,
              let reps = set.reps, reps > 0 else { return 0 }
        return weight * Double(reps)
    }

    /// Total volume in kilograms. Zero for exercises whose tracking type has no volume.
    public static func volume(of sets: [SetPerformance], trackingType: ExerciseTrackingType) -> Double {
        guard trackingType.supportsVolume else { return 0 }
        return sets.reduce(0) { $0 + volume(of: $1) }
    }

    /// Number of completed sets. Warm-ups are excluded unless `includeWarmUps` is true.
    public static func completedSetCount(_ sets: [SetPerformance], includeWarmUps: Bool = false) -> Int {
        sets.filter { includeWarmUps ? $0.isCompleted : $0.countsAsWorkSet }.count
    }

    /// Epley estimate of a one-repetition maximum. Returns the weight itself for
    /// a single, and `nil` above 12 reps where the estimate is unreliable.
    public static func estimatedOneRepMax(weightKilograms weight: Double, reps: Int) -> Double? {
        guard weight.isFinite, weight > 0, reps > 0, reps <= 12 else { return nil }
        if reps == 1 { return weight }
        return weight * (1 + Double(reps) / 30)
    }
}

/// The kinds of personal record Form tracks. Each applies to one tracking type family.
public enum RecordKind: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Heaviest load lifted for at least one rep.
    case heaviestWeight
    /// Highest Epley estimated one-rep max (sets of 1–12 reps).
    case bestEstimatedOneRepMax
    /// Highest weight × reps in a single set.
    case bestSetVolume
    /// Most reps in one set (reps-only exercises).
    case mostReps
    /// Longest single set duration.
    case longestDuration
    /// Longest single set distance.
    case longestDistance

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .heaviestWeight: return "Heaviest weight"
        case .bestEstimatedOneRepMax: return "Best estimated 1RM"
        case .bestSetVolume: return "Best set volume"
        case .mostReps: return "Most reps"
        case .longestDuration: return "Longest duration"
        case .longestDistance: return "Longest distance"
        }
    }
}

public enum PersonalRecordCalculator {

    /// Best value of each applicable record kind across `sets`.
    /// Only completed working and drop sets with valid values are considered.
    public static func bests(in sets: [SetPerformance], trackingType: ExerciseTrackingType) -> [RecordKind: Double] {
        var result: [RecordKind: Double] = [:]
        func consider(_ kind: RecordKind, _ value: Double?) {
            guard let value, value.isFinite, value > 0 else { return }
            if value > (result[kind] ?? 0) { result[kind] = value }
        }
        for set in sets where set.countsAsWorkSet {
            switch trackingType {
            case .weightAndReps:
                guard let weight = set.weightKilograms, let reps = set.reps, reps > 0 else { continue }
                consider(.heaviestWeight, weight)
                consider(.bestEstimatedOneRepMax, WorkoutCalculator.estimatedOneRepMax(weightKilograms: weight, reps: reps))
                consider(.bestSetVolume, WorkoutCalculator.volume(of: set))
            case .repsOnly:
                consider(.mostReps, set.reps.map { Double($0) })
            case .duration:
                consider(.longestDuration, set.durationSeconds)
            case .distanceAndDuration:
                consider(.longestDistance, set.distanceMeters)
                consider(.longestDuration, set.durationSeconds)
            }
        }
        return result
    }

    /// Records in `current` that strictly beat `previousBests`.
    ///
    /// A record kind with no previous value is not reported: the first time an
    /// exercise is logged establishes a baseline rather than a celebrated record.
    public static func newRecords(current sets: [SetPerformance],
                                  previousBests: [RecordKind: Double],
                                  trackingType: ExerciseTrackingType,
                                  epsilon: Double = 0.000_1) -> [RecordKind: Double] {
        bests(in: sets, trackingType: trackingType).filter { kind, value in
            guard let previous = previousBests[kind] else { return false }
            return value > previous + epsilon
        }
    }

    /// Combines best values from many sessions, keeping the maximum of each kind.
    public static func merge(_ bests: [[RecordKind: Double]]) -> [RecordKind: Double] {
        bests.reduce(into: [:]) { result, next in
            result.merge(next) { max($0, $1) }
        }
    }
}
