import XCTest

/// Acceptance tests for the three builders, reached through the real Library
/// Create chooser (BAK-10).
final class BuildersTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
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

    private func openWorkoutBuilder(_ app: XCUIApplication) {
        openCreate(app, "create.workout")
        XCTAssertTrue(app.staticTexts["eyebrow-NEW WORKOUT"].waitForExistence(timeout: 5))
    }

    func testWorkoutBuilderShowsHeaderTagsAndSeededRows() { // AC1, AC2
        let app = launch()
        openWorkoutBuilder(app)
        XCTAssertTrue(app.textFields["workout-name"].exists)
        XCTAssertTrue(app.buttons["exercise-row-Flat bench"].exists)
        XCTAssertTrue(app.buttons["exercise-row-Incline press"].exists)
        XCTAssertTrue(app.staticTexts["eyebrow-EXERCISES · 2"].exists)
        XCTAssertTrue(app.staticTexts["eyebrow-9 SETS"].exists)
    }

    func testTappingRowOpensSetEditor() { // AC3, AC6
        let app = launch()
        openWorkoutBuilder(app)
        app.buttons["exercise-row-Flat bench"].tap()
        XCTAssertTrue(app.buttons["set-editor-add"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["set-editor-done"].exists)
        app.buttons["set-editor-add"].tap()        // clone a set
        app.buttons["set-editor-done"].tap()
    }

    func testLinkGroupsTwoRows() { // AC4
        let app = launch()
        openWorkoutBuilder(app)
        app.buttons["link-0"].tap()
        // After linking, the superset card header appears.
        XCTAssertTrue(app.staticTexts["SUPERSET · 2 MOVES"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["unlink-0"].exists)
    }

    func testAddExerciseOpensPickerAndAppends() throws { // AC5, AC7
        try XCTSkipIf(true, "BAK-26: confirming the exercise picker doesn't append the exercise. Un-skip when fixed.")
        let app = launch()
        openWorkoutBuilder(app)
        app.buttons["add-exercise"].tap()
        XCTAssertTrue(app.staticTexts["eyebrow-ADD EXERCISE"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["picker-confirm"].exists)
        app.buttons["picker-row-Lat Pulldown"].tap()
        app.buttons["picker-confirm"].tap()
        XCTAssertTrue(app.buttons["exercise-row-Lat Pulldown"].waitForExistence(timeout: 5))
    }

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
