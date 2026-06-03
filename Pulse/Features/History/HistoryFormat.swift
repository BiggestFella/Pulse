import Foundation

/// Shared, fixed-locale formatting for the history-stack screens. Centralised so
/// volume/date/duration copy is consistent and a future unit toggle is localised.
/// v1 is kilograms-only (product decision).
enum HistoryFormat {
    private static func posix(_ format: String, _ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }

    /// "WED" — uppercase three-letter weekday.
    static func dayOfWeek(_ date: Date, calendar: Calendar = .current) -> String {
        posix("EEE", calendar).string(from: date).uppercased()
    }

    /// "21" — day-of-month numeral.
    static func dayNumber(_ date: Date, calendar: Calendar = .current) -> String {
        posix("d", calendar).string(from: date)
    }

    /// "WED · MAY 21 · 58M" — the Session Detail eyebrow.
    static func detailEyebrow(_ date: Date, end: Date?, calendar: Calendar = .current) -> String {
        let dow = dayOfWeek(date, calendar: calendar)
        let monthDay = posix("MMM d", calendar).string(from: date).uppercased()
        let dur = durationLabel(start: date, end: end).uppercased()
        return "\(dow) · \(monthDay) · \(dur)"
    }

    /// "58m" from start/end. Falls back to "—" when the session never ended.
    static func durationLabel(start: Date, end: Date?) -> String {
        guard let end else { return "—" }
        let minutes = Int((end.timeIntervalSince(start) / 60).rounded())
        return "\(max(minutes, 0))m"
    }

    /// Abbreviated volume with a lowercase k: "12.4k", "5.7k", "800".
    static func abbreviate(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "%.1fm", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.1fk", v / 1_000) }
        return "\(Int(v.rounded()))"
    }
}
