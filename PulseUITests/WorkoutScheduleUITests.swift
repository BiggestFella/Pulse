import XCTest

/// UI acceptance test for the weekday repeat chips — now inside the per-workout
/// Settings sheet (BAK-63; they lived on WorkoutDetailView under BAK-57).
///
/// Navigation path (mock Library):
///   Library tab → "workout.Push" row → WorkoutDetailView → gear
///   (workoutDetail.settings) → Settings sheet → tap settings.repeat-day-5 (Fri) →
///   assert the chip's isSelected trait becomes true.
final class WorkoutScheduleUITests: XCTestCase {

    private func launchLibrary() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiMock"]
        app.launch()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["library.h1"].waitForExistence(timeout: 5))
        return app
    }

    /// AC: tapping a weekday chip in the Settings sheet toggles its selected state.
    func testToggleFridayChipInSettingsSheet() {
        let app = launchLibrary()

        // The Library root lists workouts directly (Push/Pull/Legs all have
        // workoutFolderID == nil in the mock store, so they appear at root level).
        let workoutRow = app.buttons["workout.Push"]
        XCTAssertTrue(workoutRow.waitForExistence(timeout: 5),
                      "Push workout row should be visible at Library root in mock mode")
        workoutRow.tap()

        XCTAssertTrue(app.staticTexts["workoutDetail.title"].waitForExistence(timeout: 5),
                      "WorkoutDetailView should appear after tapping the Push workout row")

        // Open the per-workout Settings sheet via the gear.
        app.buttons["workoutDetail.settings"].tap()

        // Friday chip starts unselected: Push has weekdays [1] (Mon only).
        let fridayChip = app.buttons["settings.repeat-day-5"]
        XCTAssertTrue(fridayChip.waitForExistence(timeout: 5),
                      "settings.repeat-day-5 chip should exist in the Settings sheet")
        XCTAssertFalse(fridayChip.isSelected,
                       "Friday chip should start unselected for Push (weekdays [1])")

        fridayChip.tap()

        // toggleWeekday(5) persists asynchronously; wait for the chip to re-render.
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true"),
            object: fridayChip)
        wait(for: [selected], timeout: 5)
        XCTAssertTrue(fridayChip.isSelected,
                      "Friday chip should be selected after tapping it")
    }
}
