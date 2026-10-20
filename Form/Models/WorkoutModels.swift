import Foundation
import SwiftData
import FormCore

/// An exercise in the user's local, editable catalogue.
///
/// Exercises that appear in workout history should be archived rather than
/// deleted; if one is deleted anyway, history keeps its name and tracking type
/// through the snapshot stored on `WorkoutExercise`.
@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    var name: String
    var muscleGroupRaw: String
    var equipmentRaw: String
    var trackingTypeRaw: String
    var isCustom: Bool
    var isArchived: Bool
    var notes: String
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \RoutineExercise.exercise)
    var routineEntries: [RoutineExercise] = []

    @Relationship(deleteRule: .nullify, inverse: \WorkoutExercise.exercise)
    var workoutEntries: [WorkoutExercise] = []

    init(id: UUID = UUID(),
         name: String,
         muscleGroup: MuscleGroup,
         equipment: Equipment,
         trackingType: ExerciseTrackingType = .weightAndReps,
         isCustom: Bool = false,
         notes: String = "",
         createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.muscleGroupRaw = muscleGroup.rawValue
        self.equipmentRaw = equipment.rawValue
        self.trackingTypeRaw = trackingType.rawValue
        self.isCustom = isCustom
        self.isArchived = false
        self.notes = notes
        self.createdAt = createdAt
    }

    var muscleGroup: MuscleGroup {
        get { MuscleGroup(rawValue: muscleGroupRaw) ?? .other }
        set { muscleGroupRaw = newValue.rawValue }
    }

    var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .other }
        set { equipmentRaw = newValue.rawValue }
    }

    var trackingType: ExerciseTrackingType {
        get { ExerciseTrackingType(rawValue: trackingTypeRaw) ?? .weightAndReps }
        set { trackingTypeRaw = newValue.rawValue }
    }
}

/// A reusable workout template.
@Model
final class WorkoutRoutine {
    @Attribute(.unique) var id: UUID
    var name: String
    var notes: String
    /// Position in the routine list.
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \RoutineExercise.routine)
    var exercises: [RoutineExercise] = []

    init(id: UUID = UUID(), name: String, notes: String = "", sortIndex: Int = 0, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.notes = notes
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    /// SwiftData relationships are unordered; this applies the stored order.
    var orderedExercises: [RoutineExercise] {
        exercises.sorted { $0.sortIndex < $1.sortIndex }
    }
}

/// One exercise slot within a routine, with its planned sets.
@Model
final class RoutineExercise {
    @Attribute(.unique) var id: UUID
    var sortIndex: Int
    var targetSets: Int
    var targetRepsLower: Int?
    var targetRepsUpper: Int?
    /// Overrides the default rest duration for this exercise, in seconds.
    var restSeconds: Int?
    var notes: String

    var routine: WorkoutRoutine?
    var exercise: Exercise?

    /// Insert the instance into a context before linking `routine` and `exercise`.
    init(id: UUID = UUID(),
         sortIndex: Int,
         targetSets: Int = 3,
         targetRepsLower: Int? = nil,
         targetRepsUpper: Int? = nil,
         restSeconds: Int? = nil,
         notes: String = "") {
        self.id = id
        self.sortIndex = sortIndex
        self.targetSets = targetSets
        self.targetRepsLower = targetRepsLower
        self.targetRepsUpper = targetRepsUpper
        self.restSeconds = restSeconds
        self.notes = notes
    }

    /// "8–12 reps", "5 reps", or nil when no target is set.
    var repTargetText: String? {
        switch (targetRepsLower, targetRepsUpper) {
        case let (lower?, upper?) where lower != upper: return "\(lower)–\(upper) reps"
        case let (lower?, _): return "\(lower) reps"
        case let (nil, upper?): return "\(upper) reps"
        default: return nil
        }
    }
}

/// A workout: active (in progress, restored after relaunch), completed, or discarded.
@Model
final class WorkoutSession {
    @Attribute(.unique) var id: UUID
    var name: String
    var statusRaw: String
    var startedAt: Date
    var endedAt: Date?
    /// Set while the workout is paused.
    var pausedAt: Date?
    /// Total paused time, excluded from duration.
    var accumulatedPauseSeconds: Double
    var notes: String
    /// The routine this session was started from, if any. Stored as an ID so
    /// deleting a routine never deletes history.
    var routineID: UUID?
    /// Encoded `RestTimer`, persisted so a running rest survives relaunch.
    var restTimerData: Data?
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.session)
    var exercises: [WorkoutExercise] = []

    init(id: UUID = UUID(), name: String, startedAt: Date = .now, routineID: UUID? = nil) {
        self.id = id
        self.name = name
        self.statusRaw = WorkoutStatus.active.rawValue
        self.startedAt = startedAt
        self.endedAt = nil
        self.pausedAt = nil
        self.accumulatedPauseSeconds = 0
        self.notes = ""
        self.routineID = routineID
        self.restTimerData = nil
        self.updatedAt = startedAt
    }

    var status: WorkoutStatus {
        get { WorkoutStatus(rawValue: statusRaw) ?? .completed }
        set { statusRaw = newValue.rawValue }
    }

    var orderedExercises: [WorkoutExercise] {
        exercises.sorted { $0.sortIndex < $1.sortIndex }
    }

    var clock: WorkoutClock {
        get { WorkoutClock(startedAt: startedAt, pausedAt: pausedAt, accumulatedPause: accumulatedPauseSeconds, endedAt: endedAt) }
        set {
            startedAt = newValue.startedAt
            pausedAt = newValue.pausedAt
            accumulatedPauseSeconds = newValue.accumulatedPause
            endedAt = newValue.endedAt
        }
    }

    var restTimer: RestTimer? {
        get { restTimerData.flatMap { try? JSONDecoder().decode(RestTimer.self, from: $0) } }
        set { restTimerData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// Total weight × reps volume in kilograms across loaded exercises.
    var totalVolumeKilograms: Double {
        exercises.reduce(0) { $0 + $1.volumeKilograms }
    }

    var completedSetCount: Int {
        exercises.reduce(0) { $0 + WorkoutCalculator.completedSetCount($1.performances) }
    }
}

/// An exercise performed within a session. Keeps a snapshot of the exercise's
/// name and tracking type so history survives catalogue edits and deletions.
@Model
final class WorkoutExercise {
    @Attribute(.unique) var id: UUID
    var sortIndex: Int
    var exerciseID: UUID?
    var exerciseName: String
    var trackingTypeRaw: String
    var isSkipped: Bool
    var notes: String

    var session: WorkoutSession?
    var exercise: Exercise?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.workoutExercise)
    var sets: [WorkoutSet] = []

    /// Copies the exercise's name and tracking type. Insert the instance into a
    /// context before linking `session` and `exercise`.
    init(id: UUID = UUID(), exercise: Exercise, sortIndex: Int) {
        self.id = id
        self.sortIndex = sortIndex
        self.exerciseID = exercise.id
        self.exerciseName = exercise.name
        self.trackingTypeRaw = exercise.trackingTypeRaw
        self.isSkipped = false
        self.notes = ""
    }

    var trackingType: ExerciseTrackingType {
        ExerciseTrackingType(rawValue: trackingTypeRaw) ?? .weightAndReps
    }

    var orderedSets: [WorkoutSet] {
        sets.sorted { $0.sortIndex < $1.sortIndex }
    }

    var performances: [SetPerformance] {
        orderedSets.map(\.performance)
    }

    var volumeKilograms: Double {
        WorkoutCalculator.volume(of: performances, trackingType: trackingType)
    }
}

/// One logged set. Weight is always stored in kilograms.
@Model
final class WorkoutSet {
    @Attribute(.unique) var id: UUID
    var sortIndex: Int
    var kindRaw: String
    var weightKilograms: Double?
    var reps: Int?
    var durationSeconds: Double?
    var distanceMeters: Double?
    var isCompleted: Bool
    var completedAt: Date?

    var workoutExercise: WorkoutExercise?

    init(id: UUID = UUID(),
         sortIndex: Int,
         kind: SetKind = .working,
         weightKilograms: Double? = nil,
         reps: Int? = nil,
         durationSeconds: Double? = nil,
         distanceMeters: Double? = nil) {
        self.id = id
        self.sortIndex = sortIndex
        self.kindRaw = kind.rawValue
        self.weightKilograms = weightKilograms
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.isCompleted = false
        self.completedAt = nil
    }

    var kind: SetKind {
        get { SetKind(rawValue: kindRaw) ?? .working }
        set { kindRaw = newValue.rawValue }
    }

    var performance: SetPerformance {
        SetPerformance(kind: kind,
                       weightKilograms: weightKilograms,
                       reps: reps,
                       durationSeconds: durationSeconds,
                       distanceMeters: distanceMeters,
                       isCompleted: isCompleted)
    }
}
