import XCTest
@testable import Pulse

final class FolderTests: XCTestCase {
    func testFolderColorRawValuesAreTheStoredTokens() {
        XCTAssertEqual(FolderColor.blue.rawValue, "blue")
        XCTAssertEqual(FolderColor(rawValue: "purple"), .purple)
        XCTAssertEqual(Set(FolderColor.allCases.map(\.rawValue)),
                       ["blue", "orange", "teal", "yellow", "pink", "purple"])
    }

    func testFolderContentsEmptyHelper() {
        let empty = FolderContents(folders: [], workouts: [], programs: [])
        XCTAssertTrue(empty.isEmpty)
        let nonEmpty = FolderContents(
            folders: [Folder(id: UUID(), name: "A", color: .blue, parentID: nil)],
            workouts: [], programs: [])
        XCTAssertFalse(nonEmpty.isEmpty)
    }
}
