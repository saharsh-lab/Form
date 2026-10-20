import XCTest
@testable import FormCore

final class CSVTests: XCTestCase {

    func testEscapingQuotesCommasNewlinesAndFormulas() {
        XCTAssertEqual(CSVTable.escape("Oats"), "Oats")
        XCTAssertEqual(CSVTable.escape("Rice, cooked"), "\"Rice, cooked\"")
        XCTAssertEqual(CSVTable.escape("6\" sub"), "\"6\"\" sub\"")
        XCTAssertEqual(CSVTable.escape("line\nbreak"), "\"line\nbreak\"")
        XCTAssertEqual(CSVTable.escape("=SUM(A1)"), "'=SUM(A1)")
        XCTAssertEqual(CSVTable.escape("-2.5"), "-2.5", "negative numbers are not formulas")
    }

    func testMissingValuesAreEmptyNotZero() {
        var table = CSVTable(header: ["food", "calories", "protein"])
        table.append(["Egg", CSVTable.number(78), nil])
        XCTAssertEqual(table.text, "food,calories,protein\r\nEgg,78,\r\n")
    }

    func testNumberFormattingIsLocaleIndependent() {
        XCTAssertEqual(CSVTable.number(2.50), "2.5")
        XCTAssertEqual(CSVTable.number(100), "100")
        XCTAssertEqual(CSVTable.number(0.1234), "0.123")
        XCTAssertEqual(CSVTable.number(-0.0001), "0")
        XCTAssertNil(CSVTable.number(nil))
        XCTAssertNil(CSVTable.number(.nan))
    }

    func testTimestampsAndDays() {
        let date = Date(timeIntervalSince1970: 1_773_655_200) // 2026-03-16 10:00 UTC
        XCTAssertEqual(CSVTable.timestamp(date), "2026-03-16T10:00:00Z")
        XCTAssertEqual(CSVTable.day(date, timeZone: TimeZone(identifier: "UTC")!), "2026-03-16")
        XCTAssertEqual(CSVTable.day(date, timeZone: TimeZone(identifier: "Pacific/Kiritimati")!), "2026-03-17")
    }
}

final class ReminderPlannerTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let morning = Date(timeIntervalSince1970: 1_773_655_200) // 2026-03-16 10:00 UTC

    func testIncludesTodayWhenNothingLoggedAndTimeAhead() {
        let dates = ReminderPlanner.fireDates(hour: 19, minute: 30, hasLoggedToday: false, now: morning, days: 3, calendar: calendar)
        XCTAssertEqual(dates.count, 3)
        XCTAssertEqual(dates.first, morning.addingTimeInterval(9.5 * 3_600))
        XCTAssertEqual(dates.last, morning.addingTimeInterval(9.5 * 3_600 + 2 * 86_400))
    }

    func testSkipsTodayWhenAlreadyLoggedOrTimePassed() {
        let logged = ReminderPlanner.fireDates(hour: 19, minute: 0, hasLoggedToday: true, now: morning, days: 2, calendar: calendar)
        XCTAssertEqual(logged.first, morning.addingTimeInterval(9 * 3_600 + 86_400))
        XCTAssertEqual(logged.count, 2)

        let passed = ReminderPlanner.fireDates(hour: 8, minute: 0, hasLoggedToday: false, now: morning, days: 2, calendar: calendar)
        XCTAssertEqual(passed.first, morning.addingTimeInterval(-2 * 3_600 + 86_400))
    }

    func testRejectsInvalidTimes() {
        XCTAssertTrue(ReminderPlanner.fireDates(hour: 24, minute: 0, hasLoggedToday: false, now: morning).isEmpty)
        XCTAssertTrue(ReminderPlanner.fireDates(hour: 9, minute: 60, hasLoggedToday: false, now: morning).isEmpty)
    }
}
