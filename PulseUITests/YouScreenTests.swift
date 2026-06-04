import XCTest

final class YouScreenTests: XCTestCase {
    private func launchOnYou(_ extraArgs: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiMock"] + extraArgs
        app.launch()
        app.tabBars.buttons["You"].tap()
        return app
    }

    // AC1–AC4: top bar, profile header, three MiniStats, three NavRows render.
    func testRendersHeaderProfileStatsAndNavRows() {
        let app = launchOnYou()
        XCTAssertTrue(app.staticTexts["YOU"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["you.profileHeader"].exists)
        XCTAssertTrue(app.staticTexts["STREAK"].exists)
        XCTAssertTrue(app.staticTexts["SESSIONS"].exists)
        XCTAssertTrue(app.staticTexts["VOLUME"].exists)
        XCTAssertTrue(app.buttons["you.stats"].exists)
        XCTAssertTrue(app.buttons["you.personalRecords"].exists)
        XCTAssertTrue(app.buttons["you.workoutHistory"].exists)
    }

    // AC5: tapping a NavRow pushes the matching destination.
    func testNavRowPushesStatsDestination() {
        let app = launchOnYou()
        app.buttons["you.stats"].tap()
        XCTAssertTrue(app.staticTexts["stats.h1"].waitForExistence(timeout: 5))
    }

    func testNavRowPushesPersonalRecordsDestination() {
        let app = launchOnYou()
        app.buttons["you.personalRecords"].tap()
        XCTAssertTrue(app.staticTexts["pr.h1"].waitForExistence(timeout: 5))
    }

    func testNavRowPushesWorkoutHistoryDestination() {
        let app = launchOnYou()
        app.buttons["you.workoutHistory"].tap()
        // The History row now pushes the real WorkoutHistoryView (BAK-17), which
        // surfaces history.h1 — replacing the old placeholder marker.
        XCTAssertTrue(app.staticTexts["history.h1"].waitForExistence(timeout: 5))
    }

    // AC6–AC7: swatch picker shows both palettes; tapping switches + persists.
    func testSwatchPickerSwitchesAndPersistsPalette() {
        let app = launchOnYou()
        let coastal = app.buttons["palette-swatch-coastal"]
        let mint = app.buttons["palette-swatch-mint"]
        XCTAssertTrue(coastal.waitForExistence(timeout: 5))
        XCTAssertTrue(mint.exists)

        mint.tap()
        XCTAssertTrue(mint.isSelected)

        // Relaunch: choice persists via "pulse-pal".
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchArguments += ["-uiMock"]
        relaunched.launch()
        relaunched.tabBars.buttons["You"].tap()
        let mint2 = relaunched.buttons["palette-swatch-mint"]
        XCTAssertTrue(mint2.waitForExistence(timeout: 5))
        XCTAssertTrue(mint2.isSelected)

        // Reset back to Coastal so the test is rerunnable.
        relaunched.buttons["palette-swatch-coastal"].tap()
    }

    // AC8–AC9: preferences card shows four rows; toggling flips state.
    func testPreferencesRenderAndToggleFlips() {
        let app = launchOnYou()
        XCTAssertTrue(app.staticTexts["Units"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["KG · METRIC"].exists)
        XCTAssertTrue(app.staticTexts["Default rest timer"].exists)
        XCTAssertTrue(app.staticTexts["90s"].exists)

        let auto = app.switches["you.toggle.autoProgress"]
        XCTAssertTrue(auto.exists)
        let before = auto.value as? String
        auto.tap()
        XCTAssertNotEqual(auto.value as? String, before)
    }

    // AC10–AC11: a failing profile repo still renders the screen and keeps the
    // palette picker usable (palette is local-only, never blocked).
    func testFailingStatsStillRendersAndPaletteStillWorks() {
        let app = launchOnYou(["-uiTestYouError"])
        XCTAssertTrue(app.staticTexts["you.errorBanner"].waitForExistence(timeout: 5))
        // Screen still renders profile + preferences with defaults.
        XCTAssertTrue(app.otherElements["you.profileHeader"].exists)
        XCTAssertTrue(app.staticTexts["KG · METRIC"].exists)
        // Palette picker remains fully functional.
        let mint = app.buttons["palette-swatch-mint"]
        mint.tap()
        XCTAssertTrue(mint.isSelected)
        app.buttons["palette-swatch-coastal"].tap() // reset
    }
}
