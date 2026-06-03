import XCTest
@testable import Pulse

final class MonthMathTests: XCTestCase {
    private func cal() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2 // Monday
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal().date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testMay2026MondayStartOffsetIsFour() {
        // May 1 2026 is a Friday; Monday-start offset = 4.
        let ctx = MonthMath.context(for: date(2026, 5, 15), calendar: cal())
        XCTAssertEqual(ctx.monthStartOffset, 4)
        XCTAssertEqual(ctx.daysInMonth, 31)
        XCTAssertEqual(ctx.title, "May.")
        XCTAssertEqual(ctx.year, 2026)
        XCTAssertEqual(ctx.monthAbbrevUpper, "MAY")
    }

    func testFebruary2027MondayStartOffset() {
        // Feb 1 2027 is a Monday; offset = 0; 28 days.
        let ctx = MonthMath.context(for: date(2027, 2, 10), calendar: cal())
        XCTAssertEqual(ctx.monthStartOffset, 0)
        XCTAssertEqual(ctx.daysInMonth, 28)
    }

    func testDowAbbreviationForDay() {
        // May 1 2026 is a Friday, so May 28 2026 (27 days later) is a Thursday.
        XCTAssertEqual(MonthMath.dowAbbrev(year: 2026, month: 5, day: 28, calendar: cal()), "THU")
    }
}
