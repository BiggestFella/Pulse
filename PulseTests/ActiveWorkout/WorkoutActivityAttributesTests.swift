import XCTest
@testable import Pulse

final class WorkoutActivityAttributesTests: XCTestCase {
    private func sampleState() -> WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            phase: .rest,
            exerciseName: "Bench Press",
            setIndex: 2, totalSets: 4,
            setTypeLabel: "WORKING",
            targetReps: 8, targetWeight: 80,
            ssLabel: nil, isMidPair: false,
            restEndsAt: Date(timeIntervalSince1970: 1_000_090),
            totalRest: 90,
            nextExerciseName: "Bench Press", nextReps: 8, nextWeight: 80, nextSsLabel: nil,
            completedSets: 1, totalStepCount: 12,
            palette: .coastal)
    }

    func testContentStateCodableRoundTrip() throws {
        let original = sampleState()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            WorkoutActivityAttributes.ContentState.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testContentStateIsHashable() {
        XCTAssertEqual(sampleState().hashValue, sampleState().hashValue)
    }

    func testRestFractionUsesTotalRest() {
        let now = Date(timeIntervalSince1970: 1_000_045) // 45s elapsed of 90
        let state = sampleState()
        XCTAssertEqual(state.restFraction(now: now), 0.5, accuracy: 0.001)
    }

    func testRestFractionClampsAtZeroWhenElapsed() {
        let now = Date(timeIntervalSince1970: 1_000_200) // past end
        XCTAssertEqual(sampleState().restFraction(now: now), 0, accuracy: 0.001)
    }
}
