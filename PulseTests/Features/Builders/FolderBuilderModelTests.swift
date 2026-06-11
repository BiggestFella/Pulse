import XCTest
@testable import Pulse

@MainActor
final class FolderBuilderModelTests: XCTestCase {
    func testDefaults() {
        let model = FolderBuilderModel(folders: InMemoryFolderRepository())
        XCTAssertEqual(model.name, "New folder")
        XCTAssertEqual(model.colorToken, .blue)
    }

    func testSelectColorUpdatesToken() {
        let model = FolderBuilderModel(folders: InMemoryFolderRepository())
        model.select(color: .purple)
        XCTAssertEqual(model.colorToken, .purple)
    }

    func testSaveCreatesFolderWithNameAndColor() async {
        let repo = InMemoryFolderRepository()
        let model = FolderBuilderModel(folders: repo)
        model.name = "Cardio"
        model.select(color: .pink)
        await model.save()
        XCTAssertEqual(model.saveState, .saved)
        XCTAssertEqual(repo.store.folders.first?.name, "Cardio")
        XCTAssertEqual(repo.store.folders.first?.color, .pink)
    }

    func testSaveErrorWhenRepositoryThrows() async {
        let model = FolderBuilderModel(folders: InMemoryFolderRepository(shouldThrow: true))
        await model.save()
        if case .error = model.saveState { } else { XCTFail("expected .error") }
    }
}
