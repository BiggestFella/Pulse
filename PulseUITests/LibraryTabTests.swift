import XCTest

final class LibraryTabTests: XCTestCase {
    private func openLibrary() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiMock"]   // pin to the in-memory mock world
        app.launch()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["library.h1"].waitForExistence(timeout: 5))
        return app
    }

    // AC1/AC2 — header, chips, and the programs section render. The mock world
    // seeds one program ("Push / Pull / Legs") shown under PROGRAMS with a
    // UUID-based row id, so match the `program.` identifier prefix.
    func testHeaderChipsAndFolders() {
        let app = openLibrary()
        XCTAssertTrue(app.buttons["chip.all"].exists)
        XCTAssertTrue(app.buttons["chip.exercises"].exists)
        let program = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "program.")).firstMatch
        XCTAssertTrue(program.waitForExistence(timeout: 5), "Expected a seeded program row")
    }

    // AC6/AC3 — Browse exercises (and the Exercises chip) shows the grouped catalog.
    func testBrowseExercisesShowsCatalog() {
        let app = openLibrary()
        app.buttons["chip.exercises"].tap()
        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 5))
    }

    // AC5 — tapping the seeded program routes to Program Detail (stub marker
    // `route.program:<id>`, where id is the program's UUID).
    func testProgramFolderRoutes() {
        let app = openLibrary()
        let program = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "program.")).firstMatch
        XCTAssertTrue(program.waitForExistence(timeout: 5))
        program.tap()
        let marker = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "route.program:")).firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 5), "Expected program detail route marker")
    }

    // AC7/AC8 — the Create chooser opens and routes to the Workout Builder
    // (BAK-18 — the real builder now replaces the routing stub).
    func testCreateChooserRoutesToWorkoutBuilder() {
        let app = openLibrary()
        app.buttons["library.create"].tap()
        let workout = app.buttons["create.workout"]
        XCTAssertTrue(workout.waitForExistence(timeout: 5))
        workout.tap()
        XCTAssertTrue(app.staticTexts["eyebrow-NEW WORKOUT"].waitForExistence(timeout: 5))
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
