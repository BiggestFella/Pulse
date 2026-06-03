import Foundation

/// In-memory `FolderRepository` for the prototype. Captures created folders so
/// builder model tests can assert on the write. A `shouldThrow` flag drives the
/// builder's save-failure path.
@MainActor
final class InMemoryFolderRepository: FolderRepository {
    struct Saved: Equatable { var name: String; var color: FolderColor }
    private(set) var saved: [Saved] = []
    var shouldThrow: Bool

    init(shouldThrow: Bool = false) { self.shouldThrow = shouldThrow }

    func saveFolder(name: String, colorToken: FolderColor) async throws {
        if shouldThrow { throw RepositoryError.forced }
        saved.append(Saved(name: name, color: colorToken))
    }
}
