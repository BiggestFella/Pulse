import XCTest

final class WorkoutLiveActivityTests: XCTestCase {
    // AC2/AC6: rest surface shows the ring + UP NEXT preview
    func testRestSurfaceShowsRingAndUpNext() {
        let app = XCUIApplication()
        app.launchArguments = ["-LA_DEBUG_REST"]
        app.launch()
        XCTAssertTrue(app.otherElements["la-rest-ring"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["UP NEXT"].waitForExistence(timeout: 5))
    }

    // AC4/AC5: failure set shows ∞ / TO FAILURE / FAILURE label and NO weight
    func testFailureSurfaceShowsInfinityAndLabel() {
        let app = XCUIApplication()
        app.launchArguments = ["-LA_DEBUG_FAILURE"]
        app.launch()
        XCTAssertTrue(app.otherElements["la-set-lockup"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["FAILURE"].exists)
        XCTAssertTrue(app.staticTexts["∞"].exists)
        XCTAssertTrue(app.staticTexts["TO FAILURE"].exists)
        XCTAssertFalse(app.staticTexts["KG"].exists)
    }
}
