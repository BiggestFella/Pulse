import XCTest
@testable import Pulse

@MainActor
final class InMemoryFolderRepositoryTests: XCTestCase {
    private func makeRepo() -> (InMemoryFolderRepository, MockStore) {
        let store = MockStore(seeded: false)
        return (InMemoryFolderRepository(store: store), store)
    }

    func testCreateFolderAppearsInRootContents() async throws {
        let (repo, _) = makeRepo()
        let f = try await repo.createFolder(name: "Cardio", color: .pink, parentID: nil)
        let root = try await repo.contents(of: nil)
        XCTAssertEqual(root.folders.map(\.id), [f.id])
        XCTAssertEqual(f.name, "Cardio")
        XCTAssertEqual(f.color, .pink)
        XCTAssertNil(f.parentID)
    }

    func testNestedFolderShowsUnderItsParentNotRoot() async throws {
        let (repo, _) = makeRepo()
        let parent = try await repo.createFolder(name: "Strength", color: .blue, parentID: nil)
        let child = try await repo.createFolder(name: "Push", color: .teal, parentID: parent.id)
        let root = try await repo.contents(of: nil)
        XCTAssertEqual(root.folders.map(\.id), [parent.id])
        let inParent = try await repo.contents(of: parent.id)
        XCTAssertEqual(inParent.folders.map(\.id), [child.id])
    }

    func testMoveWorkoutIntoAndOutOfFolder() async throws {
        let store = MockStore(seeded: true)
        let repo = InMemoryFolderRepository(store: store)
        let folder = try await repo.createFolder(name: "A", color: .blue, parentID: nil)
        let w = store.allWorkouts.first!
        try await repo.moveWorkout(id: w.id, toFolder: folder.id)
        let folderContents = try await repo.contents(of: folder.id)
        XCTAssertEqual(folderContents.workouts.map(\.id), [w.id])
        try await repo.moveWorkout(id: w.id, toFolder: nil)
        let folderContentsAfter = try await repo.contents(of: folder.id)
        let rootContents = try await repo.contents(of: nil)
        XCTAssertTrue(folderContentsAfter.workouts.isEmpty)
        XCTAssertTrue(rootContents.workouts.contains { $0.id == w.id })
    }

    func testMoveFolderIntoOwnDescendantThrows() async throws {
        let (repo, _) = makeRepo()
        let a = try await repo.createFolder(name: "A", color: .blue, parentID: nil)
        let b = try await repo.createFolder(name: "B", color: .blue, parentID: a.id)
        do {
            try await repo.moveFolder(id: a.id, toParent: b.id)
            XCTFail("expected cycle rejection")
        } catch { }
        let rootContents = try await repo.contents(of: nil)
        XCTAssertEqual(rootContents.folders.map(\.id), [a.id])
    }

    func testDeleteFolderCascadesSubtree() async throws {
        let store = MockStore(seeded: true)
        let repo = InMemoryFolderRepository(store: store)
        let parent = try await repo.createFolder(name: "P", color: .blue, parentID: nil)
        let child = try await repo.createFolder(name: "C", color: .blue, parentID: parent.id)
        let w = store.allWorkouts.first!
        try await repo.moveWorkout(id: w.id, toFolder: child.id)
        let programCountBefore = store.programs.count
        try await repo.deleteFolder(id: parent.id)
        let rootContents = try await repo.contents(of: nil)
        XCTAssertFalse(rootContents.folders.contains { $0.id == parent.id })
        XCTAssertFalse(store.folders.contains { $0.id == child.id })
        XCTAssertFalse(store.allWorkouts.contains { $0.id == w.id })
        XCTAssertEqual(store.programs.count, programCountBefore)
    }

    func testShouldThrowMakesCreateThrow() async {
        let store = MockStore(seeded: false)
        let repo = InMemoryFolderRepository(store: store, shouldThrow: true)
        do { _ = try await repo.createFolder(name: "x", color: .blue, parentID: nil); XCTFail() }
        catch { }
    }
}
