import Foundation
import Supabase

/// Classifies a save failure as "offline" (worth showing the calm pending-sync
/// state and finishing) vs a hard error (keep the blocking BAK-31 retry UI).
/// Buffering is unconditional regardless — this only drives presentation.
enum SaveClassification {
    /// True for the connectivity-related `URLError`s a flaky gym network produces.
    static func isOffline(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut,
             .cannotConnectToHost, .cannotFindHost, .dataNotAllowed,
             .internationalRoamingOff, .callIsActive:
            return true
        default:
            return false
        }
    }

    /// A user-facing message for a hard (non-offline) save failure, naming the actual
    /// cause instead of always blaming the connection. The full error is logged
    /// separately for diagnosis (BAK-65).
    static func failureMessage(for error: Error) -> String {
        if isOffline(error) {
            return "Couldn’t save — check your connection and try again."
        }
        if error is AuthError {
            return "Couldn’t save — you may be signed out. Sign in again, then tap Retry."
        }
        if let pg = error as? PostgrestError {
            return "Couldn’t save — the server rejected it: \(pg.message)"
        }
        return "Couldn’t save your workout — \(error.localizedDescription)"
    }
}

/// A `SessionWriter` decorator that makes finishing a workout offline-resilient
/// (BAK-32, approach C). It persists the session to a durable `PendingSessionStore`
/// *before* attempting the wrapped remote save, so the session is never lost:
///
/// - success → the buffered copy is removed;
/// - failure → it stays buffered and the error is rethrown, so the active flow
///   can decide between `.pendingSync` (offline) and `.failed` (hard error).
///
/// Buffered sessions are drained by `flushPending()`, which runs on app launch,
/// on foreground, and automatically when the `ConnectivityMonitor` reports the
/// network has come back.
@MainActor
final class BufferedSessionWriter: SessionWriter {
    private let inner: any SessionWriter
    private let store: PendingSessionStore
    private let monitor: any ConnectivityMonitoring
    private var isFlushing = false

    init(wrapping inner: any SessionWriter,
         store: PendingSessionStore,
         monitor: any ConnectivityMonitoring) {
        self.inner = inner
        self.store = store
        self.monitor = monitor
        monitor.onBecameReachable = { [weak self] in
            Task { await self?.flushPending() }
        }
    }

    func save(_ session: WorkoutSession) async throws {
        store.enqueue(session)            // durability first
        try await inner.save(session)     // then attempt the remote write
        store.remove(id: session.id)      // only reached on success
    }

    /// Drains the buffer best-effort and serially. Stops at the first entry that
    /// still fails (likely still offline) and leaves the remainder queued for the
    /// next launch / foreground / reconnect.
    func flushPending() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }
        for session in store.all() {
            do {
                try await inner.save(session)
                store.remove(id: session.id)
            } catch {
                break
            }
        }
    }
}
