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

    // MARK: - %-table

    func testRoundedToNearestTwoPointFive() {
        XCTAssertEqual(OneRepMaxCalculatorModel.rounded(toNearest: 2.5, 81.2), 80, accuracy: 0.0001)
        XCTAssertEqual(OneRepMaxCalculatorModel.rounded(toNearest: 2.5, 81.3), 82.5, accuracy: 0.0001)
        XCTAssertEqual(OneRepMaxCalculatorModel.rounded(toNearest: 2.5, 83.75), 85, accuracy: 0.0001) // .5 rounds up
        XCTAssertEqual(OneRepMaxCalculatorModel.rounded(toNearest: 2.5, 0), 0, accuracy: 0.0001)
    }

    func testWorkingWeightRoundsToTwoPointFive() {
        // 90% of 100 = 90 → 90; 85% of 100 = 85; etc. (round 1RM stays round)
        XCTAssertEqual(OneRepMaxCalculatorModel.workingWeight(forPercent: 90, of: 100), 90, accuracy: 0.0001)
        XCTAssertEqual(OneRepMaxCalculatorModel.workingWeight(forPercent: 70, of: 100), 70, accuracy: 0.0001)
        // non-round 1RM: 85% of 93.333… = 79.33… → nearest 2.5 = 80
        XCTAssertEqual(OneRepMaxCalculatorModel.workingWeight(forPercent: 85, of: 93.3333), 80, accuracy: 0.0001)
    }

    func testPercentRowsCoverNinetyToSeventyDescending() {
        let m = OneRepMaxCalculatorModel(weight: 100, reps: 1) // est-1RM = 100
        XCTAssertEqual(m.percentRows.map(\.percent), [90, 85, 80, 75, 70])
        // values are the working weights rounded to 2.5
        XCTAssertEqual(m.percentRows.map(\.weight), [90, 85, 80, 75, 70])
    }

    func testPercentRowsUpdateLiveWithInputs() throws {
        let m = OneRepMaxCalculatorModel(weight: 100, reps: 1) // est-1RM 100 → 90% = 90
        XCTAssertEqual(try XCTUnwrap(m.percentRows.first?.weight), 90, accuracy: 0.0001)
        m.incrementReps() // reps 2 → est-1RM = 100 × (1 + 2/30) = 106.67 → 90% = 96 → 95 (nearest 2.5)
        XCTAssertEqual(try XCTUnwrap(m.percentRows.first?.weight), 95, accuracy: 0.0001)
    }
}
