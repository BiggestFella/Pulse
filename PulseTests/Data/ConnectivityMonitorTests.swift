import XCTest
@testable import Pulse

@MainActor
final class ConnectivityMonitorTests: XCTestCase {
    func testMockFiresOnBecameReachableOncePerEdge() {
        let mock = MockConnectivityMonitor(isOnline: false)
        var fired = 0
        mock.onBecameReachable = { fired += 1 }
        mock.simulateOnline()
        XCTAssertTrue(mock.isOnline)
        XCTAssertEqual(fired, 1)
        mock.simulateOnline()            // already online → no double-fire
        XCTAssertEqual(fired, 1)
        mock.simulateOffline()
        mock.simulateOnline()            // offline → online again → fires
        XCTAssertEqual(fired, 2)
    }
}
