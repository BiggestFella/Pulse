import XCTest
@testable import Pulse

final class PlanViewDataTests: XCTestCase {
    func testDayStateHasFourCases() {
        XCTAssertEqual(Set(DayState.allCases), [.done, .today, .plan, .empty])
    }

    func testScheduledDayDefaultsToEmpty() {
        let d = ScheduledDay(state: .empty, workoutName: nil)
        XCTAssertEqual(d.state, .empty)
        XCTAssertNil(d.workoutName)
        XCTAssertFalse(d.isRest)
    }

    func testMonthSummaryPercentRoundsDownAndGuardsZero() {
        XCTAssertEqual(MonthSummary(done: 20, planned: 23).pct, 86)   // 86.9 -> 86
        XCTAssertEqual(MonthSummary(done: 0, planned: 0).pct, 0)      // no divide-by-zero
        XCTAssertEqual(MonthSummary(done: 3, planned: 6).pct, 50)
    }

    func testSavedWorkoutRefCarriesNameAndSub() {
        let ref = SavedWorkoutRef(id: UUID(), name: "Chest & Tris", exerciseCount: 6)
        XCTAssertEqual(ref.sub, "6 EXERCISES")
    }
}
