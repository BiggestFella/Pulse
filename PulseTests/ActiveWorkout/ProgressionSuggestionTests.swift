import XCTest
@testable import Pulse

final class ProgressionSuggestionTests: XCTestCase {

    private func target(reps: Int) -> SetSpec { SetSpec(reps: reps, rir: 2, type: .working) }
    private func set(_ reps: Int, _ weight: Double) -> SessionSet {
        SessionSet(exerciseID: UUID(), order: 0, reps: reps, weight: weight, type: .working)
    }

    // Spec AC1 — no history → nil.
    func testNoHistoryReturnsNil() {
        let input = ProgressionInput(target: target(reps: 8), lastSets: [],
                                     increment: 2.5, autoProgress: true)
        XCTAssertNil(suggestProgression(input))
    }

    // Spec AC2 — hit target last time, autoProgress on → weight + increment, reps == target.
    func testHitTargetAddsIncrement() throws {
        let input = ProgressionInput(target: target(reps: 8),
                                     lastSets: [set(8, 60)],
                                     increment: 2.5, autoProgress: true)
        let s = try XCTUnwrap(suggestProgression(input))
        XCTAssertEqual(s.weight, 62.5, accuracy: 0.001)
        XCTAssertEqual(s.reps, 8)
        XCTAssertEqual(s.rationale, "Hit all reps last time → +2.5 kg")
    }

    // Beating target (more reps than planned) also progresses.
    func testBeatTargetAddsIncrement() throws {
        let input = ProgressionInput(target: target(reps: 8),
                                     lastSets: [set(10, 60)],
                                     increment: 2.5, autoProgress: true)
        let s = try XCTUnwrap(suggestProgression(input))
        XCTAssertEqual(s.weight, 62.5, accuracy: 0.001)
        XCTAssertEqual(s.reps, 8)
    }

    // Spec AC3 — missed target last time → same weight, reps == target.
    func testMissedTargetHoldsWeight() throws {
        let input = ProgressionInput(target: target(reps: 8),
                                     lastSets: [set(6, 60)],
                                     increment: 2.5, autoProgress: true)
        let s = try XCTUnwrap(suggestProgression(input))
        XCTAssertEqual(s.weight, 60, accuracy: 0.001)
        XCTAssertEqual(s.reps, 8)
        XCTAssertEqual(s.rationale, "Missed target last time → hold weight")
    }

    // Spec AC4 — autoProgress off → repeat last weight × last reps.
    func testAutoProgressOffRepeatsLast() throws {
        let input = ProgressionInput(target: target(reps: 8),
                                     lastSets: [set(6, 60)],
                                     increment: 2.5, autoProgress: false)
        let s = try XCTUnwrap(suggestProgression(input))
        XCTAssertEqual(s.weight, 60, accuracy: 0.001)
        XCTAssertEqual(s.reps, 6)
        XCTAssertEqual(s.rationale, "Repeat last session")
    }

    // Spec AC5 — increment is configurable (5.0 → +5.0).
    func testIncrementIsConfigurable() throws {
        let input = ProgressionInput(target: target(reps: 8),
                                     lastSets: [set(8, 60)],
                                     increment: 5.0, autoProgress: true)
        let s = try XCTUnwrap(suggestProgression(input))
        XCTAssertEqual(s.weight, 65, accuracy: 0.001)
        XCTAssertEqual(s.rationale, "Hit all reps last time → +5 kg")
    }
}
