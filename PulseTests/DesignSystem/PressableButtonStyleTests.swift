import XCTest
@testable import Pulse

final class PressableButtonStyleTests: XCTestCase {
    func testSizeHeightsMatchSpec() {
        XCTAssertEqual(PulseButtonConfig.height(for: .sm), 42)
        XCTAssertEqual(PulseButtonConfig.height(for: .md), 52)
        XCTAssertEqual(PulseButtonConfig.height(for: .lg), 60)
    }

    func testSizeFontSizesMatchSpec() {
        XCTAssertEqual(PulseButtonConfig.fontSize(for: .sm), 14)
        XCTAssertEqual(PulseButtonConfig.fontSize(for: .md), 16)
        XCTAssertEqual(PulseButtonConfig.fontSize(for: .lg), 18)
    }

    func testOnlyPrimaryHasShadowAndPressTranslate() {
        XCTAssertTrue(PulseButtonConfig.hasShadow(.primary))
        XCTAssertFalse(PulseButtonConfig.hasShadow(.secondary))
        XCTAssertFalse(PulseButtonConfig.hasShadow(.ghost))

        XCTAssertTrue(PulseButtonConfig.pressTranslates(.primary))
        XCTAssertFalse(PulseButtonConfig.pressTranslates(.secondary))
        XCTAssertFalse(PulseButtonConfig.pressTranslates(.ghost))
    }

    func testRestShadowOffsetIsFiveAndPressedIsOne() {
        XCTAssertEqual(PulseButtonConfig.shadowY(pressed: false), 5)
        XCTAssertEqual(PulseButtonConfig.shadowY(pressed: true), 1)
    }

    func testDisabledOpacityIsPoint45() {
        XCTAssertEqual(PulseButtonConfig.disabledOpacity, 0.45, accuracy: 0.001)
    }
}
