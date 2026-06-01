import XCTest
@testable import Pulse

@MainActor
final class PRRepositoryTests: XCTestCase {
    private func repo() -> InMemoryPRRepository { InMemoryPRRepository(store: MockStore()) }

    func testAllPRsOnePerExerciseWithLoggedSets() async throws {
        let prs = try await repo().allPRs()
        let exercisesWithSets = Set(SampleData.sessions.flatMap(\.sets)
            .filter { WorkoutAnalytics.counts($0.type) }.map(\.exerciseID))
        XCTAssertEqual(Set(prs.map(\.exerciseID)), exercisesWithSets)
    }

    func testPersonalBestIsMaxEstimated1RM() async throws {
        let bench = SampleData.exercises.first { $0.name == "Bench Press" }!
        let maybeBest = try await repo().personalBest(forExercise: bench.id)
        let best = try XCTUnwrap(maybeBest)
        let allBenchSets = SampleData.sessions.flatMap(\.sets)
            .filter { $0.exerciseID == bench.id && WorkoutAnalytics.counts($0.type) }
        let expected = allBenchSets.map(WorkoutAnalytics.estimatedOneRepMax).max()!
        XCTAssertEqual(best.estimatedOneRepMax, expected, accuracy: 0.01)
    }

    func testWarmupsNeverProducePRs() async throws {
        let store = MockStore(seeded: false)
        let ex = SampleData.exercises[0]
        store.exercises = [ex]
        store.sessions = [WorkoutSession(workoutID: UUID(), startedAt: Date(), endedAt: Date(),
            sets: [SessionSet(exerciseID: ex.id, order: 0, reps: 1, weight: 300, type: .warmup),
                   SessionSet(exerciseID: ex.id, order: 1, reps: 10, weight: 50, type: .working)])]
        let maybeBest = try await InMemoryPRRepository(store: store).personalBest(forExercise: ex.id)
        let best = try XCTUnwrap(maybeBest)
        XCTAssertEqual(best.weight, 50)
    }

    func testNewPRsFlaggedWithinRangeOnly() async throws {
        let recent = try await repo().newPRs(in: .d7)
        XCTAssertTrue(recent.allSatisfy(\.isNew))
        XCTAssertGreaterThanOrEqual(recent.count, 1)
        let allTime = try await repo().newPRs(in: .all)
        XCTAssertGreaterThanOrEqual(allTime.count, recent.count)
    }

    func testPRsByMuscleGroup() async throws {
        let chest = try await repo().prs(muscleGroup: "Chest")
        let chestIDs = Set(SampleData.exercises.filter { $0.muscleGroup == "Chest" }.map(\.id))
        XCTAssertTrue(chest.allSatisfy { chestIDs.contains($0.exerciseID) })
    }
}
