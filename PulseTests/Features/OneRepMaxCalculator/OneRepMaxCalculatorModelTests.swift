import XCTest
@testable import Pulse

@MainActor
final class OneRepMaxCalculatorModelTests: XCTestCase {

    func testEstimatedOneRepMaxEqualsEpley() {
        let m = OneRepMaxCalculatorModel(weight: 80, reps: 5)
        XCTAssertEqual(m.estimatedOneRepMax, epley1RM(weight: 80, reps: 5), accuracy: 0.0001)
        // sanity: 80 × (1 + 5/30) = 93.33…
        XCTAssertEqual(m.estimatedOneRepMax, 80 * (1 + 5.0 / 30), accuracy: 0.0001)
    }

    func testSingleRepReturnsBarWeight() {
        let m = OneRepMaxCalculatorModel(weight: 100, reps: 1)
        XCTAssertEqual(m.estimatedOneRepMax, 100, accuracy: 0.0001)
    }

    func testWeightStepperUpdatesEstimateLive() {
        let m = OneRepMaxCalculatorModel(weight: 80, reps: 5)
        m.incrementWeight()
        XCTAssertEqual(m.weight, 82.5, accuracy: 0.0001)
        XCTAssertEqual(m.estimatedOneRepMax, epley1RM(weight: 82.5, reps: 5), accuracy: 0.0001)
    }

    func testRepsStepperUpdatesEstimateLive() {
        let m = OneRepMaxCalculatorModel(weight: 80, reps: 5)
        m.incrementReps()
        XCTAssertEqual(m.reps, 6)
        XCTAssertEqual(m.estimatedOneRepMax, epley1RM(weight: 80, reps: 6), accuracy: 0.0001)
    }

    func testWeightFlooredAtZeroAndStepsByTwoPointFive() {
        let m = OneRepMaxCalculatorModel(weight: 2.5, reps: 5)
        m.decrementWeight()
        XCTAssertEqual(m.weight, 0, accuracy: 0.0001)
        m.decrementWeight()   // does not go negative
        XCTAssertEqual(m.weight, 0, accuracy: 0.0001)
    }

    func testRepsFlooredAtOne() {
        let m = OneRepMaxCalculatorModel(weight: 80, reps: 1)
        m.decrementReps()     // reps never below 1 (est-1RM undefined for 0)
        XCTAssertEqual(m.reps, 1)
    }
}
