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

    func testSeededMockStoreSurfacesSampleFolder() async {
        let model = makeModel(store: MockStore(seeded: true))
        await model.load()
        XCTAssertTrue(model.folders.contains { $0.name == "Push Pull Legs" })
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

    func testRelativeDayBoundaries() {
        let cal = SampleData.calendar
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 12))!
        func day(_ d: Int) -> Date { cal.date(byAdding: .day, value: -d, to: now)! }
        XCTAssertEqual(LibraryModel.relativeDay(day(0), now: now), "Today")
        XCTAssertEqual(LibraryModel.relativeDay(day(1), now: now), "Yesterday")
        XCTAssertEqual(LibraryModel.relativeDay(day(3), now: now), "3 days ago")
        XCTAssertEqual(LibraryModel.relativeDay(day(6), now: now), "6 days ago")
        XCTAssertFalse(LibraryModel.relativeDay(day(7), now: now).hasSuffix("ago"))
        let old = LibraryModel.relativeDay(day(40), now: now)
        XCTAssertFalse(old.isEmpty)
        XCTAssertFalse(old.hasSuffix("ago"))
    }

    func testRecentSublineHasSetCountAndRelativeDay() {
        let cal = SampleData.calendar
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 12))!
        let wid = UUID()
        let workout = Workout(id: wid, name: "Leg day", order: 0, exercises: [])
        let session = WorkoutSession(
            id: UUID(), workoutID: wid,
            startedAt: cal.date(byAdding: .day, value: -1, to: now)!, endedAt: nil,
            sets: [SessionSet(exerciseID: UUID(), order: 0, reps: 5, weight: 100, type: .working)])
        let rows = LibraryModel.recent([session], workouts: [workout], now: now)
        XCTAssertEqual(rows.first?.name, "Leg day")
        XCTAssertEqual(rows.first?.sub, "1 set · Yesterday")
    }

    func testRequestDeleteEmptyFolderDeletesImmediately() async {
        let store = MockStore(seeded: false)
        let repo = InMemoryFolderRepository(store: store)
        let folder = try! await repo.createFolder(name: "Empty", color: .blue, parentID: nil)
        let model = makeModel(store: store)
        await model.load()
        await model.requestDelete(LibraryModel.project(folder))
        XCTAssertNil(model.pendingDelete)
        XCTAssertFalse(store.folders.contains { $0.id == folder.id })
    }

    func testRequestDeleteNonEmptyFolderPromptsWithCount() async {
        let store = MockStore(seeded: false)
        let repo = InMemoryFolderRepository(store: store)
        let parent = try! await repo.createFolder(name: "Parent", color: .blue, parentID: nil)
        _ = try! await repo.createFolder(name: "Child", color: .teal, parentID: parent.id)
        let model = makeModel(store: store)
        await model.load()
        await model.requestDelete(LibraryModel.project(parent))
        XCTAssertEqual(model.pendingDelete?.itemCount, 1)
        XCTAssertTrue(store.folders.contains { $0.id == parent.id })
        await model.confirmDelete()
        XCTAssertNil(model.pendingDelete)
        XCTAssertFalse(store.folders.contains { $0.id == parent.id })
    }
}
