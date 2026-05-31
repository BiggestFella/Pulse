import XCTest
import SwiftUI
@testable import Pulse

final class ColorHexTests: XCTestCase {
    /// Resolve a SwiftUI Color to sRGB components for assertion.
    private func rgba(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    func testParsesHashRRGGBB() {
        let c = rgba(Color(hex: "#26B6F6"))
        XCTAssertEqual(c.r, 0x26 / 255, accuracy: 0.01)
        XCTAssertEqual(c.g, 0xB6 / 255, accuracy: 0.01)
        XCTAssertEqual(c.b, 0xF6 / 255, accuracy: 0.01)
        XCTAssertEqual(c.a, 1, accuracy: 0.01)
    }

    func testToleratesMissingHash() {
        let withHash = rgba(Color(hex: "#FFF4D6"))
        let without = rgba(Color(hex: "FFF4D6"))
        XCTAssertEqual(withHash.r, without.r, accuracy: 0.001)
        XCTAssertEqual(withHash.g, without.g, accuracy: 0.001)
        XCTAssertEqual(withHash.b, without.b, accuracy: 0.001)
    }

    func testMalformedReturnsClear() {
        let c = rgba(Color(hex: "zzz"))
        XCTAssertEqual(c.a, 0, accuracy: 0.01) // .clear → alpha 0
    }
}
