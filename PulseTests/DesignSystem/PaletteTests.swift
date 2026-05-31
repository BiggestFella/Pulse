import XCTest
@testable import Pulse

final class PaletteTests: XCTestCase {
    func testAllCasesIsCoastalThenMint() {
        XCTAssertEqual(Palette.allCases, [.coastal, .mint])
    }

    func testDefaultIsCoastal() {
        XCTAssertEqual(Palette.default, .coastal)
    }

    func testRawValueRoundTrips() {
        XCTAssertEqual(Palette(rawValue: "coastal"), .coastal)
        XCTAssertEqual(Palette(rawValue: "mint"), .mint)
        XCTAssertNil(Palette(rawValue: "teal"))
    }

    func testCoastalTokenHexMatchesHandoff() {
        let t = Palette.coastal.tokens
        XCTAssertEqual(t.bg, "#06121F")
        XCTAssertEqual(t.surface, "#0E1F33")
        XCTAssertEqual(t.surface2, "#16314D")
        XCTAssertEqual(t.ink, "#FFF4D6")
        XCTAssertEqual(t.accent, "#26B6F6")
        XCTAssertEqual(t.accentDeep, "#0E5BA8")
        XCTAssertEqual(t.accent2, "#FF6A1F")
        XCTAssertEqual(t.onAccent, "#06121F")
    }

    func testMintTokenHexMatchesHandoff() {
        let t = Palette.mint.tokens
        XCTAssertEqual(t.bg, "#0F1814")
        XCTAssertEqual(t.surface, "#1A2620")
        XCTAssertEqual(t.surface2, "#26332B")
        XCTAssertEqual(t.ink, "#E1F4E8")
        XCTAssertEqual(t.accent, "#00D9B8")
        XCTAssertEqual(t.accentDeep, "#007A6C")
        XCTAssertEqual(t.accent2, "#FFCC33")
        XCTAssertEqual(t.onAccent, "#0F1814")
    }

    /// Soft-opacity differs per palette: Coastal .62, Mint .64 (handoff).
    func testInkSoftOpacityPerPalette() {
        XCTAssertEqual(Palette.coastal.inkSoftOpacity, 0.62, accuracy: 0.001)
        XCTAssertEqual(Palette.mint.inkSoftOpacity, 0.64, accuracy: 0.001)
    }
}
