import XCTest
@testable import Pulse

/// Covers the bare-numeral / bodyweight / volume helpers added to `WeightFormat`
/// for the Exercise Detail screen (the existing `kg`/`eyebrow` helpers are tested
/// elsewhere).
final class WeightFormatExerciseDetailTests: XCTestCase {
    func testWholeKgNumeralHasNoDecimals() {
        XCTAssertEqual(WeightFormat.kgNumeral(150), "150")
    }

    func testHalfKgNumeralKeepsDecimal() {
        XCTAssertEqual(WeightFormat.kgNumeral(67.5), "67.5")
    }

    func testZeroOrLessRendersBodyweight() {
        XCTAssertEqual(WeightFormat.weightOrBodyweight(0), "bodyweight")
        XCTAssertEqual(WeightFormat.weightOrBodyweight(-5), "bodyweight")
    }

    func testPositiveRendersKgWithUnit() {
        XCTAssertEqual(WeightFormat.weightOrBodyweight(100), "100 kg")
    }

    func testVolumeThousandsAbbreviation() {
        XCTAssertEqual(WeightFormat.volume(3600), "3.6k")
    }

    func testVolumeUnderThousandShownAsRounded() {
        XCTAssertEqual(WeightFormat.volume(840), "840")
    }

    func testVolumeZeroIsDash() {
        XCTAssertEqual(WeightFormat.volume(0), "—")
    }
}
