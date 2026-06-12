import Foundation

/// Hero-card projection of today's prescribed workout.
struct TodayWorkoutCard: Equatable, Identifiable {
    var id: UUID { workoutID }
    let workoutID: UUID
    let programLabel: String   // "PPL"
    let week: Int              // 4
    let day: Int               // 23
    let name: String           // "Chest & Tris"
    let exerciseCount: Int     // 7
    let estimatedMinutes: Int  // 60 — structured; formatted at this layer, not in the data source

    var eyebrow: String { "TODAY · \(programLabel) · WEEK \(week)" }
    var dayLabel: String { "Day \(day)" }

    /// Estimated duration copy. Formatted here in the projection (not baked into
    /// the repository) so the real Supabase repo supplies a number rather than
    /// English copy. Fixed-locale, consistent with `HistoryFormat`; full
    /// localisation is deferred to the future unit-toggle effort.
    var est: String { "~\(estimatedMinutes) min" }

    /// Footer eyebrow. The uppercasing is the locale-independent `uppercased()`
    /// deliberately: these are stylistic design tokens (Geist Mono eyebrows), not
    /// linguistic text, so they must render identically regardless of device locale.
    var footerEyebrow: String { "\(exerciseCount) EXERCISES · \(est.uppercased())" }
}

/// One of exactly seven cells in the week strip.
struct WeekDayCell: Equatable, Identifiable {
    enum State: String, CaseIterable { case done, today, plan, rest }
    /// Identity is the strip position, not the content: rest days repeat
    /// (e.g. two "Rest" cells) and would otherwise collide in a `ForEach`.
    var id: Int { index }
    let index: Int          // 0...6 — position in the strip
    let dayLetter: String   // "M"
    let label: String       // "Chest&Tris"
    let state: State
}

/// Most-recent completed session, shown in the Yesterday row.
struct SessionRecap: Equatable, Identifiable {
    var id: UUID { sessionID }
    let sessionID: UUID
    let name: String        // "Legs"
    let subline: String     // "71M · 18.7K KG · +1 PR"
}

/// Everything the Today screen needs in one projection. Composed from the shared
/// `RepositoryContainer` repositories by `TodaySnapshotComposer` (BAK-24) — the
/// screen depends only on this value type, never on a repository directly. Also
/// mirrored into the widget App Group by `WidgetSnapshotWriter` (BAK-19).
struct TodaySnapshot: Equatable {
    let dateEyebrow: String        // "WED · MAY 28"
    let greetingName: String       // "Alex"
    let streak: Int                // honored scheduled days
    let today: TodayWorkoutCard?   // nil on a rest / no-workout day
    let week: [WeekDayCell]        // always exactly 7
    let yesterday: SessionRecap?   // nil when there is no prior session
}

/// Deterministic fixtures for SwiftUI previews. Production composes the real
/// snapshot from repositories (`TodaySnapshotComposer`); these keep the component
/// previews self-contained.
extension TodaySnapshot {
    static let sampleCard = TodayWorkoutCard(
        workoutID: UUID(),
        programLabel: "PPL", week: 4, day: 23,
        name: "Chest & Tris", exerciseCount: 7, estimatedMinutes: 60)

    static let sampleWeek: [WeekDayCell] = [
        WeekDayCell(index: 0, dayLetter: "M", label: "Chest&Tris", state: .done),
        WeekDayCell(index: 1, dayLetter: "T", label: "Back&Bis", state: .done),
        WeekDayCell(index: 2, dayLetter: "W", label: "Legs", state: .done),
        WeekDayCell(index: 3, dayLetter: "T", label: "Shoulders", state: .today),
        WeekDayCell(index: 4, dayLetter: "F", label: "Arms·finisher", state: .plan),
        WeekDayCell(index: 5, dayLetter: "S", label: "Rest", state: .rest),
        WeekDayCell(index: 6, dayLetter: "S", label: "Rest", state: .rest),
    ]

    static let sampleRecap = SessionRecap(
        sessionID: UUID(), name: "Legs", subline: "71M · 18.7K KG · +1 PR")

    /// Whole-snapshot fixtures (a training day and a rest day). Used by previews
    /// and by the widget-writer tests that map a snapshot into a `WidgetSnapshot`.
    static let sample = TodaySnapshot(
        dateEyebrow: "WED · MAY 28", greetingName: "Alex", streak: 27,
        today: sampleCard, week: sampleWeek, yesterday: sampleRecap)

    static let restDay = TodaySnapshot(
        dateEyebrow: "SAT · MAY 31", greetingName: "Alex", streak: 27,
        today: nil, week: sampleWeek, yesterday: sampleRecap)
}
