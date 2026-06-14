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

    // AC6 / AC12 — the Log button reads "Log set" on a normal step and
    // "Finish workout" on the final step. (Failure-set rendering — steppers + the
    // BODYWEIGHT footer, BAK-30 — is unit-covered in ActiveWorkoutModelTests; the
    // mock Start now launches the scheduled SampleData workout (BAK-57), which has
    // no failure set, so it can't be exercised through this UI path. BAK-61.)
    func testLogLabelOnNormalAndFinalStep() {
        let app = launch()
        startAndBegin(app)
        XCTAssertEqual(app.buttons["active.log"].label, "Log set")   // step 0 = warmup, non-superset

        // Drive to the end; the final set's Log button must read "Finish workout".
        var sawFinish = false
        for _ in 0..<40 {
            if app.buttons["summary.done"].exists { break }
            if app.buttons["active.log"].exists {
                if app.buttons["active.log"].label == "Finish workout" { sawFinish = true }
                app.buttons["active.log"].tap()
            } else if app.buttons["rest.skip"].exists {
                app.buttons["rest.skip"].tap()
            }
        }
        XCTAssertTrue(sawFinish, "the final set's Log button should read 'Finish workout'")
    }

    // BAK-29 — the − stepper reliably decrements (regression for the slow/
    // unresponsive minus button; the fix gives both buttons a full 44pt target).
    func testMinusStepperDecrementsWeight() {
        let app = launch()
        startAndBegin(app)                                            // step 0 seeds weight 60 kg
        let value = app.staticTexts["active.stepper.weight.value"]
        XCTAssertTrue(value.waitForExistence(timeout: 3))
        XCTAssertEqual(value.label, "60 kg")
        app.buttons["active.stepper.weight.dec"].tap()
        XCTAssertEqual(value.label, "57.5 kg")
    }

    // BAK-28 — tap the value and type an exact weight (off the 2.5 boundary).
    func testManualWeightEntryUpdatesValue() {
        let app = launch()
        startAndBegin(app)
        app.staticTexts["active.stepper.weight.value"].tap()
        let field = app.textFields["active.stepper.weight.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("47.5")
        app.buttons["active.stepper.weight.done"].tap()
        XCTAssertEqual(app.staticTexts["active.stepper.weight.value"].label, "47.5 kg")
    }

    // BAK-31 — a failed save is visible and retryable; a successful retry returns
    // to the tab bar (the workout is never silently dropped).
    func testSaveFailureSurfacesErrorThenRetrySucceeds() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiMock", "-uiTestSaveFail"]
        app.launch()
        XCTAssertTrue(app.buttons["today.hero.start"].waitForExistence(timeout: 5))
        app.buttons["today.hero.start"].tap()
        app.buttons["pre.begin"].tap()
        for _ in 0..<30 {
            if app.buttons["summary.done"].exists { break }
            if app.buttons["active.log"].exists { app.buttons["active.log"].tap() }
            else if app.buttons["rest.skip"].exists { app.buttons["rest.skip"].tap() }
        }
        XCTAssertTrue(app.buttons["summary.done"].waitForExistence(timeout: 5))
        app.buttons["summary.done"].tap()                            // first save throws
        let retry = expectation(for: NSPredicate(format: "label == 'Retry save'"),
                                evaluatedWith: app.buttons["summary.done"])
        wait(for: [retry], timeout: 20)
        XCTAssertTrue(app.staticTexts["summary.saveError"].exists
                      || app.otherElements["summary.saveError"].exists)
        app.buttons["summary.done"].tap()                            // retry succeeds
        // Back on Today: query a concrete element rather than the TabBar container,
        // which can be slow to re-expose after the takeover on a loaded runner.
        XCTAssertTrue(app.buttons["today.hero.start"].waitForExistence(timeout: 15))
    }

    // BAK-32 — finishing offline buffers the session on-device: the summary shows
    // the calm "saved on device" note (non-blocking), Done returns to the tab bar,
    // and the Today tab shows a persistent "pending sync" indicator.
    func testOfflineFinishBuffersAndShowsPendingSyncIndicator() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiMock", "-uiTestOffline"]
        app.launch()
        XCTAssertTrue(app.buttons["today.hero.start"].waitForExistence(timeout: 5))
        app.buttons["today.hero.start"].tap()
        app.buttons["pre.begin"].tap()
        for _ in 0..<30 {
            if app.buttons["summary.done"].exists { break }
            if app.buttons["active.log"].exists { app.buttons["active.log"].tap() }
            else if app.buttons["rest.skip"].exists { app.buttons["rest.skip"].tap() }
        }
        XCTAssertTrue(app.buttons["summary.done"].waitForExistence(timeout: 5))
        app.buttons["summary.done"].tap()                            // offline save → buffered
        // Calm pending-sync note appears (info, not the blocking error). Generous
        // timeout: the save Task does file I/O and CI runners can be heavily starved.
        XCTAssertTrue(app.staticTexts["summary.pendingSync"].waitForExistence(timeout: 40))
        app.buttons["summary.done"].tap()                            // Done → tear down to Today
        // The global indicator is visible after leaving the summary (a reliable
        // Button query — its presence also confirms we're back on the Today tab).
        XCTAssertTrue(app.buttons["today.pendingSync"].waitForExistence(timeout: 40))
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
        XCTAssertTrue(app.buttons["summary.done"].waitForExistence(timeout: 5))
        app.buttons["summary.done"].tap()
        // Query a concrete Today element rather than the TabBar container, which
        // can be slow to re-expose after the takeover on a loaded runner.
        XCTAssertTrue(app.buttons["today.hero.start"].waitForExistence(timeout: 15))
    }
}
