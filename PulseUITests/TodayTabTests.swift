import XCTest

final class TodayTabTests: XCTestCase {
    private func launch(_ args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiMock"] + args
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

    // AC4/AC5 — hero card exposes its children (it uses .accessibilityElement(children: .contain)),
    // so the workout name and Start button resolve by their own identifiers.
    func testHeroShowsWorkoutAndStartFires() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["WED · MAY 28"].waitForExistence(timeout: 5))

        // The workout name carries id 'today.hero.name'.
        let name = app.staticTexts["today.hero.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "Expected hero workout name to exist")
        XCTAssertEqual(name.label, "Chest & Tris")

        // The eyebrow texts have no own id; assert their rendered (uppercased) labels.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "DAY 23")).firstMatch.exists,
                      "Expected hero day label 'DAY 23'")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "7 EXERCISES · ~60 MIN")).firstMatch.exists,
                      "Expected hero footer '7 EXERCISES · ~60 MIN'")

        let start = app.buttons["today.hero.start"]
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

    // AC9/AC11 — error state exposes the retry button by its own id (container uses .contain).
    func testErrorShowsRetry() {
        let app = launch(["-uiTestError"])
        let retry = app.buttons["today.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5), "Expected Retry button to appear in error state")
        XCTAssertEqual(retry.label, "Retry", "Expected button label to be 'Retry'")
    }
}
