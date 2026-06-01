import Foundation

/// The exercise catalog and its variations.
protocol ExerciseRepository {
    func fetchCatalog() async throws -> [Exercise]
    func fetchExercises(muscleGroup: String) async throws -> [Exercise]
    func fetchExercise(id: Exercise.ID) async throws -> Exercise?
    /// Same-muscle-group alternatives for the swap sheet (excludes `exerciseID`).
    func alternatives(for exerciseID: Exercise.ID) async throws -> [Exercise]
    func saveExercise(_ exercise: Exercise) async throws -> Exercise
}
