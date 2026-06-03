import XCTest
@testable import Pulse

@MainActor
final class RoutineBuilderModelTests: XCTestCase {
    private func makeModel(store: MockStore? = nil) -> RoutineBuilderModel {
        let store = store ?? MockStore()
        return RoutineBuilderModel(
            routines: InMemoryProgramRepository(store: store),
            workouts: InMemoryWorkoutRepository(store: store))
    }

    func testSeededDefaults() {
        let model = makeModel()
        XCTAssertEqual(model.weeks, 8)
        XCTAssertEqual(model.days.count, 5)
        XCTAssertEqual(model.workoutsPerWeek, 4) // 5 days, 1 rest
    }

    func testIncWeeks() {
        let model = makeModel()
        model.incWeeks()
        XCTAssertEqual(model.weeks, 9)
    }

    func testDecWeeksClampsAtOne() {
        let model = makeModel()
        model.weeks = 1
        model.decWeeks()
        XCTAssertEqual(model.weeks, 1)
    }

    func testAddWorkoutAppendsDay() {
        let model = makeModel()
        let before = model.days.count
        model.addWorkout(BuilderDay(name: "Arms", sub: "4 exercises"))
        XCTAssertEqual(model.days.count, before + 1)
        XCTAssertEqual(model.days.last?.name, "Arms")
    }

    func testAddRestDayAppendsRest() {
        let model = makeModel()
        let beforeWorkouts = model.workoutsPerWeek
        model.addRestDay()
        XCTAssertTrue(model.days.last?.isRest == true)
        XCTAssertEqual(model.workoutsPerWeek, beforeWorkouts) // rest doesn't count
    }

    func testRemoveDay() {
        let model = makeModel()
        let id = model.days[0].id
        model.removeDay(id: id)
        XCTAssertFalse(model.days.contains { $0.id == id })
    }

    func testLoadSavedWorkoutsPopulatesPicker() async {
        let model = makeModel()
        await model.loadSavedWorkouts()
        XCTAssertFalse(model.savedWorkouts.isEmpty)
    }

    func testSaveCallsRepositoryAndSetsSaved() async {
        let store = MockStore()
        let routines = InMemoryProgramRepository(store: store)
        let model = RoutineBuilderModel(
            routines: routines, workouts: InMemoryWorkoutRepository(store: store))
        await model.save()
        XCTAssertEqual(model.saveState, .saved)
        let saved = (try? await routines.fetchPrograms())?.first { $0.name == model.name }
        XCTAssertEqual(saved?.weeks, 8)
        // Rest days are excluded from the persisted Program's workouts.
        XCTAssertEqual(saved?.workouts.count, model.workoutsPerWeek)
    }

    func testSaveErrorWhenRepositoryThrows() async {
        let store = MockStore()
        store.forceError = true
        let model = makeModel(store: store)
        await model.save()
        if case .error = model.saveState { } else { XCTFail("expected .error") }
    }
}
