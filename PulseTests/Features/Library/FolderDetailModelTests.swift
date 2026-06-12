import XCTest
@testable import Pulse

@MainActor
final class FolderDetailModelTests: XCTestCase {
    func testRequestDeleteEmptyChildDeletesImmediately() async {
        let store = MockStore(seeded: false)
        let repo = InMemoryFolderRepository(store: store)
        let parent = try! await repo.createFolder(name: "Parent", color: .blue, parentID: nil)
        let child = try! await repo.createFolder(name: "Child", color: .teal, parentID: parent.id)
        let model = FolderDetailModel(folderID: parent.id, title: "Parent", folders: repo)
        await model.load()
        await model.requestDelete(LibraryModel.project(child))
        XCTAssertNil(model.pendingDelete)
        XCTAssertFalse(store.folders.contains { $0.id == child.id })
    }

    func testRequestDeleteNonEmptyChildPromptsThenConfirms() async {
        let store = MockStore(seeded: false)
        let repo = InMemoryFolderRepository(store: store)
        let parent = try! await repo.createFolder(name: "Parent", color: .blue, parentID: nil)
        let child = try! await repo.createFolder(name: "Child", color: .teal, parentID: parent.id)
        _ = try! await repo.createFolder(name: "Grandchild", color: .pink, parentID: child.id)
        let model = FolderDetailModel(folderID: parent.id, title: "Parent", folders: repo)
        await model.load()
        await model.requestDelete(LibraryModel.project(child))
        XCTAssertEqual(model.pendingDelete?.itemCount, 1)
        XCTAssertTrue(store.folders.contains { $0.id == child.id })
        await model.confirmDelete()
        XCTAssertNil(model.pendingDelete)
        XCTAssertFalse(store.folders.contains { $0.id == child.id })
    }
}
