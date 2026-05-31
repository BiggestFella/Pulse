import XCTest

final class PulseUITests: XCTestCase {
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5))
    }
}
