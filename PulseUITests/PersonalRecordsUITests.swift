import XCTest

final class PersonalRecordsUITests: XCTestCase {
    private func openPRs() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiMock"]   // pin to the in-memory mock world
        app.launch()
        app.tabBars.buttons["You"].tap()
        let link = app.buttons["you.personalRecords"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        return app
    }

    // AC1 — header + sub-line render.
    func testHeaderRenders() {
        let app = openPRs()
        XCTAssertTrue(app.staticTexts["pr.h1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["pr.subline"].exists)
    }

    // AC2/AC4 — hero card + the All chip and per-muscle chips render.
    func testHeroAndChipsRender() {
        let app = openPRs()
        XCTAssertTrue(app.staticTexts["pr.hero.name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pr.chip.All"].exists)
        XCTAssertTrue(app.buttons["pr.chip.Chest"].exists)
    }

    // AC3 — selecting a muscle chip filters: the hero re-resolves to that muscle's
    // top lift (the all-records hero is a heavier Legs lift), so the name changes.
    func testMuscleFilterChangesHero() {
        let app = openPRs()
        let hero = app.staticTexts["pr.hero.name"]
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        let allHeroName = hero.label
        app.buttons["pr.chip.Chest"].tap()
        let changed = expectation(for: NSPredicate(format: "label != %@", allHeroName),
                                  evaluatedWith: hero)
        wait(for: [changed], timeout: 3)
    }

    // AC1 — back returns to You.
    func testBackReturnsToYou() {
        let app = openPRs()
        let back = app.buttons["pr.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.buttons["you.personalRecords"].waitForExistence(timeout: 5))
    }
}
