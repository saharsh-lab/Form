import XCTest
import SwiftData
import FormCore
@testable import FormApp

@MainActor
final class WorkoutRepositoryTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var repository: WorkoutRepository!
    private let t0 = Date(timeIntervalSinceReferenceDate: 790_000_000)

    override func setUp() async throws {
        container = try PersistenceController.makeContainer(location: .inMemory)
        context = ModelContext(container)
        repository = WorkoutRepository(context: context)
    }

    private func makeSquat() throws -> Exercise {
        let squat = Exercise(name: "Back Squat", muscleGroup: .quadriceps, equipment: .barbell)
        context.insert(squat)
        try context.save()
        return squat
    }

    /// Logs a completed workout with the given working sets (kg, reps).
    @discardableResult
    private func logWorkout(_ exercise: Exercise, sets: [(Double, Int)], at start: Date) throws -> (WorkoutSession, [WorkoutRepository.AchievedRecord]) {
        let session = try repository.startEmptyWorkout(now: start)
        let workoutExercise = try repository.addExercise(exercise, to: session)
        for (index, values) in sets.enumerated() {
            let set = try index == 0 ? workoutExercise.orderedSets[0] : repository.addSet(to: workoutExercise)
            try repository.update(set, weightKilograms: .some(values.0), reps: .some(values.1))
            try repository.toggleCompletion(of: set, restDuration: nil, now: start.addingTimeInterval(Double(index) * 60))
        }
        let records = try repository.finish(session, now: start.addingTimeInterval(3_600))
        return (session, records)
    }

    func testOnlyOneActiveWorkoutAtATime() throws {
        try repository.startEmptyWorkout(now: t0)
        XCTAssertThrowsError(try repository.startEmptyWorkout(now: t0))
    }

    func testActiveWorkoutIsRestoredFromANewContext() throws {
        let squat = try makeSquat()
        let session = try repository.startEmptyWorkout(now: t0)
        let workoutExercise = try repository.addExercise(squat, to: session)
        let set = workoutExercise.orderedSets[0]
        try repository.update(set, weightKilograms: .some(100), reps: .some(5))
        try repository.toggleCompletion(of: set, restDuration: 120, now: t0.addingTimeInterval(300))

        // A fresh context simulates relaunching the app.
        let relaunched = WorkoutRepository(context: ModelContext(container))
        let restored = try XCTUnwrap(relaunched.activeSession())
        XCTAssertEqual(restored.id, session.id)
        XCTAssertEqual(restored.orderedExercises.first?.orderedSets.first?.weightKilograms, 100)
        XCTAssertEqual(restored.orderedExercises.first?.orderedSets.first?.isCompleted, true)
        XCTAssertEqual(restored.restTimer?.remaining(at: t0.addingTimeInterval(360)) ?? -1, 60, accuracy: 1e-6)
    }

    func testCompletingASetStartsTheRestTimerUnlessPaused() throws {
        let squat = try makeSquat()
        let session = try repository.startEmptyWorkout(now: t0)
        let workoutExercise = try repository.addExercise(squat, to: session)
        try repository.toggleCompletion(of: workoutExercise.orderedSets[0], restDuration: 90, now: t0)
        XCTAssertTrue(session.restTimer?.isRunning ?? false)

        try repository.pause(session, now: t0.addingTimeInterval(10))
        XCTAssertTrue(session.clock.isPaused)
        XCTAssertTrue(session.restTimer?.isPaused ?? false, "pausing the workout pauses the rest")

        let second = try repository.addSet(to: workoutExercise)
        session.restTimer = nil
        try repository.toggleCompletion(of: second, restDuration: 90, now: t0.addingTimeInterval(20))
        XCTAssertNil(session.restTimer, "no rest timer while paused")
    }

    func testPauseIsExcludedFromDuration() throws {
        let session = try repository.startEmptyWorkout(now: t0)
        try repository.pause(session, now: t0.addingTimeInterval(600))
        try repository.resume(session, now: t0.addingTimeInterval(900))
        try repository.finish(session, now: t0.addingTimeInterval(1_800))
        XCTAssertEqual(session.clock.elapsed(at: t0.addingTimeInterval(99_999)), 1_500, accuracy: 1e-6)
        XCTAssertEqual(session.status, .completed)
        XCTAssertNil(repository.activeSession())
    }

    func testVolumeAndSetCountsIgnoreWarmUpsAndIncompleteSets() throws {
        let squat = try makeSquat()
        let session = try repository.startEmptyWorkout(now: t0)
        let workoutExercise = try repository.addExercise(squat, to: session)
        let working = workoutExercise.orderedSets[0]
        try repository.update(working, weightKilograms: .some(100), reps: .some(5))
        try repository.toggleCompletion(of: working, restDuration: nil)
        let warmUp = try repository.addSet(to: workoutExercise, kind: .warmUp)
        try repository.toggleCompletion(of: warmUp, restDuration: nil)
        _ = try repository.addSet(to: workoutExercise) // left incomplete

        XCTAssertEqual(workoutExercise.orderedSets.first?.kind, .warmUp, "warm-ups go before working sets")
        XCTAssertEqual(session.totalVolumeKilograms, 500, accuracy: 1e-9)
        XCTAssertEqual(session.completedSetCount, 1)
    }

    func testPersonalRecordsNeedAnEarlierBaselineAndAStrictImprovement() throws {
        let squat = try makeSquat()
        let (_, first) = try logWorkout(squat, sets: [(100, 5)], at: t0)
        XCTAssertTrue(first.isEmpty, "first session is a baseline")

        let (_, same) = try logWorkout(squat, sets: [(100, 5)], at: t0.addingTimeInterval(86_400))
        XCTAssertTrue(same.isEmpty, "equalling a best is not a record")

        let (_, better) = try logWorkout(squat, sets: [(105, 5)], at: t0.addingTimeInterval(2 * 86_400))
        XCTAssertEqual(Set(better.map(\.kind)), [.heaviestWeight, .bestEstimatedOneRepMax, .bestSetVolume])
    }

    func testPreviousPerformanceComesFromLastCompletedSession() throws {
        let squat = try makeSquat()
        try logWorkout(squat, sets: [(90, 5)], at: t0)
        try logWorkout(squat, sets: [(95, 5), (95, 4)], at: t0.addingTimeInterval(86_400))

        let previous = repository.previousPerformance(for: squat.id)
        XCTAssertEqual(previous.map(\.weightKilograms), [95, 95])

        // A new session pre-fills from it, but never counts itself.
        let session = try repository.startEmptyWorkout(now: t0.addingTimeInterval(2 * 86_400))
        let workoutExercise = try repository.addExercise(squat, to: session)
        XCTAssertEqual(workoutExercise.orderedSets.first?.weightKilograms, 95)
        XCTAssertFalse(workoutExercise.orderedSets.first?.isCompleted ?? true)
    }

    func testStartingFromRoutineCreatesPlannedSets() throws {
        let squat = try makeSquat()
        let routine = WorkoutRoutine(name: "Legs")
        context.insert(routine)
        let entry = RoutineExercise(sortIndex: 0, targetSets: 3, targetRepsLower: 5, targetRepsUpper: 8)
        context.insert(entry)
        entry.routine = routine
        entry.exercise = squat
        try context.save()

        let session = try repository.startWorkout(from: routine, now: t0)
        XCTAssertEqual(session.name, "Legs")
        XCTAssertEqual(session.routineID, routine.id)
        let sets = try XCTUnwrap(session.orderedExercises.first).orderedSets
        XCTAssertEqual(sets.count, 3)
        XCTAssertEqual(sets.map(\.reps), [5, 5, 5])
        XCTAssertTrue(sets.allSatisfy { $0.weightKilograms == nil }, "no invented weights without history")
    }

    func testReorderSkipAndRemoveExercises() throws {
        let squat = try makeSquat()
        let bench = Exercise(name: "Bench", muscleGroup: .chest, equipment: .barbell)
        context.insert(bench)
        let session = try repository.startEmptyWorkout(now: t0)
        let first = try repository.addExercise(squat, to: session)
        let second = try repository.addExercise(bench, to: session)

        try repository.move(second, by: -1)
        XCTAssertEqual(session.orderedExercises.map(\.exerciseName), ["Bench", "Back Squat"])

        try repository.setSkipped(first, true)
        XCTAssertTrue(first.isSkipped)

        try repository.remove(second)
        XCTAssertEqual(session.orderedExercises.map(\.exerciseName), ["Back Squat"])
        XCTAssertEqual(session.orderedExercises.first?.sortIndex, 0)
    }

    func testDiscardDeletesEverything() throws {
        let squat = try makeSquat()
        let session = try repository.startEmptyWorkout(now: t0)
        try repository.addExercise(squat, to: session)
        try repository.discard(session)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSet>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 1)
    }

    func testEditingHistoryRecalculatesRecords() throws {
        let squat = try makeSquat()
        let (old, _) = try logWorkout(squat, sets: [(120, 3)], at: t0)
        try logWorkout(squat, sets: [(110, 5)], at: t0.addingTimeInterval(86_400))
        XCTAssertEqual(repository.personalBests(for: squat.id, trackingType: .weightAndReps)[.heaviestWeight], 120)

        // Correct a typo in the old session: it was really 102 kg.
        let set = try XCTUnwrap(old.orderedExercises.first?.orderedSets.first)
        try repository.update(set, weightKilograms: .some(102))
        XCTAssertEqual(repository.personalBests(for: squat.id, trackingType: .weightAndReps)[.heaviestWeight], 110)

        try repository.delete(old)
        XCTAssertEqual(repository.completedHistory(for: squat.id).count, 1)
    }
}
