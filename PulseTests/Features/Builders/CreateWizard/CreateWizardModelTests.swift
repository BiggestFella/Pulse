import XCTest
@testable import Pulse

@MainActor
final class CreateWizardModelTests: XCTestCase {
    private func make() -> CreateWizardModel {
        let store = MockStore(seeded: true)
        return CreateWizardModel(workouts: InMemoryWorkoutRepository(store: store),
                                 folders: InMemoryFolderRepository(store: store))
    }

    func testStartsAtNameAndAdvancesThroughSteps() {
        let m = make()
        XCTAssertEqual(m.step, .name)
        XCTAssertTrue(m.isFirstStep)
        m.next(); XCTAssertEqual(m.step, .targets)
        m.next(); XCTAssertEqual(m.step, .schedule)
        m.next(); XCTAssertEqual(m.step, .folder)
        XCTAssertTrue(m.isLastStep)
        m.next(); XCTAssertEqual(m.step, .folder)   // no-op past the last step
    }

    func testBackRetreatsAndClampsAtFirst() {
        let m = make()
        m.next(); m.next()
        m.back(); XCTAssertEqual(m.step, .targets)
        m.back(); XCTAssertEqual(m.step, .name)
        m.back(); XCTAssertEqual(m.step, .name)     // no-op before the first step
    }

    func testCanAdvanceRequiresNonEmptyNameOnNameStep() {
        let m = make()
        XCTAssertFalse(m.canAdvance)                // empty name
        m.name = "   "
        XCTAssertFalse(m.canAdvance)                // whitespace only
        m.name = "Push"
        XCTAssertTrue(m.canAdvance)
        m.next()                                    // targets — optional
        XCTAssertTrue(m.canAdvance)
    }

    func testToggleTargetAndWeekday() {
        let m = make()
        m.toggleTarget(.chest); XCTAssertEqual(m.targets, [.chest])
        m.toggleTarget(.chest); XCTAssertTrue(m.targets.isEmpty)
        m.toggleWeekday(3); XCTAssertEqual(m.weekdays, [3])
        m.toggleWeekday(3); XCTAssertTrue(m.weekdays.isEmpty)
    }

    func testCreatePersistsNameTargetsWeekdaysAndReturnsID() async throws {
        let store = MockStore(seeded: true)
        let workouts = InMemoryWorkoutRepository(store: store)
        let m = CreateWizardModel(workouts: workouts,
                                  folders: InMemoryFolderRepository(store: store))
        m.name = "Heavy Push"
        m.toggleTarget(.chest); m.toggleWeekday(5); m.toggleWeekday(1)

        let created = await m.create()
        let id = try XCTUnwrap(created)
        let saved = try await workouts.fetchWorkout(id: id)
        XCTAssertEqual(saved?.name, "Heavy Push")
        XCTAssertEqual(saved?.targets, [.chest])
        XCTAssertEqual(saved?.weekdays, [1, 5])             // canonical order
        XCTAssertEqual(saved?.exercises.count, 0)           // empty until the editor
    }

    func testCreatePlacesWorkoutInChosenFolder() async throws {
        let store = MockStore(seeded: true)
        let workouts = InMemoryWorkoutRepository(store: store)
        let folders = InMemoryFolderRepository(store: store)
        let folder = try await folders.createFolder(name: "Push days", color: .default, parentID: nil)
        let m = CreateWizardModel(workouts: workouts, folders: folders, folderID: folder.id)
        m.name = "In A Folder"

        let created = await m.create()
        let id = try XCTUnwrap(created)
        let contents = try await folders.contents(of: folder.id)
        XCTAssertTrue(contents.workouts.contains { $0.id == id })
    }

    func testCreateAtRootDoesNotPlaceInAnyFolder() async throws {
        let store = MockStore(seeded: true)
        let workouts = InMemoryWorkoutRepository(store: store)
        let folders = InMemoryFolderRepository(store: store)
        let m = CreateWizardModel(workouts: workouts, folders: folders, folderID: nil)
        m.name = "At Root"

        let created = await m.create()
        let id = try XCTUnwrap(created)
        let root = try await folders.contents(of: nil)
        XCTAssertTrue(root.workouts.contains { $0.id == id })
    }
}
