import XCTest

final class TodayTabTests: XCTestCase {
    private func launch(_ args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiMock"] + args
        app.launch()
        return app
    }

    // AC2/AC3 — greeting is stable ("Alex Mason" → first name); the streak and
    // eyebrow are now composed from the repositories (BAK-24), so assert the streak
    // container's presence and that the eyebrow renders in the "EEE · MMM d" format
    // rather than a fixed date string.
    func testHeaderShowsDateGreetingStreak() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Hey, Alex."].waitForExistence(timeout: 5))
        // Streak numeral renders as its own digit-only text.
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]+$")).firstMatch.exists,
                      "Expected the streak numeral")
        let eyebrow = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^[A-Z]{3} · [A-Z]{3} [0-9]{1,2}$")).firstMatch
        XCTAssertTrue(eyebrow.exists, "Expected a 'WED · MAY 28'-style date eyebrow")
    }

    // AC4/AC5 — hero card exposes its children (it uses .accessibilityElement(children: .contain)),
    // so the workout name and Start button resolve by their own identifiers. The
    // mock path pins `now` to a training day, so a hero always renders; the workout
    // name varies, so assert it is present and non-empty rather than a fixed string.
    func testHeroShowsWorkoutAndStartFires() {
        let app = launch()
        let name = app.staticTexts["today.hero.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "Expected hero workout name to exist")
        XCTAssertFalse(name.label.isEmpty, "Expected a non-empty workout name")

        // The eyebrow texts have no own id; assert their rendered (uppercased) formats.
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^DAY [0-9]+$")).firstMatch.exists,
                      "Expected a 'DAY N' hero label")
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]+ EXERCISES · ~[0-9]+ MIN$")).firstMatch.exists,
                      "Expected an 'N EXERCISES · ~M MIN' hero footer")

        let start = app.buttons["today.hero.start"]
        XCTAssertTrue(start.exists, "Expected Start button to exist in hero card")
        start.tap()   // no crash; BAK-14 hook is a no-op here
    }

    // AC6/AC7 — the progress header is composed now, so assert its "N OF M DONE"
    // format and the strip container rather than a fixed count.
    func testWeekStripRendersAndHeader() {
        let app = launch()
        let header = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^[0-9]+ OF [0-9]+ DONE$")).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5), "Expected an 'N OF M DONE' header")
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
