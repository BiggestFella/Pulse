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
    let est: String            // "~60 min"

    var eyebrow: String { "TODAY · \(programLabel) · WEEK \(week)" }
    var dayLabel: String { "Day \(day)" }
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
