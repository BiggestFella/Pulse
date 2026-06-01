import XCTest

final class PulseUITests: XCTestCase {
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        // The app launches into the 4-tab shell with Today selected. (The Today
        // screen now shows the date/greeting rather than a literal "Today" label,
        // so assert the tab-bar item — a data-independent launch signal.)
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 5))
    }
}
