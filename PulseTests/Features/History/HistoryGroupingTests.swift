import XCTest
@testable import Pulse

final class HistoryGroupingTests: XCTestCase {
    // Monday-start calendar fixed to UTC so bucketing is deterministic.
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // Monday
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func day(_ s: String) -> Date {
        let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone
        f.dateFormat = "yyyy-MM-dd"; return f.date(from: s)!
    }
    private func summary(_ name: String, _ date: Date) -> WorkoutHistoryModel.Item {
        WorkoutHistoryModel.Item(
            id: UUID(), dayOfWeek: "MON", date: date, dayNumber: "1",
            name: name, durationLabel: "1m", volumeLabel: "1k KG",
            hasPR: false, isProgram: true)
    }

    func testThisWeekAndLastWeekBuckets() {
        let now = day("2026-05-28") // Thursday this week
        let groups = HistoryGrouping.groups(
            for: [
                summary("a", day("2026-05-27")), // this week
                summary("b", day("2026-05-26")), // this week
                summary("c", day("2026-05-20")), // last week
            ],
            now: now, calendar: cal)
        XCTAssertEqual(groups.map(\.label), ["THIS WEEK", "LAST WEEK"])
        XCTAssertEqual(groups[0].sessions.map(\.name), ["a", "b"]) // most-recent first
        XCTAssertEqual(groups[1].sessions.map(\.name), ["c"])
    }

    func testOlderSessionsGetMonthHeaders() {
        let now = day("2026-05-28")
        let groups = HistoryGrouping.groups(
            for: [summary("apr", day("2026-04-10"))],
            now: now, calendar: cal)
        XCTAssertEqual(groups.map(\.label), ["APRIL 2026"])
    }

    func testEmptyInputYieldsNoGroups() {
        XCTAssertTrue(HistoryGrouping.groups(for: [], now: day("2026-05-28"),
                                             calendar: cal).isEmpty)
    }

    func testSingleBucketHasNoEmptyHeaders() {
        let now = day("2026-05-28")
        let groups = HistoryGrouping.groups(
            for: [summary("a", day("2026-05-27"))],
            now: now, calendar: cal)
        XCTAssertEqual(groups.map(\.label), ["THIS WEEK"])
    }

    func testMostRecentFirstAcrossGroups() {
        let now = day("2026-05-28")
        let groups = HistoryGrouping.groups(
            for: [
                summary("old", day("2026-03-02")),
                summary("new", day("2026-05-27")),
                summary("mid", day("2026-04-15")),
            ],
            now: now, calendar: cal)
        XCTAssertEqual(groups.map(\.label), ["THIS WEEK", "APRIL 2026", "MARCH 2026"])
    }
}
