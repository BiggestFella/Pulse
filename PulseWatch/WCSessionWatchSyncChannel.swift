import Foundation
import WatchConnectivity

/// Watch-side real transport. Receives the latest snapshot via
/// `didReceiveApplicationContext` (always the freshest phone truth, so a
/// reconnect reconciles automatically) and sends commands via `sendMessage`.
/// Commands sent while unreachable are dropped — the phone is authoritative and
/// the watch reflects truth on the next snapshot.
final class WCSessionWatchSyncChannel: NSObject, WorkoutSyncChannel, WCSessionDelegate {
    private let session: WCSession
    private var stateHandler: ((WorkoutSyncSnapshot) -> Void)?

    init(session: WCSession = .default) {
        self.session = session
        super.init()
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    func send(state: WorkoutSyncSnapshot) { /* watch does not send state */ }

    func send(command: WorkoutCommand) {
        guard session.activationState == .activated, session.isReachable,
              let data = try? JSONEncoder().encode(command) else { return } // dropped if unreachable
        session.sendMessage(["command": data], replyHandler: nil, errorHandler: nil)
    }

    func onState(_ handler: @escaping (WorkoutSyncSnapshot) -> Void) {
        stateHandler = handler
        // Replay the context already received before the handler was set.
        if let data = session.receivedApplicationContext["state"] as? Data,
           let state = try? JSONDecoder().decode(WorkoutSyncSnapshot.self, from: data) {
            DispatchQueue.main.async { handler(state) }
        }
    }

    func onCommand(_ handler: @escaping (WorkoutCommand) -> Void) { /* watch receives state, not commands */ }

    // MARK: WCSessionDelegate
    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let data = context["state"] as? Data,
              let state = try? JSONDecoder().decode(WorkoutSyncSnapshot.self, from: data) else { return }
        DispatchQueue.main.async { self.stateHandler?(state) }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
}
