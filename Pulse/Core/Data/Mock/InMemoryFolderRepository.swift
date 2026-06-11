import Foundation

/// In-memory `FolderRepository` over a shared `MockStore`. Mirrors the live
/// repository's semantics: arbitrary-depth tree, cycle-guarded moves, and
/// cascade delete of a folder's sub-folders/workouts/programs. `shouldThrow`
/// drives the builder's save-failure path.
@MainActor
struct InMemoryFolderRepository: FolderRepository {
    let store: MockStore
    var shouldThrow: Bool

    init(store: MockStore, shouldThrow: Bool = false) {
        self.store = store
        self.shouldThrow = shouldThrow
    }

    init(shouldThrow: Bool = false) {
        self.init(store: MockStore(seeded: false), shouldThrow: shouldThrow)
    }

    private func gate() async throws {
        try await store.gate()
        if shouldThrow { throw RepositoryError.forced }
    }

    func contents(of parentID: Folder.ID?) async throws -> FolderContents {
        try await gate()
        let folders = store.folders.filter { $0.parentID == parentID }
        let workouts = store.allWorkouts.filter { store.workoutFolderID[$0.id] == parentID }
        let programs = store.programs.filter { store.programFolderID[$0.id] == parentID }
        return FolderContents(folders: folders, workouts: workouts, programs: programs)
    }

    func createFolder(name: String, color: FolderColor, parentID: Folder.ID?) async throws -> Folder {
        try await gate()
        let folder = Folder(id: UUID(), name: name, color: color, parentID: parentID)
        store.folders.append(folder)
        return folder
    }

    func renameFolder(id: Folder.ID, name: String, color: FolderColor) async throws {
        try await gate()
        guard let i = store.folders.firstIndex(where: { $0.id == id }) else { throw RepositoryError.notFound }
        store.folders[i].name = name
        store.folders[i].color = color
    }

    func moveFolder(id: Folder.ID, toParent newParent: Folder.ID?) async throws {
        try await gate()
        guard let i = store.folders.firstIndex(where: { $0.id == id }) else { throw RepositoryError.notFound }
        if let newParent, isDescendant(newParent, of: id) || newParent == id {
            throw RepositoryError.forced // cycle (no dedicated RepositoryError case yet)
        }
        store.folders[i].parentID = newParent
    }

    func moveWorkout(id: Workout.ID, toFolder: Folder.ID?) async throws {
        try await gate()
        if let toFolder { store.workoutFolderID[id] = toFolder }
        else { store.workoutFolderID[id] = nil }
    }

    func moveProgram(id: Program.ID, toFolder: Folder.ID?) async throws {
        try await gate()
        if let toFolder { store.programFolderID[id] = toFolder }
        else { store.programFolderID[id] = nil }
    }

    func deleteFolder(id: Folder.ID) async throws {
        try await gate()
        let subtree = subtreeIDs(of: id)
        let doomedWorkouts = Set(store.workoutFolderID.filter { subtree.contains($0.value) }.keys)
        let doomedPrograms = Set(store.programFolderID.filter { subtree.contains($0.value) }.keys)
        for pIdx in store.programs.indices {
            store.programs[pIdx].workouts.removeAll { doomedWorkouts.contains($0.id) }
        }
        store.programs.removeAll { doomedPrograms.contains($0.id) }
        store.workoutFolderID = store.workoutFolderID.filter { !subtree.contains($0.value) }
        store.programFolderID = store.programFolderID.filter { !subtree.contains($0.value) }
        store.folders.removeAll { subtree.contains($0.id) }
    }

    // MARK: - Tree helpers

    private func subtreeIDs(of root: Folder.ID) -> Set<Folder.ID> {
        var result: Set<Folder.ID> = [root]
        var frontier = [root]
        while let current = frontier.popLast() {
            for child in store.folders where child.parentID == current {
                if result.insert(child.id).inserted { frontier.append(child.id) }
            }
        }
        return result
    }

    private func isDescendant(_ candidate: Folder.ID, of ancestor: Folder.ID) -> Bool {
        var seen: Set<Folder.ID> = []
        var current: Folder.ID? = candidate
        while let id = current, seen.insert(id).inserted {
            if id == ancestor { return true }
            current = store.folders.first { $0.id == id }?.parentID
        }
        return false
    }
}
