import Foundation

/// Phone-side glue between the session engine and the watch. Sibling of
/// `WorkoutLiveActivityController`: it is a projection that pushes snapshots on
/// every engine transition and routes inbound commands back through the engine —
/// it never holds canonical session state. Not `@Observable`: it surfaces no
/// state to views; the flow view owns it and drives `sync()`.
@MainActor
final class WatchSyncBridge {
    private let model: ActiveWorkoutModel
    private let channel: WorkoutSyncChannel
    private let soundOnRestEnd: () -> Bool

    /// Designated init — tests inject a `MockWorkoutSyncChannel` and a sound gate.
    init(model: ActiveWorkoutModel,
         channel: WorkoutSyncChannel,
         soundOnRestEnd: @escaping () -> Bool) {
        self.model = model
        self.channel = channel
        self.soundOnRestEnd = soundOnRestEnd
        channel.onCommand { [weak self] command in
            guard let self else { return }
            WorkoutCommandApplier.apply(command, to: self.model)
            self.sync()                      // re-broadcast the new truth
        }
    }

    /// Call after every engine transition (same call sites as the Live Activity
    /// controller's `sync()`). Broadcasts a fresh snapshot to the watch.
    func sync() {
        channel.send(state: WorkoutSyncSnapshotBuilder.make(
            from: model, soundOnRestEnd: soundOnRestEnd()))
    }
}
