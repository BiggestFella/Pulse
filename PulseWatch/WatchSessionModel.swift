import Foundation
import Observation

/// Watch-side `@Observable` model. Holds the latest phone snapshot, exposes
/// derived display state, and sends commands. It NEVER mutates session truth —
/// it asks the phone, and reflects whatever snapshot comes back. Haptic
/// scheduling from `restEndsAt` is wired in Task 6.
@MainActor
@Observable
final class WatchSessionModel {
    private(set) var snapshot: WorkoutSyncSnapshot = .idle
    private let channel: WorkoutSyncChannel
    private let haptics: WatchHapticsPlaying

    init(channel: WorkoutSyncChannel, haptics: WatchHapticsPlaying = WatchHaptics()) {
        self.channel = channel
        self.haptics = haptics
        channel.onState { [weak self] state in
            Task { @MainActor in self?.receive(state) }
        }
    }

    /// Apply an inbound snapshot. Task 6 extends this to (re)schedule rest
    /// haptics; here it just stores the latest truth (last-write-wins).
    func receive(_ state: WorkoutSyncSnapshot) {
        snapshot = state
    }

    // MARK: - commands (fire-and-forget; phone re-broadcasts the result)
    func logSet()           { channel.send(command: .logSet) }
    func skipSet()          { channel.send(command: .skipSet) }
    func skipRest()         { channel.send(command: .skipRest) }
    func adjustRest(_ d: TimeInterval) { channel.send(command: .adjustRest(delta: d)) }

    // MARK: - derived display
    var weightLabel: String {
        guard let w = snapshot.targetWeight, w > 0 else { return "BW" }
        return "\(Int(w)) kg"
    }
    var repsLabel: String {
        snapshot.isFailure ? "∞" : "\(snapshot.targetReps ?? 0)"
    }
}
