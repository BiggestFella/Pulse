import Foundation
import Observation

@MainActor
@Observable
final class FolderBuilderModel {
    var name: String = "New folder"
    var colorToken: FolderColor = .default
    var saveState: SaveState = .idle

    private let folderRepo: any FolderRepository

    init(folders: any FolderRepository) { self.folderRepo = folders }

    func select(color: FolderColor) { colorToken = color }

    func save() async {
        saveState = .saving
        do {
            _ = try await folderRepo.createFolder(name: name, color: colorToken, parentID: nil)
            saveState = .saved
        } catch {
            saveState = .error("Couldn't create folder.")
        }
    }
}
