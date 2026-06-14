import XCTest

/// Create flow: Library + → "Workout" launches the guided wizard
/// (Name → Targets → Schedule → Folder → Create) and lands in the workout editor;
/// the editor adds an exercise via the picker. Also: the Edit entry on Workout
/// Detail opens the editor hydrated. Runs against the in-memory mock world.
final class CreateWizardUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiMock"]   // pin to the in-memory mock world
        app.launch()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["library.h1"].waitForExistence(timeout: 5))
        return app
    }

    func testWizardCreatesWorkoutAndEditorAddsExercise() {
        let app = launch()
        app.buttons["library.create"].tap()
        let workoutPick = app.buttons["create.workout"]
        XCTAssertTrue(workoutPick.waitForExistence(timeout: 5))
        workoutPick.tap()

        // Step through the wizard (same Continue button id on every step).
        let name = app.textFields["wizard.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("UI Wizard WO")
        app.buttons["wizard.continue"].tap()          // → Targets
        app.buttons["wizard.target-Chest"].tap()
        app.buttons["wizard.continue"].tap()          // → Schedule
        app.buttons["wizard.repeat-day-1"].tap()
        app.buttons["wizard.continue"].tap()          // → Folder
        app.buttons["wizard.folder.root"].tap()
        app.buttons["wizard.continue"].tap()          // Create → editor

        // Editor opens, hydrated with the wizard's name.
        let editorName = app.textFields["workout-name"]
        XCTAssertTrue(editorName.waitForExistence(timeout: 5))
        XCTAssertEqual(editorName.value as? String, "UI Wizard WO")

        // Add an exercise via the picker. "Lat Pulldown" is in the Back group below
        // the fold; narrow with the muscle filter to bring it on-screen (XCUITest
        // won't auto-scroll a SwiftUI ScrollView).
        app.buttons["add-exercise"].tap()
        XCTAssertTrue(app.staticTexts["eyebrow-ADD EXERCISE"].waitForExistence(timeout: 5))
        app.buttons["picker-filter-Back"].tap()
        let row = app.buttons["picker-row-Lat Pulldown"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        app.buttons["picker-confirm"].tap()
        XCTAssertTrue(app.buttons["exercise-row-Lat Pulldown"].waitForExistence(timeout: 5))

        // The row opens the per-set editor.
        app.buttons["exercise-row-Lat Pulldown"].tap()
        XCTAssertTrue(app.buttons["set-editor-add"].waitForExistence(timeout: 5))
        app.buttons["set-editor-done"].tap()
    }

    func testEditEntryOpensHydratedEditor() {
        let app = launch()
        let push = app.buttons["workout.Push"]
        XCTAssertTrue(push.waitForExistence(timeout: 5))
        push.tap()
        let edit = app.buttons["workoutDetail.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(app.textFields["workout-name"].waitForExistence(timeout: 5))
    }
}
