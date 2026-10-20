import XCTest
@testable import FormCore

final class WidgetSnapshotTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    private let monday = Date(timeIntervalSince1970: 1_773_619_200) // 2026-03-16 00:00 UTC, a Monday

    private func makeSnapshot(at date: Date) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: date,
            weightUnit: .pounds,
            nutrition: .init(day: calendar.startOfDay(for: date),
                             consumed: NutritionValues(calories: 1_200, protein: nil),
                             targets: NutritionValues(calories: 2_000, protein: 140),
                             entryCount: 3, entriesMissingCalories: 1),
            training: .init(active: .init(name: "Legs", clock: WorkoutClock(startedAt: date), completedSets: 4,
                                          restTimer: RestTimer(duration: 90)),
                            lastWorkoutName: "Push", lastWorkoutDate: date, workoutsThisWeek: 2, weeklyStreak: 3),
            latestBodyWeight: .init(kilograms: 80, date: date)
        )
    }

    func testRoundTripThroughFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let snapshot = makeSnapshot(at: monday.addingTimeInterval(36_000))
        try WidgetSnapshotStore.write(snapshot, to: url)
        let read = try XCTUnwrap(WidgetSnapshotStore.read(from: url))
        XCTAssertEqual(read, snapshot)
        XCTAssertNil(read.nutrition.consumed.protein, "missing values stay missing, not zero")
    }

    func testMissingOrIncompatibleFileReadsAsNil() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(WidgetSnapshotStore.read(from: url))
        try Data("{\"version\": 99}".utf8).write(to: url)
        XCTAssertNil(WidgetSnapshotStore.read(from: url))
    }

    func testStaleNutritionResetsConsumedButKeepsTargets() {
        let snapshot = makeSnapshot(at: monday.addingTimeInterval(36_000))
        let sameDay = snapshot.nutrition(on: monday.addingTimeInterval(80_000), calendar: calendar)
        XCTAssertEqual(sameDay.consumed.calories, 1_200)

        let nextDay = snapshot.nutrition(on: monday.addingTimeInterval(90_000), calendar: calendar)
        XCTAssertNil(nextDay.consumed.calories)
        XCTAssertEqual(nextDay.entryCount, 0)
        XCTAssertEqual(nextDay.targets.calories, 2_000)
        XCTAssertEqual(nextDay.progress(for: .calories).remaining, 2_000)
    }

    func testWorkoutsThisWeekResetInANewWeek() {
        let snapshot = makeSnapshot(at: monday.addingTimeInterval(36_000))
        XCTAssertEqual(snapshot.workoutsThisWeek(on: monday.addingTimeInterval(5 * 86_400), calendar: calendar), 2)
        XCTAssertEqual(snapshot.workoutsThisWeek(on: monday.addingTimeInterval(7 * 86_400), calendar: calendar), 0)
    }
}
