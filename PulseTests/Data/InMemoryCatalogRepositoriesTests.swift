import XCTest
@testable import Pulse

@MainActor
final class InMemoryCatalogRepositoriesTests: XCTestCase {

    func testProgramSaveFetchDeleteRoundTrip() async throws {
        let store = MockStore()
        let repo = InMemoryProgramRepository(store: store)
        let before = try await repo.fetchPrograms().count
        var p = Program(name: "5x5", weeks: 12, workouts: [])
        let saved = try await repo.saveProgram(p)
        let afterSave = try await repo.fetchPrograms().count
        XCTAssertEqual(afterSave, before + 1)
        try await repo.deleteProgram(id: saved.id)
        let ids = try await repo.fetchPrograms().map(\.id)
        XCTAssertFalse(ids.contains(saved.id))
        _ = p; p.name = "x"
    }

    func testActiveProgramReturnsTheActiveOne() async throws {
        let repo = InMemoryProgramRepository(store: MockStore())
        let active = try await repo.activeProgram()
        XCTAssertEqual(active?.name, "Push / Pull / Legs")
        XCTAssertEqual(active?.isActive, true)
    }

    func testFetchWorkoutIsHydratedWithVariationAndOrderedSets() async throws {
        let store = MockStore()
        let repo = InMemoryWorkoutRepository(store: store)
        let push = SampleData.pushWorkout
        let fetched = try await repo.fetchWorkout(id: push.id)
        let hydrated = try XCTUnwrap(fetched)
        XCTAssertEqual(hydrated.exercises.map(\.exercise.name),
                       ["Bench Press", "Overhead Press", "Incline Press", "Cable Fly", "Triceps Pushdown"])
        let bench = hydrated.exercises[0]
        XCTAssertEqual(bench.variationID, bench.exercise.defaultVariationID)
        XCTAssertFalse(bench.sets.isEmpty)
        XCTAssertEqual(hydrated.exercises[2].supersetGroup, "A")
        XCTAssertEqual(hydrated.exercises[3].supersetGroup, "A")
    }

    func testTodaysWorkoutMatchesWeekday() async throws {
        let repo = InMemoryWorkoutRepository(store: MockStore())
        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2
        let monday = nextWeekday(2, from: Date(), calendar: cal) // 2 = Monday in Gregorian
        let w = try await repo.todaysWorkout(on: monday)
        XCTAssertEqual(w?.name, "Push")
    }

    func testSaveWorkoutAppearsInFetch() async throws {
        let store = MockStore()
        let repo = InMemoryWorkoutRepository(store: store)
        let new = Workout(name: "Arms Day", weekday: nil, order: 9, exercises: [])
        _ = try await repo.saveWorkout(new)
        let names = try await repo.fetchWorkouts().map(\.name)
        XCTAssertTrue(names.contains("Arms Day"))
    }

    func testAlternativesAreSameMuscleAndExcludeSelf() async throws {
        let repo = InMemoryExerciseRepository(store: MockStore())
        let bench = SampleData.exercises.first { $0.name == "Bench Press" }!
        let alts = try await repo.alternatives(for: bench.id)
        XCTAssertFalse(alts.contains { $0.id == bench.id })
        XCTAssertTrue(alts.allSatisfy { $0.muscleGroup == "Chest" })
    }

    func testFetchExercisesByMuscleGroup() async throws {
        let repo = InMemoryExerciseRepository(store: MockStore())
        let back = try await repo.fetchExercises(muscleGroup: "Back")
        XCTAssertTrue(back.allSatisfy { $0.muscleGroup == "Back" })
        XCTAssertFalse(back.isEmpty)
    }

    private func nextWeekday(_ target: Int, from: Date, calendar: Calendar) -> Date {
        var d = calendar.startOfDay(for: from)
        for _ in 0..<7 {
            if calendar.component(.weekday, from: d) == target { return d }
            d = calendar.date(byAdding: .day, value: 1, to: d)!
        }
        return d
    }
}
