import Foundation

/// Library folders — a generic container tree (workouts, programs, sub-folders).
/// `contents(of:)` returns the direct children of a folder (`nil` = Library root).
/// Reads/writes are owner-scoped (RLS on the live path).
protocol FolderRepository {
    func contents(of parentID: Folder.ID?) async throws -> FolderContents
    func createFolder(name: String, color: FolderColor, parentID: Folder.ID?) async throws -> Folder
    func renameFolder(id: Folder.ID, name: String, color: FolderColor) async throws
    /// Reparent a folder. Throws if `newParent` is the folder itself or a descendant (cycle).
    func moveFolder(id: Folder.ID, toParent newParent: Folder.ID?) async throws
    func moveWorkout(id: Workout.ID, toFolder: Folder.ID?) async throws
    func moveProgram(id: Program.ID, toFolder: Folder.ID?) async throws
    /// Delete a folder; its sub-folders, workouts, and programs cascade-delete.
    func deleteFolder(id: Folder.ID) async throws
}
