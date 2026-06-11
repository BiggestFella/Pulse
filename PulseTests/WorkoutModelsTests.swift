import XCTest
@testable import Pulse

final class WorkoutModelsTests: XCTestCase {
    func testSetSpecCodableRoundTrip() throws {
        let original = SetSpec(reps: 10, rir: 2, type: .working)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SetSpec.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testSetTypeHasAllFiveCases() {
        XCTAssertEqual(Set(SetType.allCases),
                       [.working, .warmup, .dropset, .failure, .amrap])
    }

    func testSessionSetCodableRoundTripWithRIR() throws {
        let original = SessionSet(exerciseID: UUID(), order: 0, reps: 8,
                                  weight: 100, type: .working, rir: 1)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SessionSet.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.rir, 1)
    }

    func testSessionSetCodableRoundTripWithoutRIR() throws {
        let original = SessionSet(exerciseID: UUID(), order: 0, reps: 8,
                                  weight: 100, type: .working)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SessionSet.self, from: data)
        XCTAssertNil(decoded.rir)
        XCTAssertEqual(decoded, original)
    }
}
