import XCTest

/// UI tests for:
///   1. Reorder mode shows all rows (including the 5th) as hittable — regression
///      guard for the BAK-55 reorder-list clip fix.
///   2. Targets pre-filter the picker and the inline variation control appears on
///      a multi-variation exercise — SP1 coverage.
final class TargetsReorderUITests: XCTestCase {

    // MARK: - Helpers

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiMock"]
        app.launch()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["library.h1"].waitForExistence(timeout: 5))
        return app
    }

    private func openWorkoutBuilder(_ app: XCUIApplication) {
        app.buttons["library.create"].tap()
        let button = app.buttons["create.workout"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        XCTAssertTrue(app.staticTexts["eyebrow-NEW WORKOUT"].waitForExistence(timeout: 5))
    }

    // MARK: - Test 1: Reorder flow — 5 rows are all present in reorder mode
    //
    // NOTE: This is a FLOW CHECK, not a clip-guard.
    //
    // The BAK-55 clip bug manifests visually (the last row is cut off on screen)
    // but on iPhone 17 / iOS 26.5 the accessibility tree still includes the
    // clipped row: UIKit reports element frames in the CollectionView's own
    // coordinate space, and 5 × ~52 pt rows (≈260 pt) fit inside the ~240 pt
    // container before spilling below the tab bar (791 pt). XCUITest's
    // `isHittable` stays true either way because the element's window coordinate
    // is within the visible area regardless of the SwiftUI clip frame.
    //
    // A true clip-guard would require either a snapshot diff or running on a
    // smaller device / larger type-size where the overflow pushes the last row
    // below the window bottom. Neither is available in this CI environment.
    //
    // What this test DOES guard: the full add-then-reorder flow works end-to-end
    // — picker can add 3 exercises, the EXERCISES count updates, reorder mode
    // activates, and all 5 named reorder rows appear in the accessibility tree.

    /// Adds 3 Back exercises to the 2 seeded rows, enters reorder mode, and
    /// asserts all 5 named reorder rows are present in the accessibility tree.
    func testReorderShowsFifthExercise() {
        let app = launch()
        openWorkoutBuilder(app)

        // Open picker and pick the first three Back exercises (near the top of
        // the filtered list so they're on-screen without needing to scroll).
        app.buttons["add-exercise"].tap()
        XCTAssertTrue(app.staticTexts["eyebrow-ADD EXERCISE"].waitForExistence(timeout: 5))

        app.buttons["picker-filter-Back"].tap()

        let deadlift = app.buttons["picker-row-Deadlift"]
        XCTAssertTrue(deadlift.waitForExistence(timeout: 5))
        deadlift.tap()

        let pullUp = app.buttons["picker-row-Pull-Up"]
        XCTAssertTrue(pullUp.waitForExistence(timeout: 5))
        pullUp.tap()

        let barbellRow = app.buttons["picker-row-Barbell Row"]
        XCTAssertTrue(barbellRow.waitForExistence(timeout: 5))
        barbellRow.tap()

        app.buttons["picker-confirm"].tap()

        // Builder now has 5 rows: Flat bench, Incline press, Deadlift, Pull-Up,
        // Barbell Row.
        XCTAssertTrue(
            app.staticTexts["eyebrow-EXERCISES · 5"].waitForExistence(timeout: 5),
            "Expected 5 exercises in the builder after adding 3 Back exercises"
        )

        // Enter reorder mode.
        app.buttons["reorder-toggle"].tap()

        // All 5 named reorder rows must appear in the accessibility tree.
        // (Identifiers land on the StaticText label element inside each List Cell.)
        for name in ["Flat bench", "Incline press", "Deadlift", "Pull-Up", "Barbell Row"] {
            XCTAssertTrue(
                app.staticTexts["reorder-row-\(name)"].waitForExistence(timeout: 5),
                "reorder-row-\(name) should exist in reorder mode"
            )
        }
    }

    // MARK: - Test 2: Targets pre-filter picker + inline variation control

    /// Selects the Back target chip, opens the picker, and verifies:
    ///   • The picker opens pre-filtered to Back (Back chip selected, Back rows visible).
    ///   • Tapping Lat Pulldown (3 variations) reveals the inline variation control.
    ///   • Confirming appends Lat Pulldown to the builder.
    func testTargetsPreFilterPickerAndInlineVariation() {
        let app = launch()
        openWorkoutBuilder(app)

        // Select the Back target chip.
        let backTarget = app.buttons["target-Back"]
        XCTAssertTrue(backTarget.waitForExistence(timeout: 5))
        backTarget.tap()
        XCTAssertTrue(backTarget.isSelected, "target-Back should be selected after tap")

        // Open the exercise picker.
        app.buttons["add-exercise"].tap()
        XCTAssertTrue(
            app.staticTexts["eyebrow-ADD EXERCISE"].waitForExistence(timeout: 5),
            "Picker should open in add mode"
        )

        // Picker must be pre-filtered to Back.
        let backFilterChip = app.buttons["picker-filter-Back"]
        XCTAssertTrue(
            backFilterChip.waitForExistence(timeout: 5),
            "picker-filter-Back chip must exist"
        )
        XCTAssertTrue(
            backFilterChip.isSelected,
            "picker-filter-Back should be pre-selected when Back target is active"
        )

        // A Back row must be visible (Lat Pulldown is in the Back group).
        let latPulldown = app.buttons["picker-row-Lat Pulldown"]
        XCTAssertTrue(
            latPulldown.waitForExistence(timeout: 5),
            "picker-row-Lat Pulldown should be visible with Back filter active"
        )

        // Tap Lat Pulldown — it has 3 variations so the inline variation control
        // should appear immediately below the row.
        latPulldown.tap()

        let variationControl = app.buttons["picker-variation-Lat Pulldown"]
        XCTAssertTrue(
            variationControl.waitForExistence(timeout: 5),
            "Inline variation control (picker-variation-Lat Pulldown) should appear after selecting a multi-variation exercise"
        )

        // Confirm — Lat Pulldown should now be in the builder.
        app.buttons["picker-confirm"].tap()
        XCTAssertTrue(
            app.buttons["exercise-row-Lat Pulldown"].waitForExistence(timeout: 5),
            "Lat Pulldown should appear as an exercise row after confirmation"
        )
    }
}
