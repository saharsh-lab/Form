import XCTest
@testable import FormCore

final class RestTimerTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func testRemainingIsComputedFromDatesNotTicks() {
        var timer = RestTimer(duration: 90)
        timer.start(at: t0)
        // Simulates the app being suspended for 60 s: no ticks happen, the answer is still right.
        XCTAssertEqual(timer.remaining(at: t0.addingTimeInterval(60)), 30, accuracy: 1e-9)
        XCTAssertEqual(timer.remaining(at: t0.addingTimeInterval(500)), 0)
    }

    func testPauseAndResume() {
        var timer = RestTimer(duration: 60)
        timer.start(at: t0)
        timer.pause(at: t0.addingTimeInterval(20))
        XCTAssertTrue(timer.isPaused)
        XCTAssertEqual(timer.remaining(at: t0.addingTimeInterval(1_000)), 40, accuracy: 1e-9)
        timer.resume(at: t0.addingTimeInterval(100))
        XCTAssertEqual(timer.endDate, t0.addingTimeInterval(140))
    }

    func testRefreshFinishesOnlyOnce() {
        var timer = RestTimer(duration: 30)
        timer.start(at: t0)
        XCTAssertFalse(timer.refresh(at: t0.addingTimeInterval(10)))
        XCTAssertTrue(timer.refresh(at: t0.addingTimeInterval(31)))
        XCTAssertEqual(timer.phase, .finished)
        XCTAssertFalse(timer.refresh(at: t0.addingTimeInterval(40)))
    }

    func testAdjustWhileRunningAndIdle() {
        var timer = RestTimer(duration: 60)
        timer.adjust(by: 30, at: t0)
        XCTAssertEqual(timer.duration, 90)
        timer.start(at: t0)
        timer.adjust(by: -15, at: t0.addingTimeInterval(10))
        XCTAssertEqual(timer.remaining(at: t0.addingTimeInterval(10)), 65, accuracy: 1e-9)
        timer.adjust(by: -500, at: t0.addingTimeInterval(10))
        XCTAssertEqual(timer.phase, .finished)
    }

    func testSkipAndReset() {
        var timer = RestTimer(duration: 60)
        timer.start(at: t0)
        timer.skip()
        XCTAssertEqual(timer.phase, .idle)
        XCTAssertEqual(timer.remaining(at: t0), 60)
        timer.start(at: t0)
        timer.reset()
        XCTAssertFalse(timer.isActive)
    }

    func testDurationIsClamped() {
        XCTAssertEqual(RestTimer(duration: 0).duration, 5)
        XCTAssertEqual(RestTimer(duration: 99_999).duration, 3_600)
        XCTAssertEqual(RestTimer(duration: .nan).duration, 90)
    }

    func testCodableRoundTripPreservesRunningState() throws {
        var timer = RestTimer(duration: 120)
        timer.start(at: t0)
        let decoded = try JSONDecoder().decode(RestTimer.self, from: JSONEncoder().encode(timer))
        XCTAssertEqual(decoded, timer)
        XCTAssertEqual(decoded.remaining(at: t0.addingTimeInterval(20)), 100, accuracy: 1e-9)
    }
}

final class WorkoutClockTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 2_000_000)

    func testElapsedExcludesPauses() {
        var clock = WorkoutClock(startedAt: t0)
        clock.pause(at: t0.addingTimeInterval(600))
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(5_000)), 600)
        clock.resume(at: t0.addingTimeInterval(900))
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(1_200)), 900)
        clock.finish(at: t0.addingTimeInterval(1_500))
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(99_999)), 1_200)
    }

    func testFinishingWhilePausedUsesPauseTime() {
        var clock = WorkoutClock(startedAt: t0)
        clock.pause(at: t0.addingTimeInterval(300))
        clock.finish(at: t0.addingTimeInterval(3_000))
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(3_000)), 300)
    }

    func testRestoredClockMatchesOriginal() throws {
        var clock = WorkoutClock(startedAt: t0)
        clock.pause(at: t0.addingTimeInterval(100))
        clock.resume(at: t0.addingTimeInterval(160))
        let restored = try JSONDecoder().decode(WorkoutClock.self, from: JSONEncoder().encode(clock))
        XCTAssertEqual(restored.elapsed(at: t0.addingTimeInterval(400)), 340)
    }
}

final class ValidationTests: XCTestCase {

    private let us = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")

    func testNames() {
        XCTAssertEqual(InputValidator.name("  Oats  "), .success("Oats"))
        XCTAssertEqual(InputValidator.name("   "), .failure(.empty))
        XCTAssertEqual(InputValidator.name(String(repeating: "a", count: 81)), .failure(.tooLong(maximum: 80)))
    }

    func testOptionalDecimalKeepsEmptyUnspecified() {
        XCTAssertEqual(InputValidator.optionalDecimal("", in: 0...1_000, locale: us), .success(nil))
        XCTAssertEqual(InputValidator.optionalDecimal("12.5", in: 0...1_000, locale: us), .success(12.5))
        XCTAssertEqual(InputValidator.optionalDecimal("12,5", in: 0...1_000, locale: german), .success(12.5))
        XCTAssertEqual(InputValidator.optionalDecimal("-3", in: 0...1_000, locale: us), .failure(.notANumber))
        XCTAssertEqual(InputValidator.optionalDecimal("12abc", in: 0...1_000, locale: us), .failure(.notANumber))
        XCTAssertEqual(InputValidator.optionalDecimal("2000", in: 0...1_000, locale: us), .failure(.outOfRange(minimum: 0, maximum: 1_000)))
    }

    func testRequiredValues() {
        XCTAssertEqual(InputValidator.requiredDecimal("", in: 0...10, locale: us), .failure(.empty))
        XCTAssertEqual(InputValidator.requiredInteger("8", in: 0...100, locale: us), .success(8))
        XCTAssertEqual(InputValidator.requiredInteger("8.5", in: 0...100, locale: us), .failure(.notAWholeNumber))
    }

    func testFutureDatesAreRejected() {
        let now = Date()
        XCTAssertEqual(InputValidator.pastOrPresent(now, now: now), .success(now))
        let nextWeek = now.addingTimeInterval(7 * 86_400)
        XCTAssertEqual(InputValidator.pastOrPresent(nextWeek, now: now), .failure(.dateInFuture))
    }

    func testDurationText() {
        XCTAssertEqual(DurationText.clock(45), "0:45")
        XCTAssertEqual(DurationText.clock(725), "12:05")
        XCTAssertEqual(DurationText.clock(3_729), "1:02:09")
        XCTAssertEqual(DurationText.summary(30), "< 1 min")
        XCTAssertEqual(DurationText.summary(3_900), "1 h 5 min")
        XCTAssertEqual(DurationText.summary(3_600), "1 h")
    }
}
