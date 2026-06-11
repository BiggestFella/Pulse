import XCTest
@testable import Pulse

final class FatigueSignalTests: XCTestCase {
    private let exID = UUID()

    /// Build a session whose single top working set carries the given RIR.
    private func session(daysAgo: Int, rir: Int?, weight: Double = 100) -> WorkoutSession {
        let start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        let set = SessionSet(exerciseID: exID, order: 0, reps: 5,
                             weight: weight, type: .working, rir: rir)
        return WorkoutSession(workoutID: UUID(), startedAt: start, endedAt: start, sets: [set])
    }

    func testConsistentlyLowRIROverNSessionsSuggestsDeload() {
        let sessions = (0..<6).map { session(daysAgo: $0 * 2, rir: 1) }
        let suggestion = deloadSuggestion(recentSessions: sessions)
        XCTAssertNotNil(suggestion)
    }

    func testMixedOrHighRIRReturnsNil() {
        let sessions = [3, 2, 3, 2, 3, 2].enumerated()
            .map { session(daysAgo: $0.offset * 2, rir: $0.element) }
        XCTAssertNil(deloadSuggestion(recentSessions: sessions))
    }

    func testBelowMinimumTaggedSessionsReturnsNil() {
        // Only 2 tagged sessions (both hard); rest untagged → not enough signal.
        let sessions = [
            session(daysAgo: 0, rir: 0), session(daysAgo: 2, rir: 1),
            session(daysAgo: 4, rir: nil), session(daysAgo: 6, rir: nil),
            session(daysAgo: 8, rir: nil), session(daysAgo: 10, rir: nil),
        ]
        XCTAssertNil(deloadSuggestion(recentSessions: sessions))
    }

    func testEmptyInputReturnsNil() {
        XCTAssertNil(deloadSuggestion(recentSessions: []))
    }

    func testOnlyConsidersMostRecentNSessions() {
        // 6 recent hard sessions + 4 older easy ones; only the recent 6 count.
        let hard = (0..<6).map { session(daysAgo: $0, rir: 1) }
        let easyOlder = (0..<4).map { session(daysAgo: 30 + $0, rir: 4) }
        let suggestion = deloadSuggestion(recentSessions: hard + easyOlder)
        XCTAssertNotNil(suggestion)
    }
}
