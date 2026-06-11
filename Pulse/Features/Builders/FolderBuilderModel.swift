import Foundation
import Observation

@MainActor
@Observable
final class FolderBuilderModel {
    var name: String = "New folder"
    var colorToken: FolderColor = .default
    var parentID: Folder.ID? = nil
    var saveState: SaveState = .idle

    private let folderRepo: any FolderRepository

    init(folders: any FolderRepository, parentID: Folder.ID? = nil) {
        self.folderRepo = folders
        self.parentID = parentID
    }

    func select(color: FolderColor) { colorToken = color }

    func save() async {
        saveState = .saving
        do {
            _ = try await folderRepo.createFolder(name: name, color: colorToken, parentID: parentID)
            saveState = .saved
        } catch {
            saveState = .error("Couldn't create folder.")
        }
    }
}
