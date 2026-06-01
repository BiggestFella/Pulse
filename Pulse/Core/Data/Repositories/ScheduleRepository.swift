import Foundation

/// The Plan calendar. `setPlan(nil, on:)` clears a day.
protocol ScheduleRepository {
    func plan(for date: Date) async throws -> DayPlan?
    func upcoming(from date: Date, days: Int) async throws -> [(date: Date, plan: DayPlan)]
    func setPlan(_ plan: DayPlan?, on date: Date) async throws
}
