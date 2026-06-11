import SwiftUI

/// Renders a folder's three child groups (folders, workouts, programs) with the
/// per-row Move/Delete actions. Used by both the Library root and folder detail.
struct FolderContentsSection: View {
    let folders: [LibraryFolder]
    let workouts: [Workout]
    let programs: [Program]
    let onOpenFolder: (UUID) -> Void
    let onOpenWorkout: (Workout) -> Void
    let onOpenProgram: (Program) -> Void
    let onMove: (LibraryItemRef) -> Void
    let onDelete: (LibraryFolder) -> Void
    @Environment(Theme.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !folders.isEmpty {
                StatLabel("FOLDERS · \(folders.count)")
                ForEach(folders) { folder in
                    FolderRow(folder: folder) { onOpenFolder(folder.id) }
                        .contextMenu {
                            Button("Move to folder…") { onMove(.folder(folder.id)) }
                            Button("Delete", role: .destructive) { onDelete(folder) }
                        }
                }
            }
            if !programs.isEmpty {
                StatLabel("PROGRAMS · \(programs.count)").padding(.top, 8)
                ForEach(programs) { program in
                    LibraryProgramRow(program: program) { onOpenProgram(program) }
                        .contextMenu {
                            Button("Move to folder…") { onMove(.program(program.id)) }
                        }
                }
            }
            if !workouts.isEmpty {
                StatLabel("WORKOUTS · \(workouts.count)").padding(.top, 8)
                ForEach(workouts) { workout in
                    LibraryWorkoutRow(workout: workout) { onOpenWorkout(workout) }
                        .contextMenu {
                            Button("Move to folder…") { onMove(.workout(workout.id)) }
                        }
                }
            }
        }
    }
}

/// Identifies an item the user is moving, for the Move sheet.
enum LibraryItemRef: Equatable {
    case folder(UUID)
    case workout(UUID)
    case program(UUID)
}

extension LibraryItemRef: Identifiable {
    var id: String {
        switch self {
        case .folder(let id):  return "folder-\(id)"
        case .workout(let id): return "workout-\(id)"
        case .program(let id): return "program-\(id)"
        }
    }
}
