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
            try await folderRepo.saveFolder(name: name, colorToken: colorToken)
            saveState = .saved
        } catch {
            saveState = .error("Couldn't create folder.")
        }
    }
}
