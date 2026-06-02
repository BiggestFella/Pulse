import XCTest
@testable import Pulse

final class PRMathTests: XCTestCase {

    private func set(_ reps: Int, _ weight: Double, _ type: SetType) -> SessionSet {
        SessionSet(exerciseID: UUID(), order: 0, reps: reps, weight: weight, type: type)
    }

    func testEpleyOneRepMax() {
        // 100kg × (1 + 10/30) = 133.33…
        XCTAssertEqual(epley1RM(weight: 100, reps: 10), 100 * (1 + 10.0/30), accuracy: 0.0001)
    }

    func testEpleyZeroRepsIsWeight() {
        XCTAssertEqual(epley1RM(weight: 80, reps: 0), 80, accuracy: 0.0001)
    }

    func testBestEpleyExcludesWarmupAndFailure() {
        let sets = [set(12, 100, .warmup),   // excluded
                    set(10, 100, .working),  // 133.3
                    set(5,  120, .working),  // 140.0 <- best
                    set(0,  0,   .failure)]  // excluded
        let best = bestEpley(in: sets)
        XCTAssertEqual(best!, 120 * (1 + 5.0/30), accuracy: 0.0001)
    }

    func testBestEpleyNilWhenNoQualifyingSets() {
        XCTAssertNil(bestEpley(in: [set(0, 0, .failure)]))
    }

    func testWeightFormatKgWholeAndHalf() {
        XCTAssertEqual(WeightFormat.kg(60), "60 kg")
        XCTAssertEqual(WeightFormat.kg(62.5), "62.5 kg")
    }

    func testWeightFormatEyebrowUppercase() {
        XCTAssertEqual(WeightFormat.eyebrow(weight: 60, reps: 10), "60 KG · 10 REPS")
    }
}
