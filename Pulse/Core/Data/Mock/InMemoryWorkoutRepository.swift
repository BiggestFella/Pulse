import Foundation

@MainActor
struct InMemoryWorkoutRepository: WorkoutRepository {
    let store: MockStore

    func fetchWorkouts() async throws -> [Workout] {
        try await store.gate(); return store.allWorkouts
    }
    func fetchWorkout(id: Workout.ID) async throws -> Workout? {
        try await store.gate(); return store.allWorkouts.first { $0.id == id }
    }
    func todaysWorkout(on date: Date) async throws -> Workout? {
        try await store.gate()
        let greg = SampleData.calendar.component(.weekday, from: date) // 1=Sun…7=Sat
        let appWeekday = ((greg + 5) % 7) + 1                          // Mon→1 … Sun→7
        return store.allWorkouts.first { $0.weekday == appWeekday }
    }
    func saveWorkout(_ workout: Workout) async throws -> Workout {
        try await store.gate()
        guard let pi = store.programs.firstIndex(where: { $0.isActive }) ??
                       store.programs.indices.first else {
            return workout
        }
        if let wi = store.programs[pi].workouts.firstIndex(where: { $0.id == workout.id }) {
            store.programs[pi].workouts[wi] = workout
        } else {
            store.programs[pi].workouts.append(workout)
        }
        return workout
    }
    func deleteWorkout(id: Workout.ID) async throws {
        try await store.gate()
        for pi in store.programs.indices {
            store.programs[pi].workouts.removeAll { $0.id == id }
        }
    }
}
