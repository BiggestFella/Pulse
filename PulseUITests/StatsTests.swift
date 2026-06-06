import XCTest

final class StatsTests: XCTestCase {
    private func openStats() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiMock"]   // pin to the in-memory mock world
        app.launch()
        app.tabBars.buttons["You"].tap()
        let link = app.buttons["you.stats"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        return app
    }

    // AC1–2, AC5 — screen loads with header, default range, hero volume.
    func testStatsScreenLoads() {
        let app = openStats()
        XCTAssertTrue(app.staticTexts["stats.h1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["stats.volume"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["range.30D"].isSelected)
    }

    // AC3–4 — tapping another range chip selects it.
    func testRangeChipSwitches() {
        let app = openStats()
        let sevenDay = app.buttons["range.7D"]
        XCTAssertTrue(sevenDay.waitForExistence(timeout: 5))
        sevenDay.tap()
        XCTAssertTrue(sevenDay.isSelected)
    }

    // AC1 — back returns to You.
    func testBackReturnsToYou() {
        let app = openStats()
        let back = app.buttons["stats.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.buttons["you.stats"].waitForExistence(timeout: 5))
    }
}
