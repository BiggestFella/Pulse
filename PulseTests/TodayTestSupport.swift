import Foundation
@testable import Pulse

/// Shared helpers for the Today tests after the BAK-24 migration: the model now
/// composes a snapshot from the in-memory repositories (one mock world), so tests
/// build a `MockStore` + a pinned `now` rather than canned `TodaySnapshot`s.
@MainActor
enum TodayTestSupport {
    /// Monday-first Gregorian, matching `SampleData` day boundaries.
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }()

    /// Most recent Monday on or before today (Gregorian weekday 2). Monday is
    /// `SampleData`'s `Push` day, so today's card is deterministically `Push`, and
    /// it stays within the current/last week the sample schedule covers.
    static func trainingDay(from date: Date = .now) -> Date {
        snap(from: date, weekdays: [2], step: -1)
    }

    /// Soonest rest weekday on or after today — today's card composes to nil.
    static func restDay(from date: Date = .now) -> Date {
        snap(from: date, weekdays: [1, 3, 5, 7], step: 1) // Sun/Tue/Thu/Sat
    }

    static func model(store: MockStore = MockStore(),
                      now: Date,
                      onStartWorkout: @escaping (UUID) -> Void = { _ in },
                      onOpenSession: @escaping (UUID) -> Void = { _ in }) -> TodayModel {
        TodayModel(programs: InMemoryProgramRepository(store: store),
                   workouts: InMemoryWorkoutRepository(store: store),
                   stats: InMemoryStatsRepository(store: store),
                   schedule: InMemoryScheduleRepository(store: store),
                   sessions: InMemorySessionRepository(store: store),
                   user: InMemoryUserRepository(),
                   now: now,
                   onStartWorkout: onStartWorkout,
                   onOpenSession: onOpenSession)
    }

    private static func snap(from date: Date, weekdays: Set<Int>, step: Int) -> Date {
        var day = calendar.startOfDay(for: date)
        for _ in 0..<7 {
            if weekdays.contains(calendar.component(.weekday, from: day)) { return day }
            day = calendar.date(byAdding: .day, value: step, to: day)!
        }
        return calendar.startOfDay(for: date)
    }
}
