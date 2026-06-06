import XCTest

final class ActiveWorkoutFlowTests: XCTestCase {

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiMock"]   // pin to the in-memory mock world
        app.launch()
        return app
    }

    /// Start the sample workout from Today's hero and advance pre → active.
    private func startAndBegin(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["today.hero.start"].waitForExistence(timeout: 5))
        app.buttons["today.hero.start"].tap()
        XCTAssertTrue(app.buttons["pre.begin"].waitForExistence(timeout: 5))
        app.buttons["pre.begin"].tap()
        XCTAssertTrue(app.buttons["active.log"].waitForExistence(timeout: 5))
    }

    // AC1 — start hides the tab bar (takeover).
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

    // AC2 — Begin moves pre → active.
    func testBeginMovesToActive() {
        let app = launch()
        app.buttons["today.hero.start"].tap()
        XCTAssertTrue(app.buttons["pre.begin"].waitForExistence(timeout: 5))
        app.buttons["pre.begin"].tap()
        XCTAssertTrue(app.buttons["active.log"].waitForExistence(timeout: 5))
    }

    // AC17 — back from pre ends the workout, restoring the tab bar.
    func testBackFromPreReturnsToTodayWithTabBar() {
        let app = launch()
        app.buttons["today.hero.start"].tap()
        XCTAssertTrue(app.buttons["pre.back"].waitForExistence(timeout: 5))
        app.buttons["pre.back"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
    }

    // AC6 / AC12 — Log-button label + failure rendering (∞ hero, hidden steppers, BODYWEIGHT).
    func testLogLabelAndFailureRendering() {
        let app = launch()
        startAndBegin(app)
        XCTAssertEqual(app.buttons["active.log"].label, "Log set")   // step 0 = warmup, non-superset
        app.buttons["active.chip.jump"].tap()
        XCTAssertTrue(app.buttons["jump.exercise.4"].waitForExistence(timeout: 3))
        app.buttons["jump.exercise.4"].tap()                          // failure finisher = last step
        XCTAssertTrue(app.buttons["active.log"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["active.log"].label, "Finish workout")
        XCTAssertFalse(app.buttons["active.stepper.weight.inc"].exists) // steppers hidden on failure
        XCTAssertEqual(app.staticTexts["active.hero.footer"].label, "BODYWEIGHT")
    }

    // AC11 — swap shows the swapped eyebrow.
    func testSwapShowsSwappedEyebrow() {
        let app = launch()
        startAndBegin(app)
        app.buttons["active.chip.swap"].tap()
        XCTAssertTrue(app.buttons["swap.alt.0"].waitForExistence(timeout: 3))
        app.buttons["swap.alt.0"].tap()
        let swapped = expectation(for: NSPredicate(format: "label CONTAINS 'SWAPPED'"),
                                  evaluatedWith: app.staticTexts["active.eyebrow"])
        wait(for: [swapped], timeout: 3)
    }

    // AC10 — jump lands on the chosen exercise (superset eyebrow carries "1A").
    func testJumpLandsOnExercise() {
        let app = launch()
        startAndBegin(app)
        app.buttons["active.chip.jump"].tap()
        XCTAssertTrue(app.buttons["jump.exercise.2"].waitForExistence(timeout: 3))
        app.buttons["jump.exercise.2"].tap()
        XCTAssertTrue(app.buttons["active.log"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["active.eyebrow"].label.contains("1A"))
    }

    // AC7 / AC8 — logging a non-superset set shows rest; chips adjust; skip → active.
    func testRestAppearsAndChipsAdjust() {
        let app = launch()
        startAndBegin(app)
        app.buttons["active.log"].tap()                               // log step 0 → rest
        XCTAssertTrue(app.buttons["rest.skip"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["rest.adjust.30"].exists)
        app.buttons["rest.adjust.30"].tap()
        XCTAssertTrue(app.staticTexts["rest.time"].exists)
        app.buttons["rest.skip"].tap()
        XCTAssertTrue(app.buttons["active.log"].waitForExistence(timeout: 3))
    }

    // AC16 / AC17 — run to the summary; Done returns to Today with the tab bar.
    func testSummaryShowsAndDoneReturnsToTabBar() {
        let app = launch()
        startAndBegin(app)
        for _ in 0..<30 {
            if app.buttons["summary.done"].exists { break }
            if app.buttons["active.log"].exists { app.buttons["active.log"].tap() }
            else if app.buttons["rest.skip"].exists { app.buttons["rest.skip"].tap() }
        }
        XCTAssertTrue(app.buttons["summary.done"].waitForExistence(timeout: 3))
        app.buttons["summary.done"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 3))
    }
}
