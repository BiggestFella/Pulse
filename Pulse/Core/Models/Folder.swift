import Foundation

/// The six fixed brand swatches a folder can take. Hex is the source value;
/// `Theme` exposes the matching `Color` so views never read hex directly. The
/// raw value is what the `folders.color_token` column stores.
enum FolderColor: String, CaseIterable, Equatable {
    case blue, orange, teal, yellow, pink, purple

    static let `default`: FolderColor = .blue

    var hex: String {
        switch self {
        case .blue:   return "#26B6F6"
        case .orange: return "#FF6A1F"
        case .teal:   return "#00D9B8"
        case .yellow: return "#FFCC33"
        case .pink:   return "#FF4D6D"
        case .purple: return "#9B6BFF"
        }
    }
}

/// A Library folder. Tree membership is the parent pointer (`parentID == nil` =
/// top level). Folders hold workouts, programs, and sub-folders.
struct Folder: Identifiable, Equatable {
    let id: UUID
    var name: String
    var color: FolderColor
    var parentID: UUID?
}

/// A folder's direct children — the three child types the Library renders.
struct FolderContents: Equatable {
    var folders: [Folder]
    var workouts: [Workout]
    var programs: [Program]

    var isEmpty: Bool { folders.isEmpty && workouts.isEmpty && programs.isEmpty }
}
