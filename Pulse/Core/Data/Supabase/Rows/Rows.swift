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

struct FolderRecord: Codable {
    let id: UUID
    let parentFolderId: UUID?   // parent_folder_id
    let name: String
    let colorToken: String      // color_token
    func toModel() -> Folder {
        Folder(id: id, name: name,
               color: FolderColor(rawValue: colorToken) ?? .default,
               parentID: parentFolderId)
    }
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
    let rir: Int?    // nullable; legacy rows (pre-0006) decode to nil
    func toModel() -> SessionSet {
        SessionSet(id: id, exerciseID: exerciseId, variationID: variationId,
                   order: order, reps: reps, weight: weight,
                   type: SetType(rawValue: type) ?? .working, rir: rir)
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

// MARK: - Workout / Program reads (hydrated graph)
//
// Decoded from the nested embed
//   programs(*, workouts(*, workout_exercises(*, exercises(*, variations(*)), set_specs(*))))
// One round-trip → full domain graph. Embedded relations come back unordered, so
// each `toModel()` sorts children by their `"order"` column to mirror the mocks.

struct SetSpecRow: Codable {
    let id: UUID
    let reps: Int
    let rir: Int
    let type: String
    let order: Int
    func toModel() -> SetSpec {
        SetSpec(id: id, reps: reps, rir: rir, type: SetType(rawValue: type) ?? .working)
    }
}

struct WorkoutExerciseRow: Codable {
    let id: UUID
    let exerciseId: UUID
    let variationId: UUID?
    let supersetGroup: String?
    let order: Int
    let exercises: ExerciseRow?       // embed: exercises(*,variations(*)) — to-one parent
    let setSpecs: [SetSpecRow]?        // embed: set_specs(*)

    /// `nil` when the parent exercise embed is missing (FK gap) — the caller drops it.
    func toModel() -> WorkoutExercise? {
        guard let exercise = exercises?.toModel() else { return nil }
        return WorkoutExercise(
            id: id, exercise: exercise, variationID: variationId,
            supersetGroup: supersetGroup,
            sets: (setSpecs ?? []).sorted { $0.order < $1.order }.map { $0.toModel() })
    }
}

struct WorkoutRow: Codable {
    let id: UUID
    let name: String
    let weekday: Int?
    let order: Int
    let workoutExercises: [WorkoutExerciseRow]?   // embed: workout_exercises(...)
    func toModel() -> Workout {
        Workout(id: id, name: name, weekday: weekday, order: order,
                exercises: (workoutExercises ?? [])
                    .sorted { $0.order < $1.order }
                    .compactMap { $0.toModel() })
    }
}

struct ProgramRow: Codable {
    let id: UUID
    let name: String
    let weeks: Int
    let isActive: Bool
    let workouts: [WorkoutRow]?   // embed: workouts(...)
    func toModel() -> Program {
        Program(id: id, name: name, weeks: weeks, isActive: isActive,
                workouts: (workouts ?? []).sorted { $0.order < $1.order }.map { $0.toModel() })
    }
}
