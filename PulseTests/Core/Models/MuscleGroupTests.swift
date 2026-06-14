import XCTest
@testable import Pulse

final class MuscleGroupTests: XCTestCase {
    func testRawValuesMatchCatalogStrings() {
        XCTAssertEqual(MuscleGroup.chest.rawValue, "Chest")
        XCTAssertEqual(MuscleGroup.allCases.count, 7)
    }

    func testFromCatalogKnownAndUnknown() {
        XCTAssertEqual(MuscleGroup.from(catalog: "Back"), .back)
        XCTAssertEqual(MuscleGroup.from(catalog: "Glutes"), .other) // unknown → other
    }

    func testWorkoutDefaultsToNoTargets() {
        let w = Workout(name: "x", order: 0, exercises: [])
        XCTAssertEqual(w.targets, [])
    }
}
