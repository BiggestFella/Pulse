import Foundation

/// Folder writes for the Folder builder. Folders have no domain model in the
/// data layer yet (see `LibraryRepository`), so this carries the create intent
/// as name + brand-color token. The real implementation lands with the folder
/// data model in a future ticket; the builder consumes it via the mock.
protocol FolderRepository {
    func saveFolder(name: String, colorToken: FolderColor) async throws
}
