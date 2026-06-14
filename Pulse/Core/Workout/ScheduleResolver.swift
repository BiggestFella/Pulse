import Foundation

/// Computes the effective plan for a date by reconciling the per-date schedule
/// (`plan_entries`) with each workout's recurring `weekdays`. Pure + testable;
/// shared by Today and the Plan tab so they always agree.
enum ScheduleResolver {
    /// Gregorian weekday (1=Sun…7=Sat) → app weekday (Mon=1…Sun=7).
    static func appWeekday(of date: Date, calendar: Calendar) -> Int {
        let greg = calendar.component(.weekday, from: date)
        return ((greg + 5) % 7) + 1
    }

    /// Precedence: a specific `plan_entry` wins; else the recurring workout whose
    /// `weekdays` include this weekday (lowest `order`); else `nil` (no plan —
    /// callers map that to their own empty/rest state).
    static func plan(for date: Date, entry: DayPlan?,
                     workouts: [Workout], calendar: Calendar) -> DayPlan? {
        if let entry { return entry }
        let wd = appWeekday(of: date, calendar: calendar)
        if let w = workouts.filter({ $0.weekdays.contains(wd) })
                           .sorted(by: { $0.order < $1.order }).first {
            return .workout(w.id)
        }
        return nil
    }
}
