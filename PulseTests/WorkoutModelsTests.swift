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
}
