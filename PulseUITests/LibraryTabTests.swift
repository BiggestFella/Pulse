import XCTest

final class LibraryTabTests: XCTestCase {
    private func openLibrary() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["library.h1"].waitForExistence(timeout: 5))
        return app
    }

    // AC1/AC2 — header, chips, and the folders section render.
    func testHeaderChipsAndFolders() {
        let app = openLibrary()
        XCTAssertTrue(app.buttons["chip.all"].exists)
        XCTAssertTrue(app.buttons["chip.exercises"].exists)
        XCTAssertTrue(app.buttons["folder.ppl"].waitForExistence(timeout: 5))
    }

    // AC6/AC3 — Browse exercises (and the Exercises chip) shows the grouped catalog.
    func testBrowseExercisesShowsCatalog() {
        let app = openLibrary()
        app.buttons["chip.exercises"].tap()
        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 5))
    }

    // AC5 — tapping the program folder routes to Program Detail (stub marker).
    func testProgramFolderRoutes() {
        let app = openLibrary()
        let folder = app.buttons["folder.ppl"]
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        folder.tap()
        XCTAssertTrue(app.staticTexts["route.program:ppl"].waitForExistence(timeout: 5))
    }

    // AC7/AC8 — the Create chooser opens and routes to the Workout Builder (stub).
    func testCreateChooserRoutesToWorkoutBuilder() {
        let app = openLibrary()
        app.buttons["library.create"].tap()
        let workout = app.buttons["create.workout"]
        XCTAssertTrue(workout.waitForExistence(timeout: 5))
        workout.tap()
        XCTAssertTrue(app.staticTexts["route.builder:workout"].waitForExistence(timeout: 5))
    }

    // AC7 — the Create chooser dismisses via its close control.
    func testCreateChooserCloses() {
        let app = openLibrary()
        app.buttons["library.create"].tap()
        XCTAssertTrue(app.buttons["create.workout"].waitForExistence(timeout: 5))
        app.buttons["create.close"].tap()
        XCTAssertFalse(app.buttons["create.workout"].waitForExistence(timeout: 2))
    }
}
