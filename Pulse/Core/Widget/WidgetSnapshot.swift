import Foundation

/// View-ready read-model the app writes to the shared App Group and the
/// `PulseWidgets` extension renders from (BAK-19). The widget never touches a
/// repository or Supabase — it only decodes this snapshot. Mirrors the Today
/// projection (`TodaySnapshot`); `nil` `todayWorkoutName` means a rest / no-workout
/// day. Cross-compiled into both the app and the widget target.
struct WeekCellSnapshot: Codable, Equatable {
    var dayLetter: String       // "M"
    var state: String           // "done" | "today" | "plan" | "rest" (WeekDayCell.State.rawValue)
}

struct WidgetSnapshot: Codable, Equatable {
    var palette: String                 // Palette.rawValue — "coastal" | "mint"
    var generatedAt: Date
    var programLabel: String?           // "PPL" — nil if no program
    var dayLabel: String?               // "Day 23"
    var todayWorkoutName: String?       // nil = rest / no workout today
    var exerciseCount: Int?             // nil on a rest day
    var week: [WeekCellSnapshot]        // exactly 7 when valid
    var streak: Int
    var startRoute: String              // deep link the widget taps into

    /// Completed days this week.
    var doneCount: Int { week.filter { $0.state == "done" }.count }
    /// Planned (non-rest) days — matches the Today progress rule.
    var plannedCount: Int { week.filter { $0.state != "rest" }.count }
    var isRestDay: Bool { todayWorkoutName == nil }
    /// A corrupt/partial week (not exactly 7 cells) is treated as invalid → fallback.
    var hasValidWeek: Bool { week.count == 7 }

    /// A copy with the workout dropped, used for a timeline entry that crosses
    /// into a new day so a stale snapshot never shows yesterday's workout — the
    /// rest/neutral treatment renders instead, deep-linking to the Today tab (BAK-19).
    func staleNeutralized() -> WidgetSnapshot {
        var copy = self
        copy.todayWorkoutName = nil
        copy.exerciseCount = nil
        copy.dayLabel = nil
        copy.programLabel = nil
        copy.startRoute = WidgetDeepLink.today.url.absoluteString
        return copy
    }
}

extension WidgetSnapshot {
    /// Fixed sample used by the widget placeholder and the store fallback. The
    /// date is fixed so fixtures are deterministic; the now-entry always renders
    /// it as-is (only the synthetic midnight entry re-derives staleness).
    static let sample = WidgetSnapshot(
        palette: "coastal",
        generatedAt: Date(timeIntervalSinceReferenceDate: 800_000_000),
        programLabel: "PPL",
        dayLabel: "Day 23",
        todayWorkoutName: "Chest & Tris",
        exerciseCount: 7,
        week: [
            WeekCellSnapshot(dayLetter: "M", state: "done"),
            WeekCellSnapshot(dayLetter: "T", state: "done"),
            WeekCellSnapshot(dayLetter: "W", state: "done"),
            WeekCellSnapshot(dayLetter: "T", state: "today"),
            WeekCellSnapshot(dayLetter: "F", state: "plan"),
            WeekCellSnapshot(dayLetter: "S", state: "rest"),
            WeekCellSnapshot(dayLetter: "S", state: "rest"),
        ],
        streak: 27,
        startRoute: WidgetDeepLink.startToday.url.absoluteString)

    /// Rest-day sample (no workout today).
    static let restSample = WidgetSnapshot(
        palette: "coastal",
        generatedAt: Date(timeIntervalSinceReferenceDate: 800_000_000),
        programLabel: "PPL",
        dayLabel: nil,
        todayWorkoutName: nil,
        exerciseCount: nil,
        week: sample.week,
        streak: 27,
        startRoute: WidgetDeepLink.today.url.absoluteString)

    /// All-rest week — `plannedCount == 0` (gauge divide-by-zero guard).
    static let allRestSample = WidgetSnapshot(
        palette: "coastal",
        generatedAt: Date(timeIntervalSinceReferenceDate: 800_000_000),
        programLabel: nil,
        dayLabel: nil,
        todayWorkoutName: nil,
        exerciseCount: nil,
        week: Array(repeating: WeekCellSnapshot(dayLetter: "R", state: "rest"), count: 7),
        streak: 0,
        startRoute: WidgetDeepLink.today.url.absoluteString)
}
