import XCTest

/// Acceptance tests for BAK-17 (History + Session Detail). The app defaults to
/// the seeded in-memory mock world (DEBUG), so no special launch seed is needed —
/// the same approach as PersonalRecordsUITests.
final class HistorySessionDetailUITests: XCTestCase {

    private func openHistory() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["You"].tap()
        let link = app.buttons["you.workoutHistory"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        return app
    }

    private func openFirstSession(_ app: XCUIApplication) {
        // First seeded session (most recent) belongs to the Push workout.
        let row = app.buttons["history.row.Push"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
    }

    // AC1/AC2/AC3 — navigate to History; chrome + default filter render.
    func testHistoryChromeAndDefaultFilter() {
        let app = openHistory()
        XCTAssertTrue(app.staticTexts["history.h1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["WORKOUT HISTORY"].exists)
        XCTAssertTrue(app.staticTexts["history.subline"].exists)
        XCTAssertTrue(app.buttons["history.chip.All"].exists)
        XCTAssertTrue(app.buttons["history.chip.+ PR"].exists)
        XCTAssertTrue(app.buttons["history.chip.PPL"].exists)
        XCTAssertTrue(app.buttons["history.chip.One-offs"].exists)
    }

    // AC5/AC6 — recency group eyebrow + at least one row render.
    func testGroupedRowsRender() {
        let app = openHistory()
        XCTAssertTrue(app.staticTexts["THIS WEEK"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["history.row.Push"].firstMatch.exists)
    }

    // AC4 — One-offs yields the filter-empty message (all seeded sessions are
    // program-backed); All restores the rows.
    func testFilterNarrowsThenAllRestores() {
        let app = openHistory()
        XCTAssertTrue(app.buttons["history.row.Push"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["history.chip.One-offs"].tap()
        XCTAssertTrue(app.staticTexts["history.empty"].waitForExistence(timeout: 3))
        app.buttons["history.chip.All"].tap()
        XCTAssertTrue(app.buttons["history.row.Push"].firstMatch.waitForExistence(timeout: 3))
    }

    // AC7/AC8/AC9 — row → Session Detail; eyebrow, h1, stat boxes render.
    func testSessionDetailChromeAndStats() {
        let app = openHistory()
        openFirstSession(app)
        XCTAssertTrue(app.staticTexts["session.h1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["session.subline"].exists)
        XCTAssertTrue(app.otherElements["session.prBox"].exists ||
                      app.staticTexts["session.prBox"].exists ||
                      app.descendants(matching: .any)["session.prBox"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["session.volumeBox"].firstMatch.exists)
    }

    // AC10/AC11 — LOG rows + footer buttons render.
    func testSessionDetailLogAndFooter() {
        let app = openHistory()
        openFirstSession(app)
        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["session.duplicate"].exists)
        XCTAssertTrue(app.buttons["session.repeat"].exists)
    }

    // AC15 — back from Session Detail returns to History; back again to You.
    func testBackNavigationThroughStack() {
        let app = openHistory()
        openFirstSession(app)
        XCTAssertTrue(app.buttons["session.back"].waitForExistence(timeout: 5))
        app.buttons["session.back"].tap()
        XCTAssertTrue(app.staticTexts["history.h1"].waitForExistence(timeout: 5))
        app.buttons["history.back"].tap()
        XCTAssertTrue(app.buttons["you.workoutHistory"].waitForExistence(timeout: 5))
    }
}
