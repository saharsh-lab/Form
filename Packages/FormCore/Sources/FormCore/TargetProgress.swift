import Foundation

/// Progress of a consumed amount towards a user-configured daily target.
///
/// Safe for every input: a missing, zero, negative or non-finite target
/// yields `.noTarget` instead of dividing by zero.
public struct TargetProgress: Equatable, Sendable {

    public enum Status: Equatable, Sendable {
        /// No usable target is configured.
        case noTarget
        /// Below the target.
        case underTarget
        /// Within `tolerance` of the target.
        case reached
        /// Above the target by more than `tolerance`.
        case exceeded
    }

    public let consumed: Double
    public let target: Double?
    /// Amount within which the target counts as reached (for example 0.5 g or 5 kcal).
    public let tolerance: Double

    public init(consumed: Double, target: Double?, tolerance: Double = 0.5) {
        self.consumed = consumed.isFinite ? max(0, consumed) : 0
        if let target, target.isFinite, target > 0 {
            self.target = target
        } else {
            self.target = nil
        }
        self.tolerance = max(0, tolerance)
    }

    public var hasTarget: Bool { target != nil }

    /// consumed ÷ target, unclamped (1.25 means 25 % over). `nil` without a target.
    public var fraction: Double? {
        guard let target else { return nil }
        return consumed / target
    }

    /// Fraction clamped to 0...1, suitable for progress rings and bars.
    public var clampedFraction: Double {
        min(max(fraction ?? 0, 0), 1)
    }

    /// Fraction of the target exceeded, clamped to 0...1 (0.25 means 25 % over).
    public var overflowFraction: Double {
        guard let fraction, fraction > 1 else { return 0 }
        return min(fraction - 1, 1)
    }

    /// target − consumed. Negative when exceeded. `nil` without a target.
    public var remaining: Double? {
        guard let target else { return nil }
        return target - consumed
    }

    public var status: Status {
        guard let target else { return .noTarget }
        if consumed > target + tolerance { return .exceeded }
        if consumed >= target - tolerance { return .reached }
        return .underTarget
    }
}

/// A daily nutrition target that applies from a given day onwards.
public struct NutritionGoalSnapshot: Equatable, Sendable {
    public var effectiveFrom: Date
    public var targets: NutritionValues

    public init(effectiveFrom: Date, targets: NutritionValues) {
        self.effectiveFrom = effectiveFrom
        self.targets = targets
    }
}

public enum GoalResolver {
    /// The goal in effect on `day`: the most recent goal whose `effectiveFrom`
    /// is on or before the end of that day. Changing goals therefore never
    /// rewrites how past days are judged.
    public static func goal(on day: Date, from goals: [NutritionGoalSnapshot], calendar: Calendar = .current) -> NutritionGoalSnapshot? {
        let dayEnd = DayBounds.range(containing: day, calendar: calendar).upperBound
        return goals
            .filter { $0.effectiveFrom < dayEnd }
            .max { $0.effectiveFrom < $1.effectiveFrom }
    }
}

public enum DayBounds {
    /// The half-open range covering the calendar day that contains `date`.
    public static func range(containing date: Date, calendar: Calendar = .current) -> Range<Date> {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return start..<end
    }

    /// The half-open range covering the week that contains `date`, using the calendar's first weekday.
    public static func weekRange(containing date: Date, calendar: Calendar = .current) -> Range<Date> {
        if let interval = calendar.dateInterval(of: .weekOfYear, for: date) {
            return interval.start..<interval.end
        }
        let start = calendar.startOfDay(for: date)
        return start..<start.addingTimeInterval(7 * 86_400)
    }
}
