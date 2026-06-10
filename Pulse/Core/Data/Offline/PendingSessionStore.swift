import Foundation
import Observation

/// Durable, file-backed buffer for finished workout sessions that haven't yet
/// reached Supabase (BAK-32, approach C). The active flow saves through a
/// `BufferedSessionWriter`, which enqueues here *before* attempting the remote
/// write so a dropped connection at finish never loses the session — the buffer
/// survives app relaunch and is flushed when connectivity returns.
///
/// `@Observable` so the global "pending sync" indicator (Today tab) tracks the
/// count reactively. Writes are best-effort: a persistence failure logs and is
/// swallowed — it must never crash the workout flow.
@MainActor
@Observable
final class PendingSessionStore {
    private let fileURL: URL
    private(set) var pending: [WorkoutSession] = []

    var isEmpty: Bool { pending.isEmpty }
    var pendingCount: Int { pending.count }

    /// `directory` is injectable so tests can point at a temp dir; production
    /// uses Application Support (persists across launches; not purged like Caches).
    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("pending-sessions.json")
        load()
    }

    func all() -> [WorkoutSession] { pending }

    /// Adds (or replaces, by id) a session and persists. Replace-by-id keeps a
    /// re-attempted save from duplicating its buffered copy.
    func enqueue(_ session: WorkoutSession) {
        pending.removeAll { $0.id == session.id }
        pending.append(session)
        persist()
    }

    func remove(id: WorkoutSession.ID) {
        pending.removeAll { $0.id == id }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        pending = (try? JSONDecoder().decode([WorkoutSession].self, from: data)) ?? []
    }

    private func persist() {
        do { try JSONEncoder().encode(pending).write(to: fileURL, options: .atomic) }
        catch { print("[Pulse] PendingSessionStore persist failed: \(error)") }
    }
}
