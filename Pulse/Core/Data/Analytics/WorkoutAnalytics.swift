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

    /// Consecutive honored scheduled days ending at `asOf`. A scheduled training
    /// day (`.workout`) counts only if a session completed that day; a `.rest`
    /// day is transparent (neither breaks nor extends); a scheduled day with no
    /// completed session breaks the streak. Days with no plan entry stop the walk.
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
                if completedDays.contains(cursor) { streak += 1 } else { return streak }
            }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = calendar.startOfDay(for: prev)
        }
        return streak
    }

    /// Bucket a date into a label string for chart axes.
    /// - 7D/30D: "Mon", "Tue" … (day abbreviation)
    /// - 3M: "W1", "W2" … (ISO week number, relative)
    /// - YR/ALL: "Jan", "Feb" … (month abbreviation)
    static func bucketLabel(for date: Date, range: StatRange,
                            calendar: Calendar = .current) -> String {
        let fmt = DateFormatter()
        fmt.calendar = calendar
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
