import XCTest

/// The per-workout Settings sheet (BAK-63), opened from the Workout-Detail gear and
/// the editor `⋯` overflow. Runs against the in-memory mock world.
final class WorkoutSettingsUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiMock"]
        app.launch()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["library.h1"].waitForExistence(timeout: 5))
        return app
    }

    func testOpenSettingsFromDetailGearAndChangeRest() {
        let app = launch()
        let push = app.buttons["workout.Push"]
        XCTAssertTrue(push.waitForExistence(timeout: 5))
        push.tap()
        app.buttons["workoutDetail.settings"].tap()

        let rest = app.staticTexts["settings.rest.value"]
        XCTAssertTrue(rest.waitForExistence(timeout: 5))
        XCTAssertEqual(rest.label, "Default")               // Push has no per-workout override
        app.buttons["settings.rest.stepper.inc"].tap()      // Default → 105s (90 + 15)
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '105s'"), object: rest)
        wait(for: [updated], timeout: 3)

        app.buttons["settings.repeat-day-3"].tap()          // toggle a weekday (persists)
    }

    func testOpenSettingsFromEditorOverflow() {
        let app = launch()
        let push = app.buttons["workout.Push"]
        XCTAssertTrue(push.waitForExistence(timeout: 5))
        push.tap()
        app.buttons["workoutDetail.edit"].tap()             // → editor
        let overflow = app.buttons["builder-overflow"]
        XCTAssertTrue(overflow.waitForExistence(timeout: 5))
        overflow.tap()                                       // → settings sheet
        XCTAssertTrue(app.staticTexts["settings.rest.value"].waitForExistence(timeout: 5))
    }
}
