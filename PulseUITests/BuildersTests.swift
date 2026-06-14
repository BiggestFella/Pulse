import XCTest

/// Acceptance tests for the three builders, reached through the real Library
/// Create chooser (BAK-10).
final class BuildersTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // Run against the in-memory mocks; the live Supabase catalog read throws
        // `.notImplemented`, leaving the exercise picker empty (BAK-26).
        app.launchArguments += ["-uiMock"]
        app.launch()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["library.h1"].waitForExistence(timeout: 5))
        return app
    }

    private func openCreate(_ app: XCUIApplication, _ pick: String) {
        app.buttons["library.create"].tap()
        let button = app.buttons[pick]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }

    // The workout create/edit flow moved to the guided wizard + editor — its
    // acceptance coverage (was the old single-screen builder's AC1–AC7: header,
    // add-via-picker, set editor) now lives in CreateWizardUITests. Linking +
    // set-editing are unit-tested in WorkoutBuilderModelTests.

    func testRoutineBuilderStepperAndSplit() { // AC8, AC9
        let app = launch()
        openCreate(app, "create.routine")
        XCTAssertTrue(app.staticTexts["eyebrow-NEW ROUTINE"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["weeks-value"].exists)
        XCTAssertTrue(app.staticTexts["eyebrow-4 WORKOUTS / WK"].exists)
        app.buttons["weeks-inc"].tap()
        XCTAssertTrue(app.staticTexts["9wks"].exists)
        app.buttons["add-rest"].tap()  // still 4 workouts/wk
        XCTAssertTrue(app.staticTexts["eyebrow-4 WORKOUTS / WK"].exists)
    }

    func testRoutineWorkoutPickerAppendsDay() { // AC10
        let app = launch()
        openCreate(app, "create.routine")
        XCTAssertTrue(app.staticTexts["eyebrow-NEW ROUTINE"].waitForExistence(timeout: 5))
        app.buttons["add-workout"].tap()
        XCTAssertTrue(app.staticTexts["eyebrow-ADD TO ROUTINE"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["wpicker-create-new"].exists)
        app.buttons["wpicker-create-new"].tap()
        XCTAssertTrue(app.staticTexts["eyebrow-5 WORKOUTS / WK"].waitForExistence(timeout: 5))
    }

    func testFolderBuilderSwatchSelection() { // AC11
        let app = launch()
        openCreate(app, "create.folder")
        XCTAssertTrue(app.staticTexts["eyebrow-NEW FOLDER"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["folder-preview"].exists)
        XCTAssertTrue(app.textFields["folder-name"].exists)
        app.buttons["swatch-purple"].tap()
        XCTAssertTrue(app.buttons["swatch-purple"].isSelected)
    }

    func testCancelPopsBackToLibrary() { // AC12
        let app = launch()
        openCreate(app, "create.folder")
        XCTAssertTrue(app.staticTexts["eyebrow-NEW FOLDER"].waitForExistence(timeout: 5))
        app.buttons["builder-cancel"].tap()
        XCTAssertTrue(app.staticTexts["library.h1"].waitForExistence(timeout: 5))
    }

    func testSavePopsBackToLibrary() { // AC12
        let app = launch()
        openCreate(app, "create.folder")
        XCTAssertTrue(app.staticTexts["eyebrow-NEW FOLDER"].waitForExistence(timeout: 5))
        app.buttons["builder-primary"].tap()
        XCTAssertTrue(app.staticTexts["library.h1"].waitForExistence(timeout: 5))
    }
}
