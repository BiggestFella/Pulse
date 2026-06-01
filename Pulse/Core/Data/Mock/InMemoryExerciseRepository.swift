import Foundation

@MainActor
struct InMemoryExerciseRepository: ExerciseRepository {
    let store: MockStore

    func fetchCatalog() async throws -> [Exercise] {
        try await store.gate(); return store.exercises
    }
    func fetchExercises(muscleGroup: String) async throws -> [Exercise] {
        try await store.gate()
        return store.exercises.filter { $0.muscleGroup == muscleGroup }
    }
    func fetchExercise(id: Exercise.ID) async throws -> Exercise? {
        try await store.gate(); return store.exercises.first { $0.id == id }
    }
    func alternatives(for exerciseID: Exercise.ID) async throws -> [Exercise] {
        try await store.gate()
        guard let base = store.exercises.first(where: { $0.id == exerciseID }) else { return [] }
        return store.exercises.filter { $0.muscleGroup == base.muscleGroup && $0.id != exerciseID }
    }
    func saveExercise(_ exercise: Exercise) async throws -> Exercise {
        try await store.gate()
        if let i = store.exercises.firstIndex(where: { $0.id == exercise.id }) {
            store.exercises[i] = exercise
        } else {
            store.exercises.append(exercise)
        }
        return exercise
    }
}
