import Foundation
import Observation

@MainActor
@Observable
final class FolderBuilderModel {
    var name: String = "New folder"
    var colorToken: FolderColor = .default
    var parentID: Folder.ID? = nil
    private(set) var editingFolderID: Folder.ID? = nil
    var saveState: SaveState = .idle

    private let folderRepo: any FolderRepository

    /// Create mode — a new folder parented at `parentID`.
    init(folders: any FolderRepository, parentID: Folder.ID? = nil) {
        self.folderRepo = folders
        self.parentID = parentID
    }

    /// Edit mode — seeded from an existing folder; `save()` renames it.
    init(folders: any FolderRepository, editing folder: Folder) {
        self.folderRepo = folders
        self.name = folder.name
        self.colorToken = folder.color
        self.editingFolderID = folder.id
    }

    var isEditing: Bool { editingFolderID != nil }

    func select(color: FolderColor) { colorToken = color }

    func save() async {
        saveState = .saving
        do {
            if let editingFolderID {
                try await folderRepo.renameFolder(id: editingFolderID, name: name, color: colorToken)
            } else {
                _ = try await folderRepo.createFolder(name: name, color: colorToken, parentID: parentID)
            }
            saveState = .saved
        } catch {
            saveState = .error(isEditing ? "Couldn't save changes." : "Couldn't create folder.")
        }
    }
}
