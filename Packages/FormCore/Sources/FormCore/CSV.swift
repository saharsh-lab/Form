import Foundation

/// Minimal RFC 4180 CSV writer. Missing values are written as empty fields,
/// never as zero, so a spreadsheet can tell "not entered" from "0".
public struct CSVTable: Sendable {
    public let header: [String]
    public private(set) var rows: [[String]] = []

    public init(header: [String]) {
        self.header = header
    }

    public mutating func append(_ fields: [String?]) {
        precondition(fields.count == header.count, "CSV row has \(fields.count) fields, expected \(header.count)")
        rows.append(fields.map { $0 ?? "" })
    }

    /// The table as text with CRLF line endings, as RFC 4180 specifies.
    public var text: String {
        ([header] + rows).map { $0.map(Self.escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    /// Quotes a field when it contains a comma, quote or line break, doubling inner quotes.
    /// Fields that a spreadsheet would run as a formula are prefixed with an apostrophe.
    public static func escape(_ field: String) -> String {
        var value = field
        if let first = value.first, "=+-@".contains(first), Double(value) == nil {
            value = "'" + value
        }
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Locale-independent number text (dot decimal separator, no grouping, trailing zeros trimmed).
    public static func number(_ value: Double?, maxFractionDigits: Int = 3) -> String? {
        guard let value, value.isFinite else { return nil }
        var text = String(format: "%.\(maxFractionDigits)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text == "-0" ? "0" : text
    }

    /// ISO 8601 timestamp in UTC, e.g. 2026-03-16T10:00:00Z.
    public static func timestamp(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// Calendar day in the given time zone, e.g. 2026-03-16.
    public static func day(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}

/// Works out when the optional daily logging reminder should fire.
public enum ReminderPlanner {
    /// The next `days` reminder times at `hour:minute`, skipping today if the time
    /// has passed or something has already been logged today.
    public static func fireDates(hour: Int, minute: Int, hasLoggedToday: Bool, now: Date,
                                 days: Int = 7, calendar: Calendar = .current) -> [Date] {
        guard (0...23).contains(hour), (0...59).contains(minute), days > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        var dates: [Date] = []
        var offset = 0
        while dates.count < days && offset <= days {
            defer { offset += 1 }
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { continue }
            if offset == 0 && (hasLoggedToday || fire <= now) { continue }
            dates.append(fire)
        }
        return dates
    }
}
