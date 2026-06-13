import XCTest
@testable import Pulse

@MainActor
final class ExercisePickerLogicTests: XCTestCase {
    private var catalog: [BuilderCatalogGroup] { WorkoutBuilderModel.group(SampleData.exercises) }

    func testModeIsSectionedWithActiveMusclesAndNoSearch() {
        XCTAssertEqual(ExercisePickerLogic.mode(activeMuscles: ["Legs"], search: ""), .sectioned)
    }
    func testModeIsAlphabeticalWhenAllOrSearching() {
        XCTAssertEqual(ExercisePickerLogic.mode(activeMuscles: [], search: ""), .alphabetical)
        XCTAssertEqual(ExercisePickerLogic.mode(activeMuscles: ["Legs"], search: "row"), .alphabetical)
    }
    func testSectionedKeepsOnlyActiveMuscles() {
        let groups = ExercisePickerLogic.sectioned(catalog, activeMuscles: ["Chest"])
        XCTAssertEqual(groups.map(\.muscle), ["Chest"])
    }
    func testAlphabeticalSortsByNameAndFiltersBySearch() {
        let list = ExercisePickerLogic.alphabetical(catalog, activeMuscles: [], search: "row")
        XCTAssertFalse(list.isEmpty)
        XCTAssertEqual(list.map(\.name), list.map(\.name).sorted())
        XCTAssertTrue(list.allSatisfy { $0.name.localizedCaseInsensitiveContains("row") })
    }
    func testLetterIndexIsDistinctUppercaseFirstLetters() {
        let list = ExercisePickerLogic.alphabetical(catalog, activeMuscles: [], search: "")
        let idx = ExercisePickerLogic.letterIndex(list)
        XCTAssertEqual(idx, idx.sorted())
        XCTAssertEqual(Set(idx).count, idx.count)
        XCTAssertTrue(idx.allSatisfy { $0.count == 1 && $0 == $0.uppercased() })
    }
}
