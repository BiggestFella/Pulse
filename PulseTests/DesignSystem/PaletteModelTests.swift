import XCTest
@testable import Pulse

final class PaletteModelTests: XCTestCase {
    private let key = "pulse-pal"
    override func setUp() { super.setUp(); UserDefaults.standard.removeObject(forKey: key) }
    override func tearDown() { UserDefaults.standard.removeObject(forKey: key); super.tearDown() }

    func testAvailableIsAllPalettes() {
        let model = PaletteModel(theme: Theme())
        XCTAssertEqual(model.available, [.coastal, .mint])
    }

    func testSelectedReflectsTheme() {
        let theme = Theme(); theme.palette = .mint
        let model = PaletteModel(theme: theme)
        XCTAssertEqual(model.selected, .mint)
    }

    func testSelectUpdatesThemeAndPersists() {
        let theme = Theme()
        let model = PaletteModel(theme: theme)
        model.select(.mint)
        XCTAssertEqual(theme.palette, .mint)
        XCTAssertEqual(model.selected, .mint)
        XCTAssertEqual(UserDefaults.standard.string(forKey: key), "mint")
    }

    func testSelectIsNotAnimated() {
        // AC3: palette change must NOT be wrapped in withAnimation.
        let model = PaletteModel(theme: Theme())
        XCTAssertFalse(model.animatesSelection)
    }
}
