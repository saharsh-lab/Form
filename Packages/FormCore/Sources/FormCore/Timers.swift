import Foundation

/// A rest timer modelled as dates rather than ticks, so it stays correct while
/// the app is suspended. The UI only reads `remaining(at:)` for display.
public struct RestTimer: Equatable, Codable, Sendable {

    public enum Phase: Equatable, Codable, Sendable {
        case idle
        case running(endDate: Date)
        case paused(remaining: TimeInterval)
        case finished
    }

    public static let allowedDurations: ClosedRange<TimeInterval> = 5...3_600

    /// The duration the timer starts from.
    public private(set) var duration: TimeInterval
    public private(set) var phase: Phase

    public init(duration: TimeInterval) {
        self.duration = Self.clamp(duration)
        self.phase = .idle
    }

    public var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    public var isPaused: Bool {
        if case .paused = phase { return true }
        return false
    }

    public var isActive: Bool { isRunning || isPaused }

    /// When the timer will finish, if running.
    public var endDate: Date? {
        if case .running(let end) = phase { return end }
        return nil
    }

    /// Seconds left at `now`, never negative.
    public func remaining(at now: Date) -> TimeInterval {
        switch phase {
        case .idle: return duration
        case .running(let end): return max(0, end.timeIntervalSince(now))
        case .paused(let remaining): return remaining
        case .finished: return 0
        }
    }

    /// Fraction of the current countdown that has elapsed, 0...1.
    public func progress(at now: Date) -> Double {
        guard duration > 0 else { return 1 }
        return min(max(1 - remaining(at: now) / duration, 0), 1)
    }

    public mutating func start(duration newDuration: TimeInterval? = nil, at now: Date) {
        if let newDuration { duration = Self.clamp(newDuration) }
        phase = .running(endDate: now.addingTimeInterval(duration))
    }

    public mutating func pause(at now: Date) {
        guard case .running(let end) = phase else { return }
        let left = end.timeIntervalSince(now)
        phase = left > 0 ? .paused(remaining: left) : .finished
    }

    public mutating func resume(at now: Date) {
        guard case .paused(let left) = phase else { return }
        phase = .running(endDate: now.addingTimeInterval(left))
    }

    /// Ends the rest early without a completion alert.
    public mutating func skip() {
        phase = .idle
    }

    /// Returns to idle at the full duration.
    public mutating func reset() {
        phase = .idle
    }

    /// Adds (or with a negative delta, removes) time.
    /// While idle this changes the duration; while active it changes the time left.
    public mutating func adjust(by delta: TimeInterval, at now: Date) {
        switch phase {
        case .idle, .finished:
            duration = Self.clamp(duration + delta)
        case .running(let end):
            let newEnd = end.addingTimeInterval(delta)
            if newEnd <= now {
                phase = .finished
            } else {
                phase = .running(endDate: newEnd)
                duration = max(duration, newEnd.timeIntervalSince(now))
            }
        case .paused(let left):
            let newLeft = left + delta
            if newLeft <= 0 {
                phase = .finished
            } else {
                phase = .paused(remaining: newLeft)
                duration = max(duration, newLeft)
            }
        }
    }

    /// Moves a running timer whose end date has passed into `.finished`.
    /// Returns true only on the call that performs that transition.
    @discardableResult
    public mutating func refresh(at now: Date) -> Bool {
        guard case .running(let end) = phase, end <= now else { return false }
        phase = .finished
        return true
    }

    private static func clamp(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return 90 }
        return min(max(value, allowedDurations.lowerBound), allowedDurations.upperBound)
    }
}

/// Elapsed time of a workout, excluding paused periods. Like `RestTimer` it
/// stores dates so elapsed time survives suspension and relaunch.
public struct WorkoutClock: Equatable, Codable, Sendable {
    public private(set) var startedAt: Date
    public private(set) var pausedAt: Date?
    public private(set) var accumulatedPause: TimeInterval
    public private(set) var endedAt: Date?

    public init(startedAt: Date, pausedAt: Date? = nil, accumulatedPause: TimeInterval = 0, endedAt: Date? = nil) {
        self.startedAt = startedAt
        self.pausedAt = pausedAt
        self.accumulatedPause = max(0, accumulatedPause)
        self.endedAt = endedAt
    }

    public var isPaused: Bool { pausedAt != nil && endedAt == nil }
    public var isFinished: Bool { endedAt != nil }

    public func elapsed(at now: Date) -> TimeInterval {
        let reference = endedAt ?? pausedAt ?? now
        return max(0, reference.timeIntervalSince(startedAt) - accumulatedPause)
    }

    public mutating func pause(at now: Date) {
        guard pausedAt == nil, endedAt == nil else { return }
        pausedAt = max(now, startedAt)
    }

    public mutating func resume(at now: Date) {
        guard let pausedAt, endedAt == nil else { return }
        accumulatedPause += max(0, now.timeIntervalSince(pausedAt))
        self.pausedAt = nil
    }

    /// Ends the workout. A paused workout ends at the moment it was paused.
    public mutating func finish(at now: Date) {
        guard endedAt == nil else { return }
        if let pausedAt {
            endedAt = pausedAt
        } else {
            endedAt = max(now, startedAt)
        }
    }
}
