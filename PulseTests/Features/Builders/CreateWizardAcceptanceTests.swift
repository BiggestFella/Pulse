import XCTest
@testable import Pulse

@MainActor
final class CreateWizardAcceptanceTests: XCTestCase {
    func testCreateThenEditorAddsExerciseAndKeepsFolderTargetsWeekdays() async throws {
        let store = MockStore(seeded: true)
        let workouts = InMemoryWorkoutRepository(store: store)
        let folders = InMemoryFolderRepository(store: store)
        let folder = try await folders.createFolder(name: "Push days", color: .default, parentID: nil)

        // Wizard → Create
        let wiz = CreateWizardModel(workouts: workouts, folders: folders, folderID: folder.id)
        wiz.name = "Heavy Push"
        wiz.toggleTarget(.chest); wiz.toggleWeekday(1); wiz.toggleWeekday(5)
        let created = await wiz.create()
        let newID = try XCTUnwrap(created)

        // Editor hydrates the wizard's draft, adds an exercise, saves in place.
        let editor = WorkoutBuilderModel(workoutID: newID,
                                         catalog: InMemoryExerciseRepository(store: store),
                                         workouts: workouts)
        await editor.loadCatalog()
        await editor.load()
        XCTAssertEqual(editor.name, "Heavy Push")
        XCTAssertEqual(editor.targets, [.chest])

        let firstGroup = try XCTUnwrap(editor.catalog.first)
        let firstItem = try XCTUnwrap(firstGroup.exercises.first)
        editor.addExercises([PickedExercise(id: firstItem.id, variationID: nil)])
        await editor.save()

        // Persisted: same id, exercise added, weekdays/targets preserved, still in folder.
        let saved = try await workouts.fetchWorkout(id: newID)
        XCTAssertEqual(saved?.id, newID)
        XCTAssertEqual(saved?.exercises.count, 1)
        XCTAssertEqual(saved?.weekdays, [1, 5])
        XCTAssertEqual(saved?.targets, [.chest])
        let contents = try await folders.contents(of: folder.id)
        XCTAssertTrue(contents.workouts.contains { $0.id == newID })
    }

    func testEditExistingWorkoutSavesInPlace() async throws {
        let store = MockStore(seeded: true)
        let workouts = InMemoryWorkoutRepository(store: store)
        let all = try await workouts.fetchWorkouts()
        let existing = try XCTUnwrap(all.first)
        let editor = WorkoutBuilderModel(workoutID: existing.id,
                                         catalog: InMemoryExerciseRepository(store: store),
                                         workouts: workouts)
        await editor.load()
        editor.name = "Renamed In Editor"
        await editor.save()
        let saved = try await workouts.fetchWorkout(id: existing.id)
        XCTAssertEqual(saved?.id, existing.id)
        XCTAssertEqual(saved?.name, "Renamed In Editor")
    }
}
