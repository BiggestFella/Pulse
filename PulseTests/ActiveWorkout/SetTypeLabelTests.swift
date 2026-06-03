import XCTest
@testable import Pulse

final class SetTypeLabelTests: XCTestCase {
    func testEveryTypeHasNonEmptyUppercaseLabel() {
        for type in SetType.allCases {
            let label = SetTypeLabel.text(for: type)
            XCTAssertFalse(label.isEmpty, "\(type) must have a label")
            XCTAssertEqual(label, label.uppercased(), "\(type) label must be uppercase")
        }
    }

    func testExactLabels() {
        XCTAssertEqual(SetTypeLabel.text(for: .working), "WORKING")
        XCTAssertEqual(SetTypeLabel.text(for: .warmup), "WARMUP")
        XCTAssertEqual(SetTypeLabel.text(for: .dropset), "DROP SET")
        XCTAssertEqual(SetTypeLabel.text(for: .failure), "FAILURE")
        XCTAssertEqual(SetTypeLabel.text(for: .amrap), "AMRAP")
    }

    func testOnlyWorkingIsFilledChip() {
        XCTAssertTrue(SetTypeLabel.isFilledChip(.working))
        XCTAssertFalse(SetTypeLabel.isFilledChip(.warmup))
        XCTAssertFalse(SetTypeLabel.isFilledChip(.dropset))
        XCTAssertFalse(SetTypeLabel.isFilledChip(.failure))
        XCTAssertFalse(SetTypeLabel.isFilledChip(.amrap))
    }
}
