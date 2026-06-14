import Foundation

@MainActor
enum TodayWorkoutResolver {
    /// The hydrated workout to launch for `date`, or nil if today is rest/empty/done.
    static func workout(on date: Date, schedule: any ScheduleRepository,
                        workouts: any WorkoutRepository, calendar: Calendar) async throws -> Workout? {
        let day = calendar.startOfDay(for: date)
        let entry = try await schedule.plan(for: day)
        let all = try await workouts.fetchWorkouts()
        guard case let .workout(id)? = ScheduleResolver.plan(for: day, entry: entry,
                                                             workouts: all, calendar: calendar)
        else { return nil }
        return try await workouts.fetchWorkout(id: id)
    }
}
