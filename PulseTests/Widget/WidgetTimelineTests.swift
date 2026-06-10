import XCTest
@testable import Pulse

final class WidgetTimelineTests: XCTestCase {
    func testNowEntryShowsSnapshotAsIs() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = WidgetTimeline.entries(snapshot: .sample, now: now)
        XCTAssertEqual(entries.first?.date, now)
        XCTAssertEqual(entries.first?.snapshot, .sample)
    }

    func testMidnightEntryIsLaterAndNeutralised() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = WidgetTimeline.entries(snapshot: .sample, now: now)
        XCTAssertEqual(entries.count, 2)
        let midnight = entries[1]
        XCTAssertGreaterThan(midnight.date, now)
        XCTAssertNil(midnight.snapshot.todayWorkoutName)        // no stale workout into a new day
        XCTAssertNil(midnight.snapshot.exerciseCount)
        XCTAssertEqual(midnight.snapshot.startRoute, WidgetDeepLink.today.url.absoluteString)
        XCTAssertEqual(midnight.snapshot.streak, 27)            // streak/week preserved
    }

    func testNextRefreshIsUpcomingMidnight() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_700_000_000)   // 2023-11-14 22:13:20 UTC
        let next = WidgetTimeline.nextRefresh(after: now, calendar: cal)
        XCTAssertGreaterThan(next, now)
        let comps = cal.dateComponents([.hour, .minute, .second], from: next)
        XCTAssertEqual(comps.hour, 0)
        XCTAssertEqual(comps.minute, 0)
    }
}
