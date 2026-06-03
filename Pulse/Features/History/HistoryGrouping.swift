import Foundation

/// A labelled recency bucket of session summaries (most-recent first within).
struct HistoryGroup: Equatable, Identifiable {
    var id: String { label }
    let label: String
    let sessions: [WorkoutHistoryModel.Item]
}

/// Buckets history rows into Monday-start recency groups: THIS WEEK, LAST WEEK,
/// then one header per older calendar month ("APRIL 2026"). Pure + injectable
/// calendar so it is deterministic in tests; production passes `Calendar.current`
/// (device-local, Monday-start per product decisions).
enum HistoryGrouping {
    static func groups(for items: [WorkoutHistoryModel.Item],
                       now: Date = Date(),
                       calendar: Calendar = .current) -> [HistoryGroup] {
        guard !items.isEmpty else { return [] }

        let sorted = items.sorted { $0.date > $1.date } // most-recent first
        let thisWeekStart = startOfWeek(for: now, calendar: calendar)
        let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: thisWeekStart)!

        var thisWeek: [WorkoutHistoryModel.Item] = []
        var lastWeek: [WorkoutHistoryModel.Item] = []
        var older: [WorkoutHistoryModel.Item] = []
        for item in sorted {
            if item.date >= thisWeekStart { thisWeek.append(item) }
            else if item.date >= lastWeekStart { lastWeek.append(item) }
            else { older.append(item) }
        }

        var result: [HistoryGroup] = []
        if !thisWeek.isEmpty { result.append(.init(label: "THIS WEEK", sessions: thisWeek)) }
        if !lastWeek.isEmpty { result.append(.init(label: "LAST WEEK", sessions: lastWeek)) }

        // Older: one group per calendar month, preserving most-recent-first order.
        var bucketed: [String: [WorkoutHistoryModel.Item]] = [:]
        var order: [String] = []
        for item in older {
            let key = monthLabel(for: item.date, calendar: calendar)
            if bucketed[key] == nil { order.append(key) }
            bucketed[key, default: []].append(item)
        }
        for key in order { result.append(.init(label: key, sessions: bucketed[key]!)) }
        return result
    }

    private static func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: comps)!
    }

    private static func monthLabel(for date: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMMM yyyy"
        return f.string(from: date).uppercased()
    }
}
