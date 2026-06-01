import XCTest

final class TodayTabTests: XCTestCase {
    private func launch(_ args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += args
        app.launch()
        return app
    }

    // AC2/AC3
    func testHeaderShowsDateGreetingStreak() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["WED · MAY 28"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Hey, Alex."].exists)
        XCTAssertTrue(app.staticTexts["27"].exists)
    }

    // AC4/AC5 — Hero card elements inherit id='today.hero' from the card container.
    // Use label-predicate matching for texts; the Start button is accessible via id='today.hero'.
    func testHeroShowsWorkoutAndStartFires() {
        let app = launch()
        // Wait for the loaded state to appear (date eyebrow visible means content is ready).
        XCTAssertTrue(app.staticTexts["WED · MAY 28"].waitForExistence(timeout: 5))

        // "DAY 23" rendered by Eyebrow (uppercased). Its label is "DAY 23" even though the
        // accessibility identifier is propagated from the hero container as "today.hero".
        let day23 = app.staticTexts.matching(NSPredicate(format: "label == %@", "DAY 23")).firstMatch
        XCTAssertTrue(day23.exists, "Expected hero day label 'DAY 23' to exist")

        let name = app.staticTexts.matching(NSPredicate(format: "label == %@", "Chest & Tris")).firstMatch
        XCTAssertTrue(name.exists, "Expected hero workout name 'Chest & Tris' to exist")

        let footer = app.staticTexts.matching(NSPredicate(format: "label == %@", "7 EXERCISES · ~60 MIN")).firstMatch
        XCTAssertTrue(footer.exists, "Expected hero footer '7 EXERCISES · ~60 MIN' to exist")

        // The Start button inherits id='today.hero' from the card VStack. Label='Start'.
        let start = app.buttons.matching(NSPredicate(format: "label == %@", "Start")).firstMatch
        XCTAssertTrue(start.exists, "Expected Start button to exist in hero card")
        start.tap()   // no crash; BAK-14 hook is a no-op here
    }

    // AC6/AC7
    func testWeekStripRendersAndHeader() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["3 OF 5 DONE"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["today.weekStrip"].exists)
    }

    // AC8
    func testYesterdayRowPushesSessionDetail() {
        let app = launch()
        let row = app.buttons["today.yesterday"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.staticTexts["Session Detail"].waitForExistence(timeout: 5))
    }

    // AC10
    func testRestDayShowsNoStart() {
        let app = launch(["-uiTestRestDay"])
        XCTAssertTrue(app.staticTexts["Rest day."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["today.hero.start"].exists)
    }

    // AC9/AC11 — The error VStack has id='today.error'; the Retry button inside inherits
    // this identifier. Find it by that id (label='Retry').
    func testErrorShowsRetry() {
        let app = launch(["-uiTestError"])
        let retry = app.buttons["today.error"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5), "Expected Retry button (id='today.error') to appear in error state")
        XCTAssertEqual(retry.label, "Retry", "Expected button label to be 'Retry'")
    }
}
