import XCTest
@testable import Pulse

final class DerivedModelsTests: XCTestCase {
    func testSessionSetCarriesExerciseIDAndOrder() throws {
        let ex = UUID()
        let set = SessionSet(exerciseID: ex, order: 2, reps: 8, weight: 60, type: .working)
        XCTAssertEqual(set.exerciseID, ex)
        XCTAssertEqual(set.order, 2)
        let data = try JSONEncoder().encode(set)
        let back = try JSONDecoder().decode(SessionSet.self, from: data)
        XCTAssertEqual(back, set)
    }

    func testProgramHasIsActiveFlag() {
        let p = Program(name: "PPL", weeks: 6, isActive: true, workouts: [])
        XCTAssertTrue(p.isActive)
    }

    func testStatRangeHasFiveCases() {
        XCTAssertEqual(StatRange.allCases, [.d7, .d30, .m3, .year, .all])
    }

    func testDayPlanEquatableVariants() {
        let w = UUID(), s = UUID()
        XCTAssertEqual(DayPlan.workout(w), DayPlan.workout(w))
        XCTAssertNotEqual(DayPlan.workout(w), DayPlan.rest)
        XCTAssertEqual(DayPlan.done(s), DayPlan.done(s))
    }

    func testPersonalRecordHoldsEstimated1RM() {
        let pr = PersonalRecord(exerciseID: UUID(), variationID: nil,
                                weight: 100, reps: 5, estimatedOneRepMax: 116.67,
                                achievedAt: Date(), isNew: true)
        XCTAssertEqual(pr.estimatedOneRepMax, 116.67, accuracy: 0.01)
        XCTAssertTrue(pr.isNew)
    }
}
