import Foundation

public enum DurationText {
    /// Clock-style text: "0:45", "12:05", "1:02:09".
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0).rounded(.down))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Short summary text: "45 min", "1 h 5 min", "< 1 min".
    public static func summary(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(max(0, seconds.isFinite ? seconds : 0) / 60)
        if totalMinutes < 1 { return "< 1 min" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes) min" }
        if minutes == 0 { return "\(hours) h" }
        return "\(hours) h \(minutes) min"
    }
}
