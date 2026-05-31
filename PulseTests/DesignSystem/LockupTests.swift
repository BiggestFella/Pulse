import XCTest
@testable import Pulse

final class LockupTests: XCTestCase {
    func testSubLabelSizeIsOneFifthOfNumeral() {
        XCTAssertEqual(Lockup.subLabelSize(numeralSize: 120), 24, accuracy: 0.001)
        XCTAssertEqual(Lockup.subLabelSize(numeralSize: 100), 20, accuracy: 0.001)
    }

    func testNumeralTextIsValueNormally() {
        XCTAssertEqual(Lockup.numeralText(value: "7", failure: false), "7")
    }

    func testNumeralTextIsInfinityOnFailure() {
        XCTAssertEqual(Lockup.numeralText(value: "7", failure: true), "∞")
    }
}
