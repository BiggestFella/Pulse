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

    private var warningTask: Task<Void, Never>?
    private var endTask: Task<Void, Never>?

    init(channel: WorkoutSyncChannel, haptics: WatchHapticsPlaying = WatchHaptics()) {
        self.channel = channel
        self.haptics = haptics
        channel.onState { [weak self] state in
            Task { @MainActor in self?.receive(state) }
        }
    }

    /// Apply an inbound snapshot (last-write-wins) and (re)schedule rest haptics
    /// from the absolute `restEndsAt`. Reconciles to the phone on every push, so
    /// an out-of-range reconnect just re-schedules from fresh truth.
    func receive(_ state: WorkoutSyncSnapshot) {
        snapshot = state
        scheduleRestHaptics(for: state)
    }

    private func scheduleRestHaptics(for state: WorkoutSyncSnapshot) {
        warningTask?.cancel(); endTask?.cancel()
        warningTask = nil; endTask = nil

        guard state.phase == .rest, state.soundOnRestEnd,
              let end = state.restEndsAt else { return }

        let now = Date()
        let toEnd = end.timeIntervalSince(now)
        let toWarning = toEnd - 10

        if toWarning > 0 {
            warningTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(toWarning * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.haptics.playWarning() }
            }
        }
        if toEnd > 0 {
            endTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(toEnd * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.haptics.playRestEnd() }
            }
        }
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
