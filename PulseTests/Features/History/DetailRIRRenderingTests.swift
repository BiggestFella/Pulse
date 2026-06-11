import XCTest
@testable import Pulse

@MainActor
final class DetailRIRRenderingTests: XCTestCase {
    func testSessionDetailLineAppendsAverageRIRWhenPresent() {
        let exID = UUID()
        let sets = [
            SessionSet(exerciseID: exID, order: 0, reps: 10, weight: 100, type: .working, rir: 2),
            SessionSet(exerciseID: exID, order: 1, reps: 8,  weight: 100, type: .working, rir: 1),
        ]
        let session = WorkoutSession(workoutID: UUID(), startedAt: .now, endedAt: nil, sets: sets)
        let rows = SessionDetailModel.logRows(
            for: session, workout: nil,
            nameByExercise: [exID: "Back Squat"], prIDs: [])
        // "10·8 @ 100kg · @RIR 1" (avg of 2 and 1 = 1.5 → rounded down to 1)
        XCTAssertTrue(rows.first?.detail.contains("@RIR 1") ?? false,
                      "got: \(rows.first?.detail ?? "nil")")
    }

    func testSessionDetailLineOmitsRIRWhenAllNil() {
        let exID = UUID()
        let sets = [SessionSet(exerciseID: exID, order: 0, reps: 10, weight: 100, type: .working)]
        let session = WorkoutSession(workoutID: UUID(), startedAt: .now, endedAt: nil, sets: sets)
        let rows = SessionDetailModel.logRows(
            for: session, workout: nil,
            nameByExercise: [exID: "Back Squat"], prIDs: [])
        XCTAssertFalse(rows.first?.detail.contains("RIR") ?? true)
    }
}
