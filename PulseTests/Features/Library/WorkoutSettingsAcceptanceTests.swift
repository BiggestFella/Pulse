import XCTest
@testable import Pulse

@MainActor
final class WorkoutSettingsAcceptanceTests: XCTestCase {
    func testEditAllSettingsPersistOnTheSameWorkout() async throws {
        let store = MockStore(seeded: true)
        let workouts = InMemoryWorkoutRepository(store: store)
        let folders = InMemoryFolderRepository(store: store)
        let folder = try await folders.createFolder(name: "Push days", color: .default, parentID: nil)
        let w = Workout(name: "Push", weekdays: [1], order: 0,
                        exercises: BuilderSampleData.defaultWorkoutItems.map {
                            WorkoutExercise(exercise: $0.exercise, variationID: $0.variationID,
                                            supersetGroup: $0.supersetGroup, sets: $0.sets) },
                        targets: [.chest])
        _ = try await workouts.saveWorkout(w)

        let m = WorkoutSettingsModel(workoutID: w.id, workoutRepo: workouts,
                                     scheduleRepo: InMemoryScheduleRepository(store: store),
                                     folderRepo: folders)
        await m.load()
        await m.setRestSeconds(120)
        await m.setNotes("belt on")
        await m.toggleWeekday(5)
        await m.toggleTarget(.back)
        await m.setFolder(folder.id)

        let saved = try await workouts.fetchWorkout(id: w.id)
        XCTAssertEqual(saved?.restSeconds, 120)
        XCTAssertEqual(saved?.notes, "belt on")
        XCTAssertEqual(saved?.weekdays, [1, 5])
        XCTAssertEqual(Set(saved?.targets ?? []), [.chest, .back])
        XCTAssertEqual(saved?.exercises.count, BuilderSampleData.defaultWorkoutItems.count)  // never dropped
        let inFolder = try await folders.contents(of: folder.id)
        XCTAssertTrue(inFolder.workouts.contains { $0.id == w.id })
    }
}
