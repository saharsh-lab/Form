import Foundation

/// A recorded value at a date. Analytics never invent points: every point
/// comes from a stored record, and gaps stay gaps.
public struct SeriesPoint: Equatable, Hashable, Sendable, Identifiable {
    public var date: Date
    public var value: Double
    public var id: Date { date }

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// A calendar bucket (week or month) and how many events fell in it.
/// Zero counts are real: no workout was logged in that period.
public struct PeriodCount: Equatable, Hashable, Sendable, Identifiable {
    public var start: Date
    public var count: Int
    public var id: Date { start }

    public init(start: Date, count: Int) {
        self.start = start
        self.count = count
    }
}

/// Date ranges offered by the Progress screens.
public enum ProgressRange: String, CaseIterable, Identifiable, Sendable {
    case fourWeeks
    case threeMonths
    case sixMonths
    case oneYear
    case all

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fourWeeks: return "4W"
        case .threeMonths: return "3M"
        case .sixMonths: return "6M"
        case .oneYear: return "1Y"
        case .all: return "All"
        }
    }

    public var accessibilityName: String {
        switch self {
        case .fourWeeks: return "4 weeks"
        case .threeMonths: return "3 months"
        case .sixMonths: return "6 months"
        case .oneYear: return "1 year"
        case .all: return "All time"
        }
    }

    /// Start of the range, at the start of a day; `nil` for all time.
    public func startDate(now: Date, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .fourWeeks: return calendar.date(byAdding: .day, value: -27, to: today)
        case .threeMonths: return calendar.date(byAdding: .month, value: -3, to: today)
        case .sixMonths: return calendar.date(byAdding: .month, value: -6, to: today)
        case .oneYear: return calendar.date(byAdding: .year, value: -1, to: today)
        case .all: return nil
        }
    }

    /// Weekly buckets for short ranges, monthly for long ones.
    public var bucket: Calendar.Component {
        switch self {
        case .fourWeeks, .threeMonths: return .weekOfYear
        case .sixMonths, .oneYear, .all: return .month
        }
    }
}

public enum ProgressAnalytics {

    /// Counts `dates` per week or month from the bucket containing `start`
    /// through the bucket containing `end`, including empty buckets.
    public static func counts(of dates: [Date], per component: Calendar.Component,
                              from start: Date, to end: Date, calendar: Calendar = .current) -> [PeriodCount] {
        guard start <= end, let first = calendar.dateInterval(of: component, for: start)?.start else { return [] }
        var buckets: [Date: Int] = [:]
        for date in dates where date >= first && date <= end {
            if let bucket = calendar.dateInterval(of: component, for: date)?.start {
                buckets[bucket, default: 0] += 1
            }
        }
        var result: [PeriodCount] = []
        var cursor = first
        var guardCount = 0
        while cursor <= end && guardCount < 1_000 {
            result.append(PeriodCount(start: cursor, count: buckets[cursor] ?? 0))
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor) else { break }
            cursor = next
            guardCount += 1
        }
        return result
    }

    /// Consecutive weeks with at least one workout, counting back from the week
    /// containing `now`. The current week counts only if it already has one,
    /// so an empty current week doesn't break an ongoing streak.
    public static func weeklyStreak(of dates: [Date], now: Date, calendar: Calendar = .current) -> Int {
        let weeks = Set(dates.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0)?.start })
        guard var cursor = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        if !weeks.contains(cursor) {
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { return 0 }
            cursor = previous
        }
        var streak = 0
        while weeks.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    /// Average workouts per week between `start` and `now` (at least one week).
    public static func averagePerWeek(of dates: [Date], from start: Date, now: Date) -> Double {
        let count = dates.filter { $0 >= start && $0 <= now }.count
        let weeks = max(1, now.timeIntervalSince(start) / (7 * 86_400))
        return Double(count) / weeks
    }

    /// Averages a nutrient over the days that have at least one diary entry.
    /// Days with nothing logged are excluded rather than treated as zero, and
    /// days where every entry lacks the value are excluded for that nutrient.
    public static func dailyAverage(_ days: [Date: NutritionTotals], nutrient: Nutrient) -> (average: Double, days: Int)? {
        let usable = days.values.filter { $0.entryCount > 0 && $0.missingCount(for: nutrient) < $0.entryCount }
        guard !usable.isEmpty else { return nil }
        let total = usable.reduce(0) { $0 + $1.total(for: nutrient) }
        return (total / Double(usable.count), usable.count)
    }

    /// The point whose date is closest to `date`, for chart selection.
    public static func nearest(to date: Date, in points: [SeriesPoint]) -> SeriesPoint? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    /// The bucket containing `date`, for bar-chart selection.
    public static func bucket(containing date: Date, in counts: [PeriodCount], per component: Calendar.Component,
                              calendar: Calendar = .current) -> PeriodCount? {
        guard let start = calendar.dateInterval(of: component, for: date)?.start else { return nil }
        return counts.first { $0.start == start }
    }
}
