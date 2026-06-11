import SwiftUI

@main
struct PulseWatchApp: App {
    // The real WCSession channel is injected in Task 7; until then this idle
    // channel keeps the target buildable and shows the idle screen.
    @State private var model = WatchSessionModel(channel: IdleSyncChannel())

    var body: some Scene {
        WindowGroup { WatchRootView(model: model) }
    }
}

/// Placeholder channel — replaced by WCSessionWatchSyncChannel in Task 7.
private final class IdleSyncChannel: WorkoutSyncChannel {
    func send(state: WorkoutSyncSnapshot) {}
    func send(command: WorkoutCommand) {}
    func onState(_ handler: @escaping (WorkoutSyncSnapshot) -> Void) {}
    func onCommand(_ handler: @escaping (WorkoutCommand) -> Void) {}
}
