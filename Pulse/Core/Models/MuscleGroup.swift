import Foundation

/// A workout's muscle Target. Raw values match the catalog's `muscle_group`
/// strings (seeded in 0005/0006) so a workout's targets line up with
/// `Exercise.muscleGroup` for filtering.
enum MuscleGroup: String, Codable, CaseIterable, Identifiable, Equatable {
    case legs = "Legs"
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case biceps = "Biceps"
    case triceps = "Triceps"
    case other = "Other"

    var id: String { rawValue }

    /// Map a catalog `muscle_group` string to a case; anything outside the set
    /// (future catalog additions) falls back to `.other`.
    static func from(catalog raw: String) -> MuscleGroup {
        MuscleGroup(rawValue: raw) ?? .other
    }
}
