import Foundation
import SwiftData
import FormCore

/// Workout operations. Every mutating method saves immediately, so an
/// in-progress workout survives the app being suspended or terminated, and
/// is restored on next launch from the `.active` session.
@MainActor
struct WorkoutRepository {
    let context: ModelContext

    enum RepositoryError: LocalizedError {
        case workoutAlreadyActive
        case saveFailed(Error)

        var errorDescription: String? {
            switch self {
            case .workoutAlreadyActive:
                return "A workout is already in progress. Finish or discard it first."
            case .saveFailed(let error):
                return "Couldn't save: \(error.localizedDescription)"
            }
        }
    }

    /// A personal record achieved in a finished workout.
    struct AchievedRecord: Identifiable, Hashable {
        let id = UUID()
        let exerciseName: String
        let kind: RecordKind
        let value: Double
    }

    // MARK: Session lifecycle

    /// The in-progress workout, if any.
    func activeSession() -> WorkoutSession? {
        let active = WorkoutStatus.active.rawValue
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.statusRaw == active },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Starts an empty workout.
    @discardableResult
    func startEmptyWorkout(now: Date = .now) throws -> WorkoutSession {
        guard activeSession() == nil else { throw RepositoryError.workoutAlreadyActive }
        let session = WorkoutSession(name: Self.defaultName(for: now), startedAt: now)
        context.insert(session)
        try save()
        return session
    }

    /// Starts a workout from a routine, creating its planned sets. Weights are
    /// pre-filled from the last completed session of each exercise, never invented.
    @discardableResult
    func startWorkout(from routine: WorkoutRoutine, now: Date = .now) throws -> WorkoutSession {
        guard activeSession() == nil else { throw RepositoryError.workoutAlreadyActive }
        let session = WorkoutSession(name: routine.name, startedAt: now, routineID: routine.id)
        context.insert(session)
        var index = 0
        for entry in routine.orderedExercises {
            guard let exercise = entry.exercise else { continue }
            let previous = previousPerformance(for: exercise.id, excluding: session.id)
            let workoutExercise = insertExercise(exercise, into: session, at: index)
            let workingPrevious = previous.filter { $0.kind == .working }
            for setIndex in 0..<max(1, entry.targetSets) {
                let template = setIndex < workingPrevious.count ? workingPrevious[setIndex] : workingPrevious.last
                insertSet(into: workoutExercise, at: setIndex, kind: .working,
                          weight: template?.weightKilograms,
                          reps: template?.reps ?? entry.targetRepsLower,
                          duration: template?.durationSeconds,
                          distance: template?.distanceMeters)
            }
            index += 1
        }
        try save()
        return session
    }

    func pause(_ session: WorkoutSession, now: Date = .now) throws {
        var clock = session.clock
        clock.pause(at: now)
        session.clock = clock
        if var timer = session.restTimer, timer.isRunning {
            timer.pause(at: now)
            session.restTimer = timer
        }
        touch(session, now: now)
        try save()
    }

    func resume(_ session: WorkoutSession, now: Date = .now) throws {
        var clock = session.clock
        clock.resume(at: now)
        session.clock = clock
        touch(session, now: now)
        try save()
    }

    /// Completes the workout and returns the personal records it set.
    /// Incomplete sets are kept (they don't count towards volume or records).
    @discardableResult
    func finish(_ session: WorkoutSession, now: Date = .now) throws -> [AchievedRecord] {
        var clock = session.clock
        clock.finish(at: now)
        session.clock = clock
        session.status = .completed
        session.restTimer = nil
        touch(session, now: now)
        let records = recordsAchieved(in: session)
        try save()
        return records
    }

    /// Deletes an in-progress workout and everything logged in it.
    func discard(_ session: WorkoutSession) throws {
        context.delete(session)
        try save()
    }

    /// Deletes a completed workout from history. Analytics recompute from what remains.
    func delete(_ session: WorkoutSession) throws {
        context.delete(session)
        try save()
    }

    // MARK: Exercises

    @discardableResult
    func addExercise(_ exercise: Exercise, to session: WorkoutSession) throws -> WorkoutExercise {
        let nextIndex = (session.exercises.map(\.sortIndex).max() ?? -1) + 1
        let workoutExercise = insertExercise(exercise, into: session, at: nextIndex)
        let previous = previousPerformance(for: exercise.id, excluding: session.id).first { $0.kind == .working }
        insertSet(into: workoutExercise, at: 0, kind: .working,
                  weight: previous?.weightKilograms, reps: previous?.reps,
                  duration: previous?.durationSeconds, distance: previous?.distanceMeters)
        touch(session)
        try save()
        return workoutExercise
    }

    func remove(_ workoutExercise: WorkoutExercise) throws {
        let session = workoutExercise.session
        context.delete(workoutExercise)
        if let session { renumber(session.orderedExercises.filter { $0.id != workoutExercise.id }); touch(session) }
        try save()
    }

    /// Moves an exercise up (-1) or down (+1) within its session.
    func move(_ workoutExercise: WorkoutExercise, by offset: Int) throws {
        guard let session = workoutExercise.session else { return }
        var ordered = session.orderedExercises
        guard let index = ordered.firstIndex(where: { $0.id == workoutExercise.id }) else { return }
        let target = index + offset
        guard ordered.indices.contains(target) else { return }
        ordered.swapAt(index, target)
        renumber(ordered)
        touch(session)
        try save()
    }

    func setSkipped(_ workoutExercise: WorkoutExercise, _ skipped: Bool) throws {
        workoutExercise.isSkipped = skipped
        if let session = workoutExercise.session { touch(session) }
        try save()
    }

    // MARK: Sets

    /// Adds a set, copying values from the last set of the same exercise.
    /// Warm-ups are inserted before the first working set.
    @discardableResult
    func addSet(to workoutExercise: WorkoutExercise, kind: SetKind = .working) throws -> WorkoutSet {
        let ordered = workoutExercise.orderedSets
        let template = ordered.last
        let set: WorkoutSet
        if kind == .warmUp {
            let insertAt = ordered.firstIndex { $0.kind != .warmUp } ?? ordered.count
            for existing in ordered[insertAt...] { existing.sortIndex += 1 }
            set = insertSet(into: workoutExercise, at: insertAt, kind: .warmUp,
                            weight: template?.weightKilograms.map { ($0 * 0.5).rounded() },
                            reps: template?.reps, duration: nil, distance: nil)
        } else {
            let weight: Double?
            if kind == .drop, let last = template?.weightKilograms {
                weight = (last * 0.8).rounded()
            } else {
                weight = template?.weightKilograms
            }
            set = insertSet(into: workoutExercise, at: (ordered.map(\.sortIndex).max() ?? -1) + 1, kind: kind,
                            weight: weight, reps: template?.reps,
                            duration: template?.durationSeconds, distance: template?.distanceMeters)
        }
        if let session = workoutExercise.session { touch(session) }
        try save()
        return set
    }

    func remove(_ set: WorkoutSet) throws {
        let parent = set.workoutExercise
        context.delete(set)
        if let parent {
            for (index, remaining) in parent.orderedSets.filter({ $0.id != set.id }).enumerated() {
                remaining.sortIndex = index
            }
            if let session = parent.session { touch(session) }
        }
        try save()
    }

    /// Saves edited values of a set (weight in kilograms).
    func update(_ set: WorkoutSet,
                weightKilograms: Double?? = nil,
                reps: Int?? = nil,
                durationSeconds: Double?? = nil,
                distanceMeters: Double?? = nil,
                kind: SetKind? = nil) throws {
        if let weightKilograms { set.weightKilograms = weightKilograms.map { max(0, $0) } }
        if let reps { set.reps = reps.map { max(0, $0) } }
        if let durationSeconds { set.durationSeconds = durationSeconds.map { max(0, $0) } }
        if let distanceMeters { set.distanceMeters = distanceMeters.map { max(0, $0) } }
        if let kind { set.kind = kind }
        if let session = set.workoutExercise?.session { touch(session) }
        try save()
    }

    /// Toggles completion. When a set becomes complete and `restDuration` is
    /// given, the session's rest timer starts. Returns the new completion state.
    @discardableResult
    func toggleCompletion(of set: WorkoutSet, restDuration: TimeInterval?, now: Date = .now) throws -> Bool {
        set.isCompleted.toggle()
        set.completedAt = set.isCompleted ? now : nil
        if let session = set.workoutExercise?.session {
            if set.isCompleted, let restDuration, session.status == .active, !session.clock.isPaused {
                var timer = session.restTimer ?? RestTimer(duration: restDuration)
                timer.start(duration: restDuration, at: now)
                session.restTimer = timer
            }
            touch(session, now: now)
        }
        try save()
        return set.isCompleted
    }

    // MARK: Rest timer

    func updateRestTimer(of session: WorkoutSession, _ change: (inout RestTimer) -> Void, defaultDuration: TimeInterval) throws {
        var timer = session.restTimer ?? RestTimer(duration: defaultDuration)
        change(&timer)
        session.restTimer = timer
        try save()
    }

    // MARK: History and records

    /// Sets from the most recent completed session containing this exercise.
    func previousPerformance(for exerciseID: UUID, excluding sessionID: UUID? = nil) -> [SetPerformance] {
        completedHistory(for: exerciseID, excluding: sessionID).first?.performances ?? []
    }

    /// Completed occurrences of an exercise, newest first.
    func completedHistory(for exerciseID: UUID, excluding sessionID: UUID? = nil) -> [WorkoutExercise] {
        let id: UUID? = exerciseID
        let descriptor = FetchDescriptor<WorkoutExercise>(predicate: #Predicate<WorkoutExercise> { $0.exerciseID == id })
        let all = (try? context.fetch(descriptor)) ?? []
        return all
            .filter { $0.session?.status == .completed && $0.session?.id != sessionID && !$0.isSkipped }
            .sorted { ($0.session?.startedAt ?? .distantPast) > ($1.session?.startedAt ?? .distantPast) }
    }

    /// Best values per record kind for an exercise across completed sessions,
    /// optionally excluding one session.
    func personalBests(for exerciseID: UUID, trackingType: ExerciseTrackingType, excluding sessionID: UUID? = nil) -> [RecordKind: Double] {
        let history = completedHistory(for: exerciseID, excluding: sessionID).filter { $0.trackingType == trackingType }
        return PersonalRecordCalculator.merge(history.map {
            PersonalRecordCalculator.bests(in: $0.performances, trackingType: trackingType)
        })
    }

    /// Records in `session` that beat every earlier completed session.
    func recordsAchieved(in session: WorkoutSession) -> [AchievedRecord] {
        var records: [AchievedRecord] = []
        for workoutExercise in session.orderedExercises where !workoutExercise.isSkipped {
            guard let exerciseID = workoutExercise.exerciseID else { continue }
            let earlier = completedHistory(for: exerciseID, excluding: session.id)
                .filter { ($0.session?.startedAt ?? .distantFuture) < session.startedAt && $0.trackingType == workoutExercise.trackingType }
            let previousBests = PersonalRecordCalculator.merge(earlier.map {
                PersonalRecordCalculator.bests(in: $0.performances, trackingType: workoutExercise.trackingType)
            })
            let new = PersonalRecordCalculator.newRecords(current: workoutExercise.performances,
                                                          previousBests: previousBests,
                                                          trackingType: workoutExercise.trackingType)
            for kind in workoutExercise.trackingType.recordKinds {
                if let value = new[kind] {
                    records.append(AchievedRecord(exerciseName: workoutExercise.exerciseName, kind: kind, value: value))
                }
            }
        }
        return records
    }

    // MARK: Helpers

    @discardableResult
    private func insertExercise(_ exercise: Exercise, into session: WorkoutSession, at index: Int) -> WorkoutExercise {
        let workoutExercise = WorkoutExercise(exercise: exercise, sortIndex: index)
        context.insert(workoutExercise)
        workoutExercise.session = session
        workoutExercise.exercise = exercise
        return workoutExercise
    }

    @discardableResult
    private func insertSet(into workoutExercise: WorkoutExercise, at index: Int, kind: SetKind,
                           weight: Double?, reps: Int?, duration: Double?, distance: Double?) -> WorkoutSet {
        let set = WorkoutSet(sortIndex: index, kind: kind, weightKilograms: weight, reps: reps,
                             durationSeconds: duration, distanceMeters: distance)
        context.insert(set)
        set.workoutExercise = workoutExercise
        return set
    }

    private func renumber(_ exercises: [WorkoutExercise]) {
        for (index, exercise) in exercises.enumerated() { exercise.sortIndex = index }
    }

    private func touch(_ session: WorkoutSession, now: Date = .now) {
        session.updatedAt = now
    }

    private func save() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw RepositoryError.saveFailed(error)
        }
    }

    static func defaultName(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: return "Morning workout"
        case 12..<17: return "Afternoon workout"
        default: return "Evening workout"
        }
    }
}
