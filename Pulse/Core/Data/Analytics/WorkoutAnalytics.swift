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
    /// - 3M: "W48", "W49" … (calendar week-of-year for the injected calendar)
    /// - YR/ALL: "Jan", "Feb" … (month abbreviation)
    static func bucketLabel(for date: Date, range: StatRange,
                            calendar: Calendar = .current) -> String {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.locale = Locale(identifier: "en_US_POSIX")
        switch range {
        case .d7, .d30:
            fmt.dateFormat = "EEE"
        case .m3:
            let week = calendar.component(.weekOfYear, from: date)
            return "W\(week)"
        case .year, .all:
            fmt.dateFormat = "MMM"
        }
        return fmt.string(from: date)
    }
}
