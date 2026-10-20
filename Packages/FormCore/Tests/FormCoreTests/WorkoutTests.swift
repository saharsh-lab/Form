import XCTest
@testable import FormCore

final class WorkoutCalculatorTests: XCTestCase {

    func testVolumeCountsOnlyCompletedLoadedWorkSets() {
        let sets = [
            SetPerformance(kind: .warmUp, weightKilograms: 40, reps: 10),
            SetPerformance(kind: .working, weightKilograms: 100, reps: 5),
            SetPerformance(kind: .working, weightKilograms: 100, reps: 5),
            SetPerformance(kind: .working, weightKilograms: 100, reps: 5, isCompleted: false),
            SetPerformance(kind: .drop, weightKilograms: 70, reps: 8),
            SetPerformance(kind: .working, weightKilograms: nil, reps: 12)
        ]
        XCTAssertEqual(WorkoutCalculator.volume(of: sets, trackingType: .weightAndReps), 1_560, accuracy: 1e-9)
        XCTAssertEqual(WorkoutCalculator.completedSetCount(sets), 4)
        XCTAssertEqual(WorkoutCalculator.completedSetCount(sets, includeWarmUps: true), 5)
    }

    func testVolumeIsZeroForNonLoadedTrackingTypes() {
        let sets = [SetPerformance(weightKilograms: 20, reps: 10)]
        XCTAssertEqual(WorkoutCalculator.volume(of: sets, trackingType: .repsOnly), 0)
        XCTAssertEqual(WorkoutCalculator.volume(of: sets, trackingType: .duration), 0)
    }

    func testEstimatedOneRepMax() {
        XCTAssertEqual(WorkoutCalculator.estimatedOneRepMax(weightKilograms: 100, reps: 1), 100)
        XCTAssertEqual(WorkoutCalculator.estimatedOneRepMax(weightKilograms: 100, reps: 5)!, 116.666_666, accuracy: 1e-5)
        XCTAssertNil(WorkoutCalculator.estimatedOneRepMax(weightKilograms: 100, reps: 13))
        XCTAssertNil(WorkoutCalculator.estimatedOneRepMax(weightKilograms: 0, reps: 5))
    }
}

final class PersonalRecordTests: XCTestCase {

    func testBestsForWeightAndReps() {
        let sets = [
            SetPerformance(kind: .warmUp, weightKilograms: 140, reps: 1),
            SetPerformance(kind: .working, weightKilograms: 100, reps: 8),
            SetPerformance(kind: .working, weightKilograms: 110, reps: 3)
        ]
        let bests = PersonalRecordCalculator.bests(in: sets, trackingType: .weightAndReps)
        XCTAssertEqual(bests[.heaviestWeight], 110, "warm-ups never count as records")
        XCTAssertEqual(bests[.bestSetVolume], 800)
        XCTAssertEqual(bests[.bestEstimatedOneRepMax]!, 126.666_666, accuracy: 1e-5)
        XCTAssertNil(bests[.mostReps])
    }

    func testNewRecordsRequireAPreviousBestAndAStrictImprovement() {
        let sets = [SetPerformance(weightKilograms: 105, reps: 5)]
        let previous: [RecordKind: Double] = [.heaviestWeight: 100, .bestSetVolume: 600, .bestEstimatedOneRepMax: 130]
        let records = PersonalRecordCalculator.newRecords(current: sets, previousBests: previous, trackingType: .weightAndReps)
        XCTAssertEqual(records, [.heaviestWeight: 105])
    }

    func testFirstSessionIsABaselineNotARecord() {
        let sets = [SetPerformance(weightKilograms: 60, reps: 10)]
        XCTAssertTrue(PersonalRecordCalculator.newRecords(current: sets, previousBests: [:], trackingType: .weightAndReps).isEmpty)
    }

    func testEqualPerformanceIsNotARecord() {
        let sets = [SetPerformance(weightKilograms: 100, reps: 5)]
        let previous = PersonalRecordCalculator.bests(in: sets, trackingType: .weightAndReps)
        XCTAssertTrue(PersonalRecordCalculator.newRecords(current: sets, previousBests: previous, trackingType: .weightAndReps).isEmpty)
    }

    func testIncompatibleTrackingTypesAreNotCompared() {
        let plank = [SetPerformance(durationSeconds: 90)]
        let bests = PersonalRecordCalculator.bests(in: plank, trackingType: .duration)
        XCTAssertEqual(bests, [.longestDuration: 90])
        // Duration bests never produce weight records and vice versa.
        let weightRecords = PersonalRecordCalculator.newRecords(current: [SetPerformance(weightKilograms: 50, reps: 5)],
                                                                previousBests: bests,
                                                                trackingType: .weightAndReps)
        XCTAssertTrue(weightRecords.isEmpty)
    }

    func testRepsOnlyAndDistance() {
        XCTAssertEqual(PersonalRecordCalculator.bests(in: [SetPerformance(reps: 12), SetPerformance(reps: 15)], trackingType: .repsOnly),
                       [.mostReps: 15])
        let row = [SetPerformance(durationSeconds: 600, distanceMeters: 2_000)]
        XCTAssertEqual(PersonalRecordCalculator.bests(in: row, trackingType: .distanceAndDuration),
                       [.longestDistance: 2_000, .longestDuration: 600])
    }

    func testMergeKeepsMaximums() {
        let merged = PersonalRecordCalculator.merge([[.heaviestWeight: 100, .bestSetVolume: 900], [.heaviestWeight: 110]])
        XCTAssertEqual(merged, [.heaviestWeight: 110, .bestSetVolume: 900])
    }
}

final class UnitConversionTests: XCTestCase {

    func testWeightRoundTrip() {
        XCTAssertEqual(WeightUnit.pounds.fromKilograms(100), 220.462_262_18, accuracy: 1e-6)
        XCTAssertEqual(WeightUnit.pounds.toKilograms(WeightUnit.pounds.fromKilograms(72.5)), 72.5, accuracy: 1e-9)
        XCTAssertEqual(WeightUnit.kilograms.toKilograms(80), 80)
    }

    func testLengthAndDistance() {
        XCTAssertEqual(LengthUnit.inches.toCentimeters(10), 25.4, accuracy: 1e-9)
        XCTAssertEqual(DistanceUnit.miles.fromMeters(1_609.344), 1, accuracy: 1e-9)
        XCTAssertEqual(DistanceUnit.kilometers.toMeters(5), 5_000)
    }
}
