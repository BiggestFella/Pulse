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
