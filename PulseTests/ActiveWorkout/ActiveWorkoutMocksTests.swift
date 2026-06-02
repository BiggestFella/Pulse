import XCTest
@testable import Pulse

final class ActiveWorkoutMocksTests: XCTestCase {

    func testSampleWorkoutHasASupersetPairAndAFailureSet() {
        let w = ActiveWorkoutSample.workout
        XCTAssertTrue(w.exercises.contains { $0.supersetGroup != nil })
        XCTAssertTrue(w.exercises.flatMap(\.sets).contains { $0.type == .failure })
    }

    func testAlternativesReturnsSameMuscleGroup() async throws {
        let repo = MockSwapAlternativesRepository()
        let alts = try await repo.alternatives(muscleGroup: "Chest")
        XCTAssertFalse(alts.isEmpty)
        XCTAssertTrue(alts.allSatisfy { $0.muscleGroup == "Chest" })
    }

    func testHistoryReturnsRecentSetsForExercise() async throws {
        let repo = MockHistoryRepository()
        let ex = Exercise(name: "Bench", muscleGroup: "Chest", variations: [])
        let sets = try await repo.recentSets(exerciseID: ex.id)
        XCTAssertFalse(sets.isEmpty)
    }

    func testSaveSessionStubRecordsTheSession() async throws {
        let repo = MockSessionWriter()
        let session = WorkoutSession(workoutID: UUID(), startedAt: .now, endedAt: .now, sets: [])
        try await repo.save(session)
        XCTAssertEqual(repo.saved.count, 1)
    }
}
