import XCTest

/// Acceptance tests for Exercise Detail (BAK-11), mapped to the spec's criteria.
/// Navigates Library → Exercise Detail and asserts the rendered structure that is
/// deterministic against the seeded mock store.
final class ExerciseDetailUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiMock"]
        app.launch()
        return app
    }

    private func openLibrary(_ app: XCUIApplication) {
        app.tabBars.buttons["Library"].tap()
    }

    private func openExercise(_ app: XCUIApplication, _ name: String) {
        openLibrary(app)
        // The merged Library shows folders/recent by default; the exercise catalog
        // is revealed by the Exercises filter chip.
        let exercisesChip = app.buttons["chip.exercises"]
        XCTAssertTrue(exercisesChip.waitForExistence(timeout: 8), "exercises filter should exist")
        exercisesChip.tap()
        let row = app.buttons["library.exercise.\(name)"]
        XCTAssertTrue(row.waitForExistence(timeout: 8), "row \(name) should exist")
        row.tap()
    }

    // AC1 + AC2 + AC11: navigate in, header reflects exercise, back returns.
    func testNavigateInHeaderAndBack() {
        let app = launch()
        openExercise(app, "Bench Press")

        let title = app.staticTexts["exdetail.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        XCTAssertEqual(title.label, "Bench Press.")

        let eyebrow = app.staticTexts["exdetail.eyebrow"]
        XCTAssertTrue(eyebrow.exists)
        XCTAssertTrue(eyebrow.label.hasPrefix("CHEST"))

        app.buttons["exdetail.back"].tap()
        // Back returns to the Library catalog (no "Library" nav-bar title in the
        // merged Library); assert the catalog row is visible again.
        XCTAssertTrue(app.buttons["library.exercise.Bench Press"].waitForExistence(timeout: 8))
    }

    // AC3 + AC4 + AC5: multi-variation shows pills; PB card present.
    func testMultiVariationShowsPillsAndPB() {
        let app = launch()
        openExercise(app, "Bench Press")
        XCTAssertTrue(app.otherElements["exdetail.variationPills"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.otherElements["exdetail.pbCard"].waitForExistence(timeout: 8))
    }

    // AC3: a single-variation exercise shows no pill row.
    func testSingleVariationHidesPills() {
        let app = launch()
        openExercise(app, "Push-Up")  // single "Bodyweight" variation
        XCTAssertTrue(app.staticTexts["exdetail.title"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.otherElements["exdetail.variationPills"].exists)
    }

    // AC5: a bodyweight exercise (top weight 0) hides the PB card.
    func testBodyweightHidesPBCard() {
        let app = launch()
        openExercise(app, "Push-Up")
        XCTAssertTrue(app.staticTexts["exdetail.title"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.otherElements["exdetail.pbCard"].exists)
    }

    // AC6 + AC7: chart and sessions list render for a logged exercise.
    func testChartAndSessionsRender() {
        let app = launch()
        openExercise(app, "Bench Press")
        XCTAssertTrue(app.otherElements["exdetail.volumeChart"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.otherElements["exdetail.sessionsList"].exists)
    }
}
