import Foundation

/// Deterministic in-memory `TodayRepository` for UI-first development, previews,
/// and tests. Mirrors the sample data in the spec (and `docs/design/pulse-app.jsx`).
struct MockTodayRepository: TodayRepository {
    enum Failure: Error { case unavailable }

    var snapshot: TodaySnapshot?      // nil => throw (error path)
    var artificialDelay: Duration = .zero

    func loadToday() async throws -> TodaySnapshot {
        if artificialDelay > .zero { try? await Task.sleep(for: artificialDelay) }
        guard let snapshot else { throw Failure.unavailable }
        return snapshot
    }

    // MARK: Canned variants

    static let sample = MockTodayRepository(snapshot: .sample)
    static let restDay = MockTodayRepository(snapshot: .restDay)
    static let noHistory = MockTodayRepository(snapshot: .noHistory)
    static let allRest = MockTodayRepository(snapshot: .allRest)
    static let failing = MockTodayRepository(snapshot: nil)
}

extension TodaySnapshot {
    static let sampleWorkoutID = UUID()

    static let sampleWeek: [WeekDayCell] = [
        WeekDayCell(index: 0, dayLetter: "M", label: "Chest&Tris", state: .done),
        WeekDayCell(index: 1, dayLetter: "T", label: "Back&Bis", state: .done),
        WeekDayCell(index: 2, dayLetter: "W", label: "Legs", state: .done),
        WeekDayCell(index: 3, dayLetter: "T", label: "Shoulders", state: .today),
        WeekDayCell(index: 4, dayLetter: "F", label: "Arms·finisher", state: .plan),
        WeekDayCell(index: 5, dayLetter: "S", label: "Rest", state: .rest),
        WeekDayCell(index: 6, dayLetter: "S", label: "Rest", state: .rest),
    ]

    static let sampleCard = TodayWorkoutCard(
        workoutID: sampleWorkoutID,
        programLabel: "PPL", week: 4, day: 23,
        name: "Chest & Tris", exerciseCount: 7, est: "~60 min")

    static let sampleRecap = SessionRecap(
        sessionID: UUID(), name: "Legs", subline: "71M · 18.7K KG · +1 PR")

    static let sample = TodaySnapshot(
        dateEyebrow: "WED · MAY 28", greetingName: "Alex", streak: 27,
        today: sampleCard, week: sampleWeek, yesterday: sampleRecap)

    static let restDay = TodaySnapshot(
        dateEyebrow: "SAT · MAY 31", greetingName: "Alex", streak: 27,
        today: nil, week: sampleWeek, yesterday: sampleRecap)

    static let noHistory = TodaySnapshot(
        dateEyebrow: "WED · MAY 28", greetingName: "Alex", streak: 0,
        today: sampleCard, week: sampleWeek, yesterday: nil)

    static let allRest = TodaySnapshot(
        dateEyebrow: "SUN · JUN 01", greetingName: "Alex", streak: 0,
        today: nil,
        week: (0..<7).map {
            WeekDayCell(index: $0, dayLetter: "R", label: "Rest", state: .rest)
        },
        yesterday: nil)
}
