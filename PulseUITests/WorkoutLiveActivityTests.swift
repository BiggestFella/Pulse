import XCTest

final class WorkoutLiveActivityTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false // avoid cascading failures against an unrendered UI
    }

    // AC2/AC6: rest surface shows the ring + UP NEXT preview
    func testRestSurfaceShowsRingAndUpNext() {
        let app = XCUIApplication()
        app.launchArguments = ["-LA_DEBUG_REST"]
        app.launch()
        XCTAssertTrue(app.otherElements["la-rest-ring"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.otherElements["la-up-next"].exists)
        XCTAssertTrue(app.staticTexts["UP NEXT"].exists)
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
