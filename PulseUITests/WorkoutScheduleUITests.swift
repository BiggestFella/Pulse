import XCTest

/// UI acceptance test for the weekday repeat chips on WorkoutDetailView (BAK-57).
///
/// Navigation path (mock Library):
///   Library tab → root content section → "workout.Push" row (tap) →
///   WorkoutDetailView (workoutDetail.title appears) → tap repeat-day-5 (Fri) →
///   assert the chip's isSelected trait becomes true.
///
/// Why this path works in the mock world:
///   The mock store seeds Push/Pull/Legs with workoutFolderID = [:], so all three
///   appear as root-level workouts in Library (folder.contents(of: nil)). The row
///   accessibilityIdentifier is "workout.<name>" (LibraryWorkoutRow).
final class WorkoutScheduleUITests: XCTestCase {

    private func launchLibrary() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiMock"]
        app.launch()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["library.h1"].waitForExistence(timeout: 5))
        return app
    }

    /// AC: tapping a weekday chip on WorkoutDetailView toggles its selected state.
    func testToggleFridayChipOnPushWorkout() {
        let app = launchLibrary()

        // The Library root lists workouts directly (Push/Pull/Legs all have
        // workoutFolderID == nil in the mock store, so they appear at root level).
        let workoutRow = app.buttons["workout.Push"]
        XCTAssertTrue(workoutRow.waitForExistence(timeout: 5),
                      "Push workout row should be visible at Library root in mock mode")
        workoutRow.tap()

        // WorkoutDetailView should now be on screen
        XCTAssertTrue(app.staticTexts["workoutDetail.title"].waitForExistence(timeout: 5),
                      "WorkoutDetailView should appear after tapping the Push workout row")

        // Friday chip (repeat-day-5) starts unselected: Push has weekdays [1] (Mon only)
        let fridayChip = app.buttons["repeat-day-5"]
        XCTAssertTrue(fridayChip.waitForExistence(timeout: 5),
                      "repeat-day-5 chip should exist on WorkoutDetailView")
        XCTAssertFalse(fridayChip.isSelected,
                       "Friday chip should start unselected for Push (weekdays [1])")

        fridayChip.tap()

        // After tap, toggleWeekday(5) is called asynchronously; wait a moment for
        // the view to re-render with the updated weekdays set.
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true"),
            object: fridayChip)
        wait(for: [selected], timeout: 5)
        XCTAssertTrue(fridayChip.isSelected,
                      "Friday chip should be selected after tapping it")
    }
}
