import XCTest
import SwiftUI
@testable import Pulse

final class PaletteTests: XCTestCase {
    func testCoastalIsDefault() {
        XCTAssertEqual(Palette.default, .coastal)
    }

    func testEveryPaletteDefinesAllTokens() {
        for palette in Palette.allCases {
            let t = palette.tokens
            // hex strings are 7 chars ("#RRGGBB") and parse to a Color
            XCTAssertEqual(t.bg.count, 7)
            XCTAssertEqual(t.accent.count, 7)
            XCTAssertEqual(t.accent2.count, 7)
            XCTAssertEqual(t.onAccent.count, 7)
        }
    }

    func testCoastalAccentHex() {
        XCTAssertEqual(Palette.coastal.tokens.accent, "#26B6F6")
    }
}
