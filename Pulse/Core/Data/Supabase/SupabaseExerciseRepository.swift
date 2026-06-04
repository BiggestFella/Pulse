import Foundation
import Supabase

/// Exercise catalog reads. The catalog is global (RLS: readable by all), so no
/// user scoping. Variations come back via the embedded select.
struct SupabaseExerciseRepository: ExerciseRepository {
    let client: SupabaseClient

    func fetchCatalog() async throws -> [Exercise] {
        let rows: [ExerciseRow] = try await client
            .from("exercises").select("*,variations(*)").order("name")
            .execute().value
        return rows.map { $0.toModel() }
    }

    func fetchExercises(muscleGroup: String) async throws -> [Exercise] {
        let rows: [ExerciseRow] = try await client
            .from("exercises").select("*,variations(*)")
            .eq("muscle_group", value: muscleGroup).order("name")
            .execute().value
        return rows.map { $0.toModel() }
    }

    func fetchExercise(id: Exercise.ID) async throws -> Exercise? {
        let rows: [ExerciseRow] = try await client
            .from("exercises").select("*,variations(*)")
            .eq("id", value: id.uuidString).limit(1)
            .execute().value
        return rows.first?.toModel()
    }

    func alternatives(for exerciseID: Exercise.ID) async throws -> [Exercise] {
        guard let exercise = try await fetchExercise(id: exerciseID) else { return [] }
        return try await fetchExercises(muscleGroup: exercise.muscleGroup)
            .filter { $0.id != exerciseID }
    }

    func saveExercise(_ exercise: Exercise) async throws -> Exercise {
        // Catalog is curated server-side for v1; not written from the app.
        throw RepositoryError.notImplemented
    }
}
