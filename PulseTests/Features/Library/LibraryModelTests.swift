import XCTest
@testable import Pulse

@MainActor
final class LibraryModelTests: XCTestCase {
    private func makeModel(store: MockStore) -> LibraryModel {
        LibraryModel(folders: InMemoryFolderRepository(store: store),
                     sessionRepo: InMemorySessionRepository(store: store),
                     workoutRepo: InMemoryWorkoutRepository(store: store),
                     exerciseRepo: InMemoryExerciseRepository(store: store),
                     prRepo: InMemoryPRRepository(store: store))
    }

    func testLoadSurfacesTopLevelFolders() async {
        let store = MockStore(seeded: false)
        let repo = InMemoryFolderRepository(store: store)
        _ = try? await repo.createFolder(name: "Cardio", color: .pink, parentID: nil)
        let model = makeModel(store: store)
        await model.load()
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.folders.map(\.name), ["Cardio"])
    }

    func testRecentWorkoutsJoinSessionWithWorkoutName() async {
        let store = MockStore(seeded: true)            // has a program with named workouts + sessions
        let model = makeModel(store: store)
        await model.load()
        // Each recent row's name resolves from the workout the session referenced.
        let sessions = try! await InMemorySessionRepository(store: store).fetchSessions(limit: 10)
        XCTAssertEqual(model.recentWorkouts.count, min(sessions.count, 10))
        XCTAssertFalse(model.recentWorkouts.contains { $0.name.isEmpty })
    }

    func testEmptyStoreYieldsEmptyFoldersAndRecents() async {
        let store = MockStore(seeded: false)
        let model = makeModel(store: store)
        await model.load()
        XCTAssertTrue(model.folders.isEmpty)
        XCTAssertTrue(model.recentWorkouts.isEmpty)
    }

    func testSelectUpdatesFilter() {
        let model = makeModel(store: MockStore(seeded: false))
        model.select(.exercises)
        XCTAssertEqual(model.selectedFilter, .exercises)
    }

    func testPresentAndDismissCreate() {
        let model = makeModel(store: MockStore(seeded: false))
        model.presentCreate()
        XCTAssertTrue(model.isCreateSheetPresented)
        model.dismissCreate()
        XCTAssertFalse(model.isCreateSheetPresented)
    }

    func testIsAllEmptyTrueOnEmptyStore() async {
        let model = makeModel(store: MockStore(seeded: false))
        await model.load()
        XCTAssertTrue(model.isAllEmpty)
    }

    func testLoadFailureSetsErrorState() async {
        let store = MockStore(seeded: true)
        store.forceError = true
        let model = makeModel(store: store)
        await model.load()
        XCTAssertEqual(model.loadState, .error)
    }

    func testRetryRecoversAfterError() async {
        let store = MockStore(seeded: true)
        store.forceError = true
        let model = makeModel(store: store)
        await model.load()
        XCTAssertEqual(model.loadState, .error)
        store.forceError = false
        await model.retry()
        XCTAssertEqual(model.loadState, .loaded)
    }
}
