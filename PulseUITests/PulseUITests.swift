import XCTest

final class PulseUITests: XCTestCase {
    func testAppLaunchesWithMockData() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiMock"]   // force the mock-backed composition root
        app.launch()
        // The app launches into the 4-tab shell with Today selected. (The Today
        // screen shows the date/greeting rather than a literal "Today" label,
        // so assert the tab-bar item — a data-independent launch signal.)
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 5))
    }
}
