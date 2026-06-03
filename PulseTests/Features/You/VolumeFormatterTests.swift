import XCTest
@testable import Pulse

final class VolumeFormatterTests: XCTestCase {
    func testMillionsCompactToOneDecimalM() {
        let r = VolumeFormatter.compact(2_100_000)
        XCTAssertEqual(r.value, "2.1")
        XCTAssertEqual(r.unit, "M")
    }

    func testThousandsCompactToK() {
        let r = VolumeFormatter.compact(48_500)
        XCTAssertEqual(r.value, "48.5")
        XCTAssertEqual(r.unit, "K")
    }

    func testSmallVolumeHasNoUnit() {
        let r = VolumeFormatter.compact(420)
        XCTAssertEqual(r.value, "420")
        XCTAssertEqual(r.unit, "")
    }

    func testZeroVolume() {
        let r = VolumeFormatter.compact(0)
        XCTAssertEqual(r.value, "0")
        XCTAssertEqual(r.unit, "")
    }

    func testWholeMillionDropsTrailingZero() {
        let r = VolumeFormatter.compact(3_000_000)
        XCTAssertEqual(r.value, "3")
        XCTAssertEqual(r.unit, "M")
    }
}
