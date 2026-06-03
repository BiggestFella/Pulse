import Foundation

/// Uppercase session-date labels in the device-local calendar/timezone.
/// Fixed `en_US_POSIX` locale so the format reads identically across languages
/// (matches the convention used by `WorkoutAnalytics.bucketLabel`).
enum SessionDateLabel {
    private static func formatted(_ date: Date, _ format: String) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f.string(from: date).uppercased()
    }

    /// "FRI · MAY 22"
    static func row(_ date: Date) -> String { formatted(date, "EEE '·' MMM d") }

    /// "FRI"
    static func weekday(_ date: Date) -> String { formatted(date, "EEE") }
}
