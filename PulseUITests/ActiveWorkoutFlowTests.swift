import XCTest

final class ActiveWorkoutFlowTests: XCTestCase {

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    // AC1 — starting the workout (Today's hero Start →) hides the tab bar and
    // enters the flow.
    func testStartHidesTabBar() {
        let app = launch()
        let start = app.buttons["today.hero.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.firstMatch.exists)
        start.tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"),
                               evaluatedWith: app.tabBars.firstMatch)
        wait(for: [gone], timeout: 5)
    }

    // AC2 — Begin moves pre → active (active screen exposes the Log button).
    func testBeginMovesToActive() throws {
        try XCTSkipUnless(false, "Enabled once PreWorkoutView (pre.begin) + ActiveSetView (active.log) land")
        let app = launch()
        app.buttons["today.hero.start"].tap()
        let begin = app.buttons["pre.begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 5))
        begin.tap()
        XCTAssertTrue(app.buttons["active.log"].waitForExistence(timeout: 5))
    }

    // AC17 — back/pause from pre ends the workout and restores the tab bar.
    func testBackFromPreReturnsToTodayWithTabBar() throws {
        try XCTSkipUnless(false, "Enabled once PreWorkoutView (pre.back) lands")
        let app = launch()
        app.buttons["today.hero.start"].tap()
        let back = app.buttons["pre.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
    }
}
