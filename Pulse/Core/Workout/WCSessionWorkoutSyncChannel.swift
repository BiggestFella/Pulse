import Foundation
import WatchConnectivity

/// Phone-side real transport. Latest session state goes via
/// `updateApplicationContext` (coalesced, survives unreachability — the watch
/// reconciles to it on reconnect). Commands arrive via `didReceiveMessage`.
final class WCSessionWorkoutSyncChannel: NSObject, WorkoutSyncChannel, WCSessionDelegate {
    private let session: WCSession
    private var commandHandler: ((WorkoutCommand) -> Void)?

    init(session: WCSession = .default) {
        self.session = session
        super.init()
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    func send(state: WorkoutSyncSnapshot) {
        guard session.activationState == .activated,
              let data = try? JSONEncoder().encode(state) else { return }
        // updateApplicationContext throws if called before activation; guarded above.
        try? session.updateApplicationContext(["state": data])
    }

    func send(command: WorkoutCommand) { /* phone does not send commands */ }

    func onState(_ handler: @escaping (WorkoutSyncSnapshot) -> Void) { /* phone receives commands, not state */ }

    func onCommand(_ handler: @escaping (WorkoutCommand) -> Void) { commandHandler = handler }

    // MARK: WCSessionDelegate
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message["command"] as? Data,
              let command = try? JSONDecoder().decode(WorkoutCommand.self, from: data) else { return }
        DispatchQueue.main.async { self.commandHandler?(command) }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
