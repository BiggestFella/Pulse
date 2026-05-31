import XCTest

final class DesignSystemUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    /// Launch the app in gallery mode and wait for the gallery scroll view to appear.
    /// Correction vs. plan: `design-system-gallery` is a ScrollView, not an Other element;
    /// use `scrollViews` query instead of `otherElements`.
    private func launchGallery() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestGallery"]
        app.launch()
        XCTAssertTrue(app.scrollViews["design-system-gallery"].waitForExistence(timeout: 5))
        return app
    }

    // AC9: Lockup renders; failure variant (∞) exists.
    // Correction vs. plan: `gallery-lockup` identifier propagates to child StaticTexts,
    // not to an Other container; query the first matching staticText.
    func testLockupAndFailureRender() {
        let app = launchGallery()
        XCTAssertTrue(app.staticTexts.matching(identifier: "gallery-lockup").firstMatch.exists)
        XCTAssertTrue(app.staticTexts["∞"].exists)
    }

    // AC5–7: primary buttons of each size exist and fire once.
    // Correction vs. plan: `.eyebrow` style uppercases the fired-counter text visually;
    // accessibility label is "FIRED: 1", not "Fired: 1". Use the `gallery-fired-count`
    // identifier to avoid depending on exact casing.
    func testPrimaryButtonFiresOnce() {
        let app = launchGallery()
        XCTAssertTrue(app.buttons["gallery-primary-lg"].exists)
        XCTAssertTrue(app.buttons["gallery-primary-md"].exists)
        XCTAssertTrue(app.buttons["gallery-primary-sm"].exists)
        app.buttons["gallery-primary-md"].tap()
        let counter = app.staticTexts["gallery-fired-count"]
        XCTAssertTrue(counter.waitForExistence(timeout: 2))
        // Accept either cased form since the eyebrow style uppercases visually.
        let label = counter.label
        XCTAssertTrue(label == "Fired: 1" || label == "FIRED: 1",
                      "Expected fired counter to show 1, got: \(label)")
    }

    // AC8: disabled button does not fire.
    func testDisabledButtonDoesNotFire() {
        let app = launchGallery()
        let disabled = app.buttons["gallery-disabled"]
        XCTAssertTrue(disabled.exists)
        XCTAssertFalse(disabled.isEnabled)
    }

    // AC10: sheet presents, ✕ dismisses it.
    func testSheetPresentsAndCloseButtonDismisses() {
        let app = launchGallery()
        app.buttons["gallery-open-sheet"].tap()
        XCTAssertTrue(app.otherElements["pulse-sheet"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["sheet-body"].exists)
        app.buttons["sheet-close"].tap()
        XCTAssertFalse(app.staticTexts["sheet-body"].waitForExistence(timeout: 2))
    }

    // AC3/AC12: selecting Mint marks it selected; selecting Coastal reverts.
    func testPalettePickerSelectsAndReverts() {
        let app = launchGallery()
        let mint = app.buttons["palette-swatch-mint"]
        let coastal = app.buttons["palette-swatch-coastal"]
        XCTAssertTrue(mint.waitForExistence(timeout: 3))
        mint.tap()
        XCTAssertTrue(mint.isSelected)
        coastal.tap()
        XCTAssertTrue(coastal.isSelected)
    }

    // AC1–2: first launch defaults to Coastal; selection persists across relaunch.
    func testPalettePersistsAcrossRelaunch() {
        let app = launchGallery()
        XCTAssertTrue(app.buttons["palette-swatch-coastal"].isSelected) // AC1/AC2 default
        app.buttons["palette-swatch-mint"].tap()
        XCTAssertTrue(app.buttons["palette-swatch-mint"].isSelected)

        app.terminate()
        let relaunch = XCUIApplication()
        relaunch.launchArguments += ["-uiTestGallery"]
        relaunch.launch()
        XCTAssertTrue(relaunch.buttons["palette-swatch-mint"].waitForExistence(timeout: 5))
        XCTAssertTrue(relaunch.buttons["palette-swatch-mint"].isSelected)

        // Reset preference so other tests start from Coastal.
        relaunch.buttons["palette-swatch-coastal"].tap()
    }
}
