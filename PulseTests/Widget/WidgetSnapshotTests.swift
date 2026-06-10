import XCTest
@testable import Pulse

final class WidgetSnapshotTests: XCTestCase {
    func testRoundTripsIncludingRestDayNils() throws {
        let s = WidgetSnapshot.sample
        XCTAssertEqual(try JSONDecoder().decode(WidgetSnapshot.self,
                                                from: try JSONEncoder().encode(s)), s)
        let rest = WidgetSnapshot.restSample
        XCTAssertNil(rest.todayWorkoutName)
        XCTAssertNil(rest.exerciseCount)
        XCTAssertEqual(try JSONDecoder().decode(WidgetSnapshot.self,
                                                from: try JSONEncoder().encode(rest)), rest)
    }

    func testProgressDerivationMatchesTodayRule() {
        XCTAssertEqual(WidgetSnapshot.sample.doneCount, 3)
        XCTAssertEqual(WidgetSnapshot.sample.plannedCount, 5)   // excludes rest
        XCTAssertEqual(WidgetSnapshot.allRestSample.doneCount, 0)
        XCTAssertEqual(WidgetSnapshot.allRestSample.plannedCount, 0)
    }

    func testRestDayAndValidityFlags() {
        XCTAssertFalse(WidgetSnapshot.sample.isRestDay)
        XCTAssertTrue(WidgetSnapshot.restSample.isRestDay)
        XCTAssertTrue(WidgetSnapshot.sample.hasValidWeek)
        var corrupt = WidgetSnapshot.sample
        corrupt.week = Array(corrupt.week.prefix(3))
        XCTAssertFalse(corrupt.hasValidWeek)
    }
}
