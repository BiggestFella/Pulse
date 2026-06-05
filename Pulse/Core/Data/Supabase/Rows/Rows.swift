import Foundation

/// Codable row DTOs mirroring the Postgres tables + embedded selects. Decoded with
/// `SupabaseDecoding.decoder` (snake_case → camelCase), then mapped to domain models.
/// One file for now; split if it grows.

struct VariationRow: Codable {
    let id: UUID
    let name: String
    let equipment: String?
    func toModel() -> Variation { Variation(id: id, name: name, equipment: equipment) }
}

struct ExerciseRow: Codable {
    let id: UUID
    let name: String
    let muscleGroup: String          // muscle_group
    let defaultVariationId: UUID?    // default_variation_id
    let variations: [VariationRow]?  // embed: variations(*)

    func toModel() -> Exercise {
        Exercise(id: id,
                 name: name,
                 muscleGroup: muscleGroup,
                 variations: (variations ?? []).map { $0.toModel() },
                 defaultVariationID: defaultVariationId)
    }
}

// MARK: - Session reads

struct SessionSetReadRow: Codable {
    let id: UUID
    let exerciseId: UUID
    let variationId: UUID?
    let reps: Int
    let weight: Double
    let type: String
    let order: Int
    func toModel() -> SessionSet {
        SessionSet(id: id, exerciseID: exerciseId, variationID: variationId,
                   order: order, reps: reps, weight: weight, type: SetType(rawValue: type) ?? .working)
    }
}

struct SessionReadRow: Codable {
    let id: UUID
    let workoutId: UUID
    let startedAt: Date
    let endedAt: Date?
    let sessionSets: [SessionSetReadRow]?   // embed: session_sets(*)
    func toModel() -> WorkoutSession {
        WorkoutSession(id: id, workoutID: workoutId, startedAt: startedAt, endedAt: endedAt,
                       sets: (sessionSets ?? []).map { $0.toModel() }.sorted { $0.order < $1.order })
    }
}

// MARK: - Workout / Program reads (shallow — enough for History name + program membership)

struct WorkoutReadRow: Codable {
    let id: UUID
    let name: String
    let weekday: Int?
    let order: Int
    func toModel() -> Workout {
        Workout(id: id, name: name, weekday: weekday, order: order, exercises: [])
    }
}

struct ProgramReadRow: Codable {
    let id: UUID
    let name: String
    let weeks: Int
    let isActive: Bool
    let workouts: [WorkoutReadRow]?   // embed: workouts(*)
    func toModel() -> Program {
        Program(id: id, name: name, weeks: weeks, isActive: isActive,
                workouts: (workouts ?? []).map { $0.toModel() })
    }
}
