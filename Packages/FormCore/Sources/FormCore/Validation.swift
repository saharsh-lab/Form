import Foundation

public enum ValidationError: Error, Equatable, Sendable, LocalizedError {
    case empty
    case tooLong(maximum: Int)
    case notANumber
    case notAWholeNumber
    case outOfRange(minimum: Double, maximum: Double)
    case dateInFuture

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "This field is required."
        case .tooLong(let maximum):
            return "Use \(maximum) characters or fewer."
        case .notANumber:
            return "Enter a number."
        case .notAWholeNumber:
            return "Enter a whole number."
        case .outOfRange(let minimum, let maximum):
            return "Enter a value from \(InputValidator.plain(minimum)) to \(InputValidator.plain(maximum))."
        case .dateInFuture:
            return "Choose a date that isn't in the future."
        }
    }
}

/// Validation and locale-aware parsing for user-entered text.
public enum InputValidator {

    /// A trimmed, non-empty name of at most `maximumLength` characters.
    public static func name(_ text: String, maximumLength: Int = 80) -> Result<String, ValidationError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard trimmed.count <= maximumLength else { return .failure(.tooLong(maximum: maximumLength)) }
        return .success(trimmed)
    }

    /// Parses a decimal. Empty text is `nil` (unspecified), never zero.
    public static func optionalDecimal(_ text: String, in range: ClosedRange<Double>, locale: Locale = .current) -> Result<Double?, ValidationError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .success(nil) }
        guard let value = parseDecimal(trimmed, locale: locale) else { return .failure(.notANumber) }
        guard range.contains(value) else {
            return .failure(.outOfRange(minimum: range.lowerBound, maximum: range.upperBound))
        }
        return .success(value)
    }

    /// Parses a decimal that must be present.
    public static func requiredDecimal(_ text: String, in range: ClosedRange<Double>, locale: Locale = .current) -> Result<Double, ValidationError> {
        switch optionalDecimal(text, in: range, locale: locale) {
        case .success(let value?): return .success(value)
        case .success(nil): return .failure(.empty)
        case .failure(let error): return .failure(error)
        }
    }

    /// Parses a whole number that must be present.
    public static func requiredInteger(_ text: String, in range: ClosedRange<Int>, locale: Locale = .current) -> Result<Int, ValidationError> {
        let doubleRange = Double(range.lowerBound)...Double(range.upperBound)
        switch requiredDecimal(text, in: doubleRange, locale: locale) {
        case .success(let value):
            guard value.rounded() == value else { return .failure(.notAWholeNumber) }
            return .success(Int(value))
        case .failure(let error):
            return .failure(error)
        }
    }

    /// A date that is not later than the end of today.
    public static func pastOrPresent(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Result<Date, ValidationError> {
        let endOfToday = DayBounds.range(containing: now, calendar: calendar).upperBound
        return date < endOfToday ? .success(date) : .failure(.dateInFuture)
    }

    /// Accepts the locale's decimal separator and also a plain "." or ",".
    /// Rejects grouping-only or trailing garbage such as "12abc".
    public static func parseDecimal(_ text: String, locale: Locale = .current) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let separator = locale.decimalSeparator ?? "."
        var normalized = trimmed.replacingOccurrences(of: separator, with: ".")
        if separator != "," { normalized = normalized.replacingOccurrences(of: ",", with: ".") }
        // Only digits and a single decimal point are accepted.
        let allowed = Set("0123456789.")
        guard normalized.allSatisfy({ allowed.contains($0) }),
              normalized.filter({ $0 == "." }).count <= 1,
              normalized != "." else { return nil }
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    static func plain(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}
