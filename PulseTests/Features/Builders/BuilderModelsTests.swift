import XCTest
@testable import Pulse

final class BuilderModelsTests: XCTestCase {
    private func ex(_ name: String, _ muscle: String = "Chest") -> Exercise {
        Exercise(name: name, muscleGroup: muscle, variations: [], defaultVariationID: nil)
    }

    func testRepsSummaryJoinsWorkingSetsWithDash() {
        let item = BuilderExercise(
            exercise: ex("Flat bench"),
            variationID: nil,
            supersetGroup: nil,
            sets: [
                SetSpec(reps: 8, rir: 2, type: .working),
                SetSpec(reps: 10, rir: 2, type: .working),
            ])
        XCTAssertEqual(item.repsSummary, "8-10")
    }

    func testIsMixedTrueWhenAnyNonWorkingSet() {
        let working = BuilderExercise(
            exercise: ex("Incline"), variationID: nil, supersetGroup: nil,
            sets: [SetSpec(reps: 10, rir: 2, type: .working)])
        let mixed = BuilderExercise(
            exercise: ex("Flat bench"), variationID: nil, supersetGroup: nil,
            sets: [SetSpec(reps: 8, rir: 2, type: .warmup),
                   SetSpec(reps: 8, rir: 2, type: .working)])
        XCTAssertFalse(working.isMixed)
        XCTAssertTrue(mixed.isMixed)
    }

    func testSubLineAppendsMixedWhenAnyNonWorking() {
        let plain = BuilderExercise(
            exercise: ex("Incline"), variationID: nil, supersetGroup: nil,
            sets: [SetSpec(reps: 10, rir: 2, type: .working),
                   SetSpec(reps: 10, rir: 2, type: .working)])
        XCTAssertEqual(plain.subLine, "2 sets · 10-10")
        let mixed = BuilderExercise(
            exercise: ex("Flat bench"), variationID: nil, supersetGroup: nil,
            sets: [SetSpec(reps: 12, rir: 4, type: .warmup),
                   SetSpec(reps: 8, rir: 2, type: .working)])
        XCTAssertEqual(mixed.subLine, "2 sets · 8 · MIXED")
    }

    func testFolderColorHasSixCasesBlueDefault() {
        XCTAssertEqual(FolderColor.allCases.count, 6)
        XCTAssertEqual(FolderColor.default, .blue)
        XCTAssertEqual(FolderColor.blue.hex, "#26B6F6")
    }

    func testWorkoutTagHasThreeCasesPushDefault() {
        XCTAssertEqual(WorkoutTag.allCases, [.push, .pull, .legs])
        XCTAssertEqual(WorkoutTag.push.label, "PUSH")
    }

    func testSaveStateEquatable() {
        XCTAssertEqual(SaveState.idle, .idle)
        XCTAssertNotEqual(SaveState.saved, SaveState.error("x"))
        XCTAssertEqual(SaveState.error("boom"), SaveState.error("boom"))
    }
}
