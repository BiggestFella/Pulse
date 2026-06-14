import XCTest
@testable import Pulse

@MainActor
final class WorkoutSettingsModelTests: XCTestCase {
    /// Seeds a "Push" workout (Mon, Chest, sample exercises) into the active program.
    private func seedWorkout(_ store: MockStore) async throws -> Workout {
        let repo = InMemoryWorkoutRepository(store: store)
        let w = Workout(name: "Push", weekdays: [1], order: 0,
                        exercises: BuilderSampleData.defaultWorkoutItems.map {
                            WorkoutExercise(exercise: $0.exercise, variationID: $0.variationID,
                                            supersetGroup: $0.supersetGroup, sets: $0.sets) },
                        targets: [.chest])
        _ = try await repo.saveWorkout(w)
        return w
    }

    private func model(_ store: MockStore, _ id: Workout.ID) -> WorkoutSettingsModel {
        WorkoutSettingsModel(workoutID: id,
                             workoutRepo: InMemoryWorkoutRepository(store: store),
                             scheduleRepo: InMemoryScheduleRepository(store: store),
                             folderRepo: InMemoryFolderRepository(store: store))
    }

    func testLoadHydratesAllSettings() async throws {
        let store = MockStore(seeded: true)
        let w = try await seedWorkout(store)
        let m = model(store, w.id)
        await m.load()
        XCTAssertEqual(m.loadState, .loaded)
        XCTAssertEqual(m.weekdays, [1])
        XCTAssertEqual(m.targets, [.chest])
        XCTAssertNil(m.restSeconds)
        XCTAssertEqual(m.notes, "")
    }

    func testSettingRestNotesPersistsAndKeepsExercises() async throws {
        let store = MockStore(seeded: true)
        let w = try await seedWorkout(store)
        let repo = InMemoryWorkoutRepository(store: store)
        let m = model(store, w.id)
        await m.load()
        await m.setRestSeconds(120)
        await m.setNotes("Belt on top sets")
        let saved = try await repo.fetchWorkout(id: w.id)
        XCTAssertEqual(saved?.restSeconds, 120)
        XCTAssertEqual(saved?.notes, "Belt on top sets")
        XCTAssertEqual(saved?.exercises.count, BuilderSampleData.defaultWorkoutItems.count)  // exercises preserved
        XCTAssertEqual(saved?.weekdays, [1])                                                 // schedule preserved
    }

    func testToggleWeekdayAndTargetPersist() async throws {
        let store = MockStore(seeded: true)
        let w = try await seedWorkout(store)
        let repo = InMemoryWorkoutRepository(store: store)
        let m = model(store, w.id)
        await m.load()
        await m.toggleWeekday(5)         // add Friday
        await m.toggleTarget(.back)
        let saved = try await repo.fetchWorkout(id: w.id)
        XCTAssertEqual(saved?.weekdays, [1, 5])
        XCTAssertEqual(Set(saved?.targets ?? []), [.chest, .back])
    }

    func testUseDefaultRestClearsOverride() async throws {
        let store = MockStore(seeded: true)
        let w = try await seedWorkout(store)
        let repo = InMemoryWorkoutRepository(store: store)
        let m = model(store, w.id)
        await m.load()
        await m.setRestSeconds(120)
        await m.useDefaultRest()
        let saved = try await repo.fetchWorkout(id: w.id)
        XCTAssertNil(saved?.restSeconds)
    }

    func testRestClampsToBounds() async throws {
        let store = MockStore(seeded: true)
        let w = try await seedWorkout(store)
        let repo = InMemoryWorkoutRepository(store: store)
        let m = model(store, w.id)
        await m.load()
        await m.setRestSeconds(5)          // below 15 → clamps to 15
        let low = try await repo.fetchWorkout(id: w.id)
        XCTAssertEqual(low?.restSeconds, 15)
        await m.setRestSeconds(9999)       // above 600 → clamps to 600
        let high = try await repo.fetchWorkout(id: w.id)
        XCTAssertEqual(high?.restSeconds, 600)
    }

    func testDeleteRemovesWorkout() async throws {
        let store = MockStore(seeded: true)
        let w = try await seedWorkout(store)
        let repo = InMemoryWorkoutRepository(store: store)
        let m = model(store, w.id)
        await m.load()
        await m.delete()
        let fetched = try await repo.fetchWorkout(id: w.id)
        XCTAssertNil(fetched)
        XCTAssertTrue(m.deleted)
    }
}
