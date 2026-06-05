import Foundation

/// The single source of derived workout math. `StatsRepository` and
/// `PRRepository` call this — no screen or repo reimplements volume / 1RM /
/// PR / streak. All day-bucketing uses the injected calendar (default
/// `Calendar.current`, device-local, Monday-start) per product decisions.
enum WorkoutAnalytics {

    /// Only working & AMRAP sets count toward volume and PRs.
    static func counts(_ type: SetType) -> Bool {
        type == .working || type == .amrap
    }

    /// reps × weight, or 0 for non-counting (warmup/dropset/failure) sets.
    static func setVolume(_ set: SessionSet) -> Double {
        counts(set.type) ? Double(set.reps) * set.weight : 0
    }

    static func sessionVolume(_ session: WorkoutSession) -> Double {
        session.sets.reduce(0) { $0 + setVolume($1) }
    }

    /// Epley: weight × (1 + reps / 30). One rep returns the bar weight.
    static func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        guard reps > 1 else { return weight }
        return weight * (1 + Double(reps) / 30)
    }

    static func estimatedOneRepMax(_ set: SessionSet) -> Double {
        estimatedOneRepMax(weight: set.weight, reps: set.reps)
    }

    /// Best counting set by estimated 1RM (warmups excluded). `nil` if none.
    static func bestSet(in sets: [SessionSet]) -> SessionSet? {
        sets.filter { counts($0.type) }
            .max { estimatedOneRepMax($0) < estimatedOneRepMax($1) }
    }

    /// Heaviest counting-set weight (warmups excluded). `nil` if no counting sets.
    static func topWorkingWeight(in sets: [SessionSet]) -> Double? {
        sets.filter { counts($0.type) }.map(\.weight).max()
    }

    /// Total counting-set volume across the given sets (warmups excluded).
    static func volume(of sets: [SessionSet]) -> Double {
        sets.reduce(0) { $0 + setVolume($1) }
    }

    /// Consecutive honored scheduled days ending at `asOf`. A `.done` day already
    /// encodes a completed session, so it counts unconditionally; a scheduled
    /// `.workout` day counts only if a session completed that day (else the streak
    /// breaks); a `.rest` day is transparent (neither breaks nor extends). Days
    /// with no plan entry stop the walk.
    static func streak(plan: [Date: DayPlan],
                       completedDays: Set<Date>,
                       asOf: Date,
                       calendar: Calendar = .current) -> Int {
        var streak = 0
        var cursor = calendar.startOfDay(for: asOf)
        while let entry = plan[cursor] {
            switch entry {
            case .rest:
                break // transparent — neither breaks nor extends
            case .workout:
                if completedDays.contains(cursor) { streak += 1 } else { return streak }
            case .done:
                streak += 1 // a logged session — counts unconditionally
            }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = calendar.startOfDay(for: prev)
        }
        return streak
    }

    /// Bucket a date into a label string for chart axes. Labels are fixed-locale
    /// (`en_US_POSIX`) so they read identically regardless of device language.
    /// - 7D/30D: "Mon", "Tue" … (day abbreviation)
    /// - 3M: "W1", "W2" … (week number relative to `rangeStart` when given —
    ///   counts straight across a year boundary; otherwise the absolute
    ///   calendar week-of-year for the injected calendar)
    /// - YR/ALL: "Jan", "Feb" … (month abbreviation)
    static func bucketLabel(for date: Date, range: StatRange,
                            rangeStart: Date? = nil,
                            calendar: Calendar = .current) -> String {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.locale = Locale(identifier: "en_US_POSIX")
        switch range {
        case .d7, .d30:
            fmt.dateFormat = "EEE"
        case .m3:
            guard let rangeStart else {
                return "W\(calendar.component(.weekOfYear, from: date))"
            }
            // Number of whole weeks from the range start's week to this date's
            // week; +1 so the first bucket reads "W1". Counting between
            // week-start dates avoids the W52→W1 reset at the year boundary.
            func weekStart(_ d: Date) -> Date {
                calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d))!
            }
            let weeks = calendar.dateComponents([.weekOfYear],
                                                from: weekStart(rangeStart),
                                                to: weekStart(date)).weekOfYear ?? 0
            return "W\(weeks + 1)"
        case .year, .all:
            fmt.dateFormat = "MMM"
        }
        return fmt.string(from: date)
    }
}
