import Foundation
@testable import Pulse

/// Test double for `ConnectivityMonitoring` — lets a test drive the offline →
/// online edge deterministically (BAK-32).
@MainActor
final class MockConnectivityMonitor: ConnectivityMonitoring {
    private(set) var isOnline: Bool
    var onBecameReachable: (() -> Void)?

    init(isOnline: Bool) { self.isOnline = isOnline }

    /// Simulates the network coming back; fires `onBecameReachable` only on a
    /// genuine offline → online transition (matches the real monitor).
    func simulateOnline() {
        let wasOffline = !isOnline
        isOnline = true
        if wasOffline { onBecameReachable?() }
    }

    func simulateOffline() { isOnline = false }
}
