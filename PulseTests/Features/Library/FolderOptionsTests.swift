import XCTest
@testable import Pulse

@MainActor
final class FolderOptionsTests: XCTestCase {
    func testRootFirstIndentedListWithDepths() async throws {
        let store = MockStore(seeded: false)
        let repo = InMemoryFolderRepository(store: store)
        let a = try await repo.createFolder(name: "A", color: .default, parentID: nil)
        let b = try await repo.createFolder(name: "B", color: .default, parentID: a.id)

        let opts = await FolderOptions.load(from: repo)

        XCTAssertEqual(opts.first?.id, nil)                  // Library root first
        XCTAssertEqual(opts.first?.depth, 0)
        let aOpt = try XCTUnwrap(opts.first { $0.id == a.id })
        let bOpt = try XCTUnwrap(opts.first { $0.id == b.id })
        XCTAssertEqual(aOpt.depth, 1)
        XCTAssertEqual(bOpt.depth, 2)
    }

    func testExcludingDropsTheGivenIDs() async throws {
        let store = MockStore(seeded: false)
        let repo = InMemoryFolderRepository(store: store)
        let a = try await repo.createFolder(name: "A", color: .default, parentID: nil)
        let b = try await repo.createFolder(name: "B", color: .default, parentID: a.id)

        let opts = await FolderOptions.load(from: repo, excluding: [a.id, b.id])

        XCTAssertEqual(opts.map(\.id), [nil])                // only Library root remains
    }
}
