import Foundation
import Network
import Observation

/// Abstraction over network reachability so `BufferedSessionWriter` can auto-flush
/// the pending buffer when connectivity returns, without depending on `NWPathMonitor`
/// directly (a mock drives this in unit tests).
@MainActor
protocol ConnectivityMonitoring: AnyObject {
    var isOnline: Bool { get }
    /// Invoked on the main actor each time the path transitions offline → online.
    var onBecameReachable: (() -> Void)? { get set }
}

/// `NWPathMonitor`-backed reachability (BAK-32). Publishes `isOnline` and fires
/// `onBecameReachable` only on a genuine offline → online edge, so a flush is
/// triggered exactly once per reconnect rather than on every path update.
@MainActor
@Observable
final class ConnectivityMonitor: ConnectivityMonitoring {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "au.com.codeheroes.pulse.connectivity")
    private(set) var isOnline: Bool = true
    @ObservationIgnored var onBecameReachable: (() -> Void)?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.apply(online) }
        }
        monitor.start(queue: queue)
    }

    private func apply(_ online: Bool) {
        let wasOffline = !isOnline
        isOnline = online
        if online && wasOffline { onBecameReachable?() }
    }

    deinit { monitor.cancel() }
}
