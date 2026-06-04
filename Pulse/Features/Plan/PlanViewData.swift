import Foundation

/// Visual state of a calendar day cell.
enum DayState: String, CaseIterable {
    case done    // completed session: accent fill + onAccent dot
    case today   // today, not yet done: accent2 outline (tap launches workout)
    case plan    // scheduled (not done): faint fill + accent2 dot
    case empty   // unscheduled (incl. rest, which renders dashed/dimmed)
}

/// One day's schedule, as the views consume it.
struct ScheduledDay: Equatable {
    var state: DayState
    var workoutName: String?
    var isRest: Bool = false
}

/// Month-grid geometry + display strings. Monday-start week.
struct MonthContext: Equatable {
    var title: String          // "May."
    var year: Int              // 2026
    var monthStartOffset: Int  // leading blank cells, Monday-start (0...6)
    var daysInMonth: Int       // 31
    var monthAbbrevUpper: String // "MAY"
}

/// THIS MONTH summary card values.
struct MonthSummary: Equatable {
    var done: Int
    var planned: Int
    /// Completion percent, integer, floor; 0 when nothing planned.
    var pct: Int { planned == 0 ? 0 : Int((Double(done) / Double(planned)) * 100) }
}

/// One agenda row.
struct AgendaEntry: Equatable, Identifiable {
    var id: Int { day }       // day-of-month is unique within the window
    var day: Int              // day-of-month
    var dow: String           // "WED"
    var name: String?         // workout name, nil for empty
    var sub: String?          // "6 EXERCISES · ~52M"
    var isToday: Bool
    var isRest: Bool
    var isDone: Bool = false  // completed session — non-interactive, routes to read-only sheet
}

/// A saved workout the picker can assign.
struct SavedWorkoutRef: Equatable, Identifiable {
    var id: UUID
    var name: String
    var exerciseCount: Int
    var sub: String { "\(exerciseCount) EXERCISES" }
}
