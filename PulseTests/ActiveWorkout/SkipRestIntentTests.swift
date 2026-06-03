import XCTest
import AppIntents
@testable import Pulse

final class SkipRestIntentTests: XCTestCase {
    @MainActor
    override func tearDown() {
        SkipRestIntent.target = nil // static target must not leak across tests
        super.tearDown()
    }

    @MainActor
    func testPerformCallsAfterRestOnTarget() async throws {
        let spy = SkipRestTargetSpy()
        SkipRestIntent.target = spy

        let intent = SkipRestIntent()
        _ = try await intent.perform()

        XCTAssertEqual(spy.afterRestCallCount, 1)
    }

    @MainActor
    func testPerformIsNoOpWhenNoTarget() async throws {
        SkipRestIntent.target = nil
        let intent = SkipRestIntent()
        _ = try await intent.perform() // must not crash
    }
}

/// Test double for the target the intent routes into.
@MainActor
final class SkipRestTargetSpy: SkipRestTarget {
    private(set) var afterRestCallCount = 0
    func afterRest() { afterRestCallCount += 1 }
}
