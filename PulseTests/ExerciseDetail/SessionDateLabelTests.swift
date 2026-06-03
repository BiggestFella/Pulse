import XCTest
@testable import Pulse

final class SessionDateLabelTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d
        return Calendar.current.date(from: c)!
    }

    func testRowLabelIsWeekdayDotMonthDay() {
        // 2026-05-22 is a Friday.
        XCTAssertEqual(SessionDateLabel.row(date(2026, 5, 22)), "FRI · MAY 22")
    }

    func testWeekdayOnlySegment() {
        XCTAssertEqual(SessionDateLabel.weekday(date(2026, 5, 22)), "FRI")
    }
}
