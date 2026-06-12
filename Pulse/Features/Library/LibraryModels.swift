import Foundation

/// Library filter chips.
enum LibraryFilter: String, CaseIterable {
    case all, workouts, folders, exercises, programs
    var label: String {
        switch self {
        case .all: return "All"
        case .workouts: return "Workouts"
        case .folders: return "Folders"
        case .exercises: return "Exercises"
        case .programs: return "Programs"
        }
    }
}

/// A folder row projection for the Library.
struct LibraryFolder: Identifiable, Equatable {
    let id: UUID
    let name: String
    let sub: String
    let color: FolderColor
}

/// A recent-workout row projection.
struct WorkoutSummary: Identifiable, Equatable {
    let id: String
    let name: String
    let sub: String
}

/// One catalog exercise row (projected from a `Core/Models` `Exercise`).
struct CatalogExercise: Identifiable, Equatable {
    let id: String
    let name: String
    let equipment: String
    let variationCount: Int
    let hasPR: Bool

    var subline: String {
        let variations = variationCount > 0
            ? "\(variationCount) variation\(variationCount == 1 ? "" : "s")"
            : ""
        switch (equipment.isEmpty, variations.isEmpty) {
        case (false, false): return "\(equipment) · \(variations)"
        case (false, true):  return equipment
        case (true, false):  return variations
        case (true, true):   return ""
        }
    }
}

/// Catalog exercises grouped under one muscle.
struct MuscleGroupCatalog: Identifiable, Equatable {
    var id: String { muscle }
    let muscle: String
    let items: [CatalogExercise]
}

/// A folder pending deletion confirmation, with the count of items directly inside it.
struct PendingFolderDelete: Equatable {
    let folder: LibraryFolder
    let itemCount: Int
}

/// Confirmation copy for deleting a non-empty folder.
func deleteMessage(_ pending: PendingFolderDelete?) -> String {
    guard let pending else { return "" }
    let n = pending.itemCount
    return "Delete \"\(pending.folder.name)\" and the \(n) item\(n == 1 ? "" : "s") inside it? This can't be undone."
}
