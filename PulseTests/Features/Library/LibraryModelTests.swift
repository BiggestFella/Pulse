import XCTest
@testable import Pulse

@MainActor
final class LibraryModelTests: XCTestCase {
    private func model(libraryFail: Bool = false, libraryEmpty: Bool = false, store: MockStore) -> LibraryModel {
        LibraryModel(library: MockLibraryRepository(shouldFail: libraryFail, empty: libraryEmpty),
                     exerciseRepo: InMemoryExerciseRepository(store: store),
                     prRepo: InMemoryPRRepository(store: store))
    }

    func testDefaultFilterIsAll() {
        XCTAssertEqual(model(store: MockStore()).selectedFilter, .all)
    }

    func testInitialStateIsLoading() {
        XCTAssertEqual(model(store: MockStore()).loadState, .loading)
    }

    func testLoadPopulatesEverything() async {
        let m = model(store: MockStore())
        await m.load()
        XCTAssertEqual(m.loadState, .loaded)
        XCTAssertEqual(m.folders.count, 3)
        XCTAssertEqual(m.recentWorkouts.count, 3)
        XCTAssertEqual(m.catalog.first?.muscle, "Chest")
    }

    func testCatalogInMuscleFirstAppearanceOrder() async {
        let m = model(store: MockStore())
        await m.load()
        XCTAssertEqual(m.catalog.map(\.muscle), ["Chest", "Back", "Shoulders", "Legs", "Arms"])
    }

    func testCatalogMapsVariationsAndPR() async {
        let m = model(store: MockStore())
        await m.load()
        let chest = m.catalog.first { $0.muscle == "Chest" }
        let bench = chest?.items.first { $0.name == "Bench Press" }
        XCTAssertEqual(bench?.variationCount, 3)
        XCTAssertTrue(bench?.hasPR ?? false)              // bench is logged → has a PR
        let pushup = chest?.items.first { $0.name == "Push-Up" }
        XCTAssertEqual(pushup?.variationCount, 1)         // single-variation
    }

    func testFolderIsProgramFlag() async {
        let m = model(store: MockStore())
        await m.load()
        XCTAssertTrue(m.folders.first { $0.id == "ppl" }?.isProgram ?? false)
        XCTAssertFalse(m.folders.first { $0.id == "cardio" }?.isProgram ?? true)
    }

    func testSelectUpdatesFilter() {
        let m = model(store: MockStore())
        m.select(.exercises)
        XCTAssertEqual(m.selectedFilter, .exercises)
    }

    func testPresentAndDismissCreate() {
        let m = model(store: MockStore())
        XCTAssertFalse(m.isCreateSheetPresented)
        m.presentCreate(); XCTAssertTrue(m.isCreateSheetPresented)
        m.dismissCreate(); XCTAssertFalse(m.isCreateSheetPresented)
    }

    func testIsAllEmptyWhenFoldersAndRecentEmpty() async {
        let m = model(libraryEmpty: true, store: MockStore())
        await m.load()
        XCTAssertEqual(m.loadState, .loaded)
        XCTAssertTrue(m.isAllEmpty)
    }

    func testLibraryFailureSetsError() async {
        let m = model(libraryFail: true, store: MockStore())
        await m.load()
        XCTAssertEqual(m.loadState, .error)
        XCTAssertTrue(m.folders.isEmpty)
    }

    func testCatalogErrorThenRetryRecovers() async {
        let store = MockStore(); store.forceError = true
        let m = model(store: store)            // library succeeds; catalog repo throws
        await m.load()
        XCTAssertEqual(m.loadState, .error)
        store.forceError = false
        await m.retry()
        XCTAssertEqual(m.loadState, .loaded)
    }
}
