import Foundation
@testable import Pulse

enum FakePlanError: Error { case boom }

/// Configurable fake ScheduleRepository for PlanModel tests.
/// Keyed by day-of-month within the model's reference month.
@MainActor
final class FakeScheduleRepository: ScheduleRepository {
    var plansByDay: [Int: DayPlan]
    var calendar: Calendar
    var shouldThrow = false

    init(plansByDay: [Int: DayPlan], calendar: Calendar) {
        self.plansByDay = plansByDay
        self.calendar = calendar
    }

    private func day(of date: Date) -> Int { calendar.component(.day, from: date) }

    func plan(for date: Date) async throws -> DayPlan? {
        if shouldThrow { throw FakePlanError.boom }
        return plansByDay[day(of: date)]
    }

    func upcoming(from date: Date, days: Int) async throws -> [(date: Date, plan: DayPlan)] {
        if shouldThrow { throw FakePlanError.boom }
        var out: [(date: Date, plan: DayPlan)] = []
        for offset in 0..<days {
            let d = calendar.date(byAdding: .day, value: offset, to: date)!
            if let p = plansByDay[day(of: d)] { out.append((d, p)) }
        }
        return out
    }

    func setPlan(_ plan: DayPlan?, on date: Date) async throws {
        if shouldThrow { throw FakePlanError.boom }
        if let plan { plansByDay[day(of: date)] = plan }
        else { plansByDay[day(of: date)] = nil }
    }
}

/// Minimal fake WorkoutRepository. Only `fetchWorkouts()` is exercised by PlanModel;
/// the rest satisfy the protocol.
@MainActor
final class FakeWorkoutRepository: WorkoutRepository {
    var workouts: [Workout]
    init(workouts: [Workout]) { self.workouts = workouts }

    func fetchWorkouts() async throws -> [Workout] { workouts }
    func fetchWorkout(id: Workout.ID) async throws -> Workout? { workouts.first { $0.id == id } }
    func todaysWorkout(on date: Date) async throws -> Workout? { nil }
    func saveWorkout(_ workout: Workout) async throws -> Workout { workout }
    func deleteWorkout(id: Workout.ID) async throws {}
}
