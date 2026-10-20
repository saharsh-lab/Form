import XCTest
@testable import FormCore

final class ProgressAnalyticsTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2 // Monday
        return calendar
    }

    private func date(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: string)!
    }

    func testWeeklyCountsIncludeEmptyWeeks() {
        // Mondays: 2026-03-02, 03-09, 03-16
        let dates = [date("2026-03-03"), date("2026-03-05"), date("2026-03-18")]
        let counts = ProgressAnalytics.counts(of: dates, per: .weekOfYear,
                                              from: date("2026-03-02"), to: date("2026-03-20"), calendar: calendar)
        XCTAssertEqual(counts.map(\.count), [2, 0, 1])
        XCTAssertEqual(counts.first?.start, date("2026-03-02"))
    }

    func testMonthlyCounts() {
        let dates = [date("2026-01-10"), date("2026-03-01"), date("2026-03-31")]
        let counts = ProgressAnalytics.counts(of: dates, per: .month, from: date("2026-01-15"), to: date("2026-03-31"), calendar: calendar)
        XCTAssertEqual(counts.map(\.count), [1, 0, 2])
    }

    func testWeeklyStreak() {
        let now = date("2026-03-18") // week of 03-16
        let dates = [date("2026-03-03"), date("2026-03-10"), date("2026-03-17")]
        XCTAssertEqual(ProgressAnalytics.weeklyStreak(of: dates, now: now, calendar: calendar), 3)
        // An empty current week does not break the streak yet.
        XCTAssertEqual(ProgressAnalytics.weeklyStreak(of: [date("2026-03-03"), date("2026-03-10")], now: now, calendar: calendar), 2)
        // A missed week does.
        XCTAssertEqual(ProgressAnalytics.weeklyStreak(of: [date("2026-03-03")], now: now, calendar: calendar), 0)
        XCTAssertEqual(ProgressAnalytics.weeklyStreak(of: [], now: now, calendar: calendar), 0)
    }

    func testDailyAverageIgnoresUnloggedDaysAndMissingValues() {
        let full = NutritionTotals([NutritionValues(calories: 2_000, protein: 150, carbohydrates: 200, fat: 60)])
        let partial = NutritionTotals([NutritionValues(calories: 1_600, protein: nil)])
        let days: [Date: NutritionTotals] = [date("2026-03-01"): full, date("2026-03-02"): partial, date("2026-03-03"): NutritionTotals()]

        let calories = ProgressAnalytics.dailyAverage(days, nutrient: .calories)
        XCTAssertEqual(calories?.average ?? 0, 1_800, accuracy: 1e-9)
        XCTAssertEqual(calories?.days, 2)

        let protein = ProgressAnalytics.dailyAverage(days, nutrient: .protein)
        XCTAssertEqual(protein?.average ?? 0, 150, accuracy: 1e-9, "a day with no protein values isn't averaged as zero")
        XCTAssertEqual(protein?.days, 1)

        XCTAssertNil(ProgressAnalytics.dailyAverage([:], nutrient: .calories))
    }

    func testNearestPointAndBucketSelection() {
        let points = [SeriesPoint(date: date("2026-03-01"), value: 80), SeriesPoint(date: date("2026-03-10"), value: 79)]
        XCTAssertEqual(ProgressAnalytics.nearest(to: date("2026-03-07"), in: points)?.value, 79)
        XCTAssertNil(ProgressAnalytics.nearest(to: date("2026-03-07"), in: []))

        let counts = [PeriodCount(start: date("2026-03-02"), count: 2)]
        XCTAssertEqual(ProgressAnalytics.bucket(containing: date("2026-03-04"), in: counts, per: .weekOfYear, calendar: calendar)?.count, 2)
    }

    func testRanges() {
        let now = date("2026-03-31")
        XCTAssertEqual(ProgressRange.fourWeeks.startDate(now: now, calendar: calendar), date("2026-03-04"))
        XCTAssertNil(ProgressRange.all.startDate(now: now, calendar: calendar))
        XCTAssertEqual(ProgressAnalytics.averagePerWeek(of: [date("2026-03-10"), date("2026-03-20")], from: date("2026-03-03"), now: date("2026-03-31")), 0.5, accuracy: 1e-9)
    }
}
