import Foundation
import Supabase

/// Live folder repository. The folder tree is owner-scoped by RLS (`own_folders`).
/// `contents(of:)` reads the direct children of a folder; lightweight selects
/// (no embeds) are used for workouts/programs since the Library only lists names.
struct SupabaseFolderRepository: FolderRepository {
    let client: SupabaseClient

    func contents(of parentID: Folder.ID?) async throws -> FolderContents {
        let folderRows: [FolderRecord] = try await childQuery("folders", column: "parent_folder_id", parentID)
            .order("order").execute().value
        let workoutRows: [WorkoutRow] = try await childQuery("workouts", column: "folder_id", parentID)
            .order("order").execute().value
        let programRows: [ProgramRow] = try await childQuery("programs", column: "folder_id", parentID)
            .order("created_at").execute().value
        return FolderContents(
            folders: folderRows.map { $0.toModel() },
            workouts: workoutRows.map { $0.toModel() },
            programs: programRows.map { $0.toModel() })
    }

    /// `select("*")` filtered to children of `parentID` — `is null` at the root.
    private func childQuery(_ table: String, column: String, _ parentID: Folder.ID?)
        -> PostgrestFilterBuilder {
        let base = client.from(table).select("*")
        if let parentID { return base.eq(column, value: parentID.uuidString) }
        return base.is(column, value: nil)
    }

    func createFolder(name: String, color: FolderColor, parentID: Folder.ID?) async throws -> Folder {
        let userID = try await client.auth.session.user.id
        let id = UUID()
        try await client.from("folders").insert(FolderWriteRow(
            id: id, userId: userID, parentFolderId: parentID,
            name: name, colorToken: color.rawValue)).execute()
        return Folder(id: id, name: name, color: color, parentID: parentID)
    }

    func renameFolder(id: Folder.ID, name: String, color: FolderColor) async throws {
        struct Rename: Encodable { let name: String; let colorToken: String }
        try await client.from("folders")
            .update(Rename(name: name, colorToken: color.rawValue))
            .eq("id", value: id.uuidString).execute()
    }

    func moveFolder(id: Folder.ID, toParent newParent: Folder.ID?) async throws {
        if let newParent {
            if newParent == id { throw RepositoryError.forced }
            let all = try await allFolders()
            let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
            var cursor: Folder.ID? = newParent
            while let c = cursor {
                if c == id { throw RepositoryError.forced }   // cycle
                cursor = byID[c]?.parentID
            }
        }
        struct Reparent: Encodable {
            let parentFolderId: Folder.ID?
            enum CodingKeys: String, CodingKey { case parentFolderId }
            func encode(to e: Encoder) throws {
                var c = e.container(keyedBy: CodingKeys.self)
                try c.encode(parentFolderId, forKey: .parentFolderId)   // null when nil
            }
        }
        try await client.from("folders")
            .update(Reparent(parentFolderId: newParent))
            .eq("id", value: id.uuidString).execute()
    }

    func moveWorkout(id: Workout.ID, toFolder: Folder.ID?) async throws {
        try await client.from("workouts")
            .update(FolderIDUpdate(folderId: toFolder)).eq("id", value: id.uuidString).execute()
    }

    func moveProgram(id: Program.ID, toFolder: Folder.ID?) async throws {
        try await client.from("programs")
            .update(FolderIDUpdate(folderId: toFolder)).eq("id", value: id.uuidString).execute()
    }

    func deleteFolder(id: Folder.ID) async throws {
        try await client.from("folders").delete().eq("id", value: id.uuidString).execute()
    }

    private func allFolders() async throws -> [Folder] {
        let rows: [FolderRecord] = try await client.from("folders").select("*").execute().value
        return rows.map { $0.toModel() }
    }
}
