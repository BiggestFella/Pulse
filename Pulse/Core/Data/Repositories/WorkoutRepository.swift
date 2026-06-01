import Foundation

/// Workouts (routines). `fetchWorkout(id:)` returns the hydrated graph
/// (exercises → embedded Exercise + chosen variation → ordered SetSpecs).
protocol WorkoutRepository {
    func fetchWorkouts() async throws -> [Workout]
    func fetchWorkout(id: Workout.ID) async throws -> Workout?
    func todaysWorkout(on date: Date) async throws -> Workout?
    func saveWorkout(_ workout: Workout) async throws -> Workout
    func deleteWorkout(id: Workout.ID) async throws
}
