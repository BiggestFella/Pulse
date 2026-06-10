# Offline-resilient active session — implementation plan (BAK-32)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A finished workout is never lost to connectivity — buffer it locally on finish, flush to Supabase with auto-retry on reconnect, and show a persistent "pending sync" indicator. Builds on BAK-31's in-memory save-error/retry groundwork (already on this branch).

**Architecture:** A `BufferedSessionWriter` decorator wraps whichever concrete `SessionWriter` is injected (mock or `SupabaseSessionWriter`). It persists the session to a file-based `PendingSessionStore` *before* attempting the remote save, removes it on success, and keeps it (rethrowing) on failure. A `ConnectivityMonitor` (`NWPathMonitor`) drives `flushPending()` on reconnect; the app also flushes on launch + foreground. `ActiveWorkoutModel` gains a `.pendingSync` `SaveState` so an offline finish is non-blocking; the Today tab shows a global pending-sync pill driven by the store. No changes to `SupabaseSessionWriter` or the (already `Codable`) domain models.

**Tech Stack:** Swift / SwiftUI, Network (`NWPathMonitor`), Foundation (`FileManager`, `JSONEncoder`), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-06-10-offline-resilient-session-design.md`.

---

## File Structure

- Create `Pulse/Core/Data/Offline/PendingSessionStore.swift` — durable file-backed buffer.
- Create `Pulse/Core/Data/Offline/ConnectivityMonitor.swift` — `NWPathMonitor` wrapper + protocol + mock.
- Create `Pulse/Core/Data/Offline/BufferedSessionWriter.swift` — `SessionWriter` decorator + `flushPending`.
- Modify `Pulse/Core/Data/ActiveWorkoutRepositories.swift` — extend `MockSessionWriter` test hooks if needed.
- Modify `Pulse/App/AppEnvironment.swift` — own the store + monitor, wrap the writer, expose pending count.
- Modify `Pulse/App/PulseApp.swift` / `AppShell.swift` — flush on launch + foreground (`scenePhase`).
- Modify `Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift` — `.pendingSync` case + offline handling.
- Modify `Pulse/Features/ActiveWorkout/SummaryView.swift` — non-blocking `.pendingSync` UI.
- Create/modify the Today tab indicator: `Pulse/Features/Today/` (a `PendingSyncBanner` view) + its model wiring.
- Tests: `PulseTests/Data/PendingSessionStoreTests.swift`, `BufferedSessionWriterTests.swift`, `ConnectivityMonitorTests.swift`; extend `PulseTests/ActiveWorkout/ActiveWorkoutModelTests.swift`; extend the save-failure XCUITest under `PulseUITests/`.

> **Testing gate after each code task:** `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests test` (full unit suite stays green on mocks). Build UI with the same `build` invocation.

---

## Phase 1 — Durable buffer

### Task 1: PendingSessionStore (file-backed, Codable)

**Files:** Create `Pulse/Core/Data/Offline/PendingSessionStore.swift`, `PulseTests/Data/PendingSessionStoreTests.swift`

- [ ] **Step 1: Write the failing test** — enqueue/reload/remove round-trips against a temp directory; a fresh instance pointed at the same dir reloads what was persisted (proves durability across "relaunch").

```swift
import XCTest
@testable import Pulse

@MainActor
final class PendingSessionStoreTests: XCTestCase {
    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private func session() -> WorkoutSession {
        WorkoutSession(workoutID: UUID(), startedAt: .now, endedAt: .now,
                       sets: [SessionSet(exerciseID: UUID(), order: 0, reps: 5, weight: 100, type: .working)])
    }

    func testEnqueuePersistsAndReloads() throws {
        let dir = tempDir()
        let store = PendingSessionStore(directory: dir)
        let s = session()
        store.enqueue(s)
        XCTAssertEqual(store.pendingCount, 1)
        // New instance == app relaunch: reads the same file.
        let reloaded = PendingSessionStore(directory: dir)
        XCTAssertEqual(reloaded.pendingCount, 1)
        XCTAssertEqual(reloaded.all().first?.id, s.id)
    }

    func testRemoveClears() throws {
        let dir = tempDir()
        let store = PendingSessionStore(directory: dir)
        let s = session(); store.enqueue(s)
        store.remove(id: s.id)
        XCTAssertTrue(store.isEmpty)
        XCTAssertTrue(PendingSessionStore(directory: dir).isEmpty)
    }

    func testEnqueueIsIdempotentOnID() throws {
        let store = PendingSessionStore(directory: tempDir())
        let s = session(); store.enqueue(s); store.enqueue(s)
        XCTAssertEqual(store.pendingCount, 1)   // same id replaces, no dupes
    }
}
```

- [ ] **Step 2: Run (fails — no PendingSessionStore).** Expected: FAIL.

- [ ] **Step 3: Implement.** `@MainActor @Observable` so views observe `pendingCount`. File-backed JSON; default directory is Application Support; injectable for tests. Loads on init; writes on every mutation (best-effort, logs on failure — a write failure must never crash the workout flow).

```swift
import Foundation

@MainActor
@Observable
final class PendingSessionStore {
    private let fileURL: URL
    private(set) var pending: [WorkoutSession] = []

    var isEmpty: Bool { pending.isEmpty }
    var pendingCount: Int { pending.count }

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("pending-sessions.json")
        load()
    }

    func all() -> [WorkoutSession] { pending }

    func enqueue(_ session: WorkoutSession) {
        pending.removeAll { $0.id == session.id }   // replace-by-id, no dupes
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
```

- [ ] **Step 4: Run (passes).** Expected: PASS.
- [ ] **Step 5: Regenerate + build** `xcodegen generate` (new file picked up) then build. Expected: success.
- [ ] **Step 6: Commit** `git add -A && git commit -m "feat(data): durable PendingSessionStore [BAK-32]"`

### Task 2: ConnectivityMonitor (NWPathMonitor wrapper + mock)

**Files:** Create `Pulse/Core/Data/Offline/ConnectivityMonitor.swift`, `PulseTests/Data/ConnectivityMonitorTests.swift`

- [ ] **Step 1: Define a protocol** so the buffered writer depends on an abstraction, not `NWPathMonitor` directly:

```swift
import Foundation

@MainActor
protocol ConnectivityMonitoring: AnyObject {
    var isOnline: Bool { get }
    /// Invoked on the main actor each time the path transitions offline → online.
    var onBecameReachable: (() -> Void)? { get set }
}
```

- [ ] **Step 2: Write the failing test** against a mock that simulates an offline→online transition and asserts the callback fires (this is what the writer subscribes to):

```swift
import XCTest
@testable import Pulse

@MainActor
final class ConnectivityMonitorTests: XCTestCase {
    func testMockFiresOnBecameReachable() {
        let mock = MockConnectivityMonitor(isOnline: false)
        var fired = 0
        mock.onBecameReachable = { fired += 1 }
        mock.simulateOnline()
        XCTAssertTrue(mock.isOnline)
        XCTAssertEqual(fired, 1)
        mock.simulateOnline()           // already online → no double-fire
        XCTAssertEqual(fired, 1)
    }
}
```

- [ ] **Step 3: Implement** the real monitor (`NWPathMonitor` on a background queue, hopping to `@MainActor` to publish + fire the callback only on a genuine offline→online edge) and the `MockConnectivityMonitor`. Put the mock in the test target (or under a `#if DEBUG`/test-support file) so production stays clean.

```swift
import Foundation
import Network

@MainActor
@Observable
final class ConnectivityMonitor: ConnectivityMonitoring {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "pulse.connectivity")
    private(set) var isOnline: Bool = true
    var onBecameReachable: (() -> Void)?

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
```

- [ ] **Step 4: Run (passes).** Expected: PASS.
- [ ] **Step 5: Build.** Expected: success.
- [ ] **Step 6: Commit** `git add -A && git commit -m "feat(data): ConnectivityMonitor (NWPathMonitor) [BAK-32]"`

---

## Phase 2 — Buffered writer

### Task 3: BufferedSessionWriter decorator + flushPending

**Files:** Create `Pulse/Core/Data/Offline/BufferedSessionWriter.swift`, `PulseTests/Data/BufferedSessionWriterTests.swift`

- [ ] **Step 1: Write the failing tests** covering the four behaviours from the spec.

```swift
import XCTest
@testable import Pulse

@MainActor
final class BufferedSessionWriterTests: XCTestCase {
    private func session() -> WorkoutSession {
        WorkoutSession(workoutID: UUID(), startedAt: .now, endedAt: .now, sets: [])
    }
    private func makeStore() -> PendingSessionStore {
        PendingSessionStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString))
    }

    func testSuccessDoesNotLeaveAnythingBuffered() async throws {
        let inner = MockSessionWriter()
        let store = makeStore()
        let w = BufferedSessionWriter(wrapping: inner, store: store, monitor: MockConnectivityMonitor(isOnline: true))
        try await w.save(session())
        XCTAssertEqual(inner.saved.count, 1)
        XCTAssertTrue(store.isEmpty)            // persisted then removed on success
    }

    func testFailureKeepsBufferedAndRethrows() async {
        let inner = MockSessionWriter(); inner.failAlways = NSError(domain: "x", code: 1)
        let store = makeStore()
        let w = BufferedSessionWriter(wrapping: inner, store: store, monitor: MockConnectivityMonitor(isOnline: false))
        do { try await w.save(session()); XCTFail("expected throw") }
        catch { /* expected */ }
        XCTAssertEqual(store.pendingCount, 1)   // not lost
    }

    func testFlushDrainsWhenWriterRecovers() async throws {
        let inner = MockSessionWriter(); inner.failAlways = NSError(domain: "x", code: 1)
        let store = makeStore()
        let w = BufferedSessionWriter(wrapping: inner, store: store, monitor: MockConnectivityMonitor(isOnline: false))
        _ = try? await w.save(session())
        XCTAssertEqual(store.pendingCount, 1)
        inner.failAlways = nil                  // connectivity restored
        await w.flushPending()
        XCTAssertTrue(store.isEmpty)
        XCTAssertEqual(inner.saved.count, 1)
    }

    func testBecameReachableTriggersFlush() async throws {
        let inner = MockSessionWriter(); inner.failAlways = NSError(domain: "x", code: 1)
        let store = makeStore()
        let monitor = MockConnectivityMonitor(isOnline: false)
        let w = BufferedSessionWriter(wrapping: inner, store: store, monitor: monitor)
        _ = try? await w.save(session())
        inner.failAlways = nil
        monitor.simulateOnline()                // fires onBecameReachable → flush
        // allow the flush Task to run
        await Task.yield(); try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(store.isEmpty)
    }
}
```

- [ ] **Step 2: Run (fails).** Expected: FAIL (no `BufferedSessionWriter`).

- [ ] **Step 3: Implement.** Persist-first, try inner, remove-on-success / keep-and-rethrow on failure. Subscribe to `monitor.onBecameReachable` to auto-flush. `flushPending` is best-effort and serial; a still-failing entry stays buffered for the next trigger.

```swift
import Foundation

@MainActor
final class BufferedSessionWriter: SessionWriter {
    private let inner: any SessionWriter
    private let store: PendingSessionStore
    private let monitor: any ConnectivityMonitoring
    private var isFlushing = false

    init(wrapping inner: any SessionWriter, store: PendingSessionStore, monitor: any ConnectivityMonitoring) {
        self.inner = inner; self.store = store; self.monitor = monitor
        monitor.onBecameReachable = { [weak self] in Task { await self?.flushPending() } }
    }

    /// Buffers first (durability), then attempts the remote save. On success the
    /// buffered copy is removed; on failure it's kept and the error is rethrown so
    /// the active flow can decide between `.pendingSync` (offline) and `.failed`.
    func save(_ session: WorkoutSession) async throws {
        store.enqueue(session)
        try await inner.save(session)
        store.remove(id: session.id)
    }

    /// Drains the buffer best-effort; stops touching an entry the moment it fails
    /// (it stays queued for the next reconnect/foreground/launch).
    func flushPending() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }
        for session in store.all() {
            do { try await inner.save(session); store.remove(id: session.id) }
            catch { break }   // still offline / failing — leave the rest queued
        }
    }
}
```

- [ ] **Step 4: Run (passes).** Expected: PASS.
- [ ] **Step 5: Build.** Expected: success.
- [ ] **Step 6: Commit** `git add -A && git commit -m "feat(data): BufferedSessionWriter decorator + flushPending [BAK-32]"`

### Task 4: Classify offline vs hard failure

**Files:** Modify `Pulse/Core/Data/Offline/BufferedSessionWriter.swift` (add a typed error or flag)

- [ ] **Step 1:** Decide the signal the active model reads. Simplest: `BufferedSessionWriter.save` rethrows the inner error, and `ActiveWorkoutModel` classifies it via a small helper `SaveOutcome.isOffline(error)` checking `URLError` / `.notConnectedToInternet` / `.networkConnectionLost` / `.timedOut`. The session is *already buffered* regardless, so "offline" just changes the message + lets the flow tear down. Document that non-`URLError` failures keep the blocking `.failed` UI **but remain buffered** (so a later flush still recovers them — buffering is unconditional; classification is presentation-only).
- [ ] **Step 2:** Add `enum SaveClassification { static func isOffline(_ error: Error) -> Bool }` (small, unit-tested) — covers the `URLError` codes above.
- [ ] **Step 3: Test** the classifier with representative `URLError`s and a generic `NSError`.
- [ ] **Step 4: Commit** `git add -A && git commit -m "feat(data): classify offline vs hard save failure [BAK-32]"`

---

## Phase 3 — Active flow integration

### Task 5: SaveState.pendingSync in ActiveWorkoutModel

**Files:** Modify `Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift`, extend `PulseTests/ActiveWorkout/ActiveWorkoutModelTests.swift`

- [ ] **Step 1: Update the failing tests first.** Add the new behaviours and update existing BAK-31 expectations:

```swift
func testOfflineFinishBuffersAndTearsDownAsPendingSync() async {
    let writer = MockSessionWriter()
    writer.failAlways = URLError(.notConnectedToInternet)
    let m = started(writer: writer); m.beginSets()
    m.logSet(reps: 12, weight: 100)
    await m.finishAndSave()
    XCTAssertEqual(m.saveState, .pendingSync)   // non-blocking
    XCTAssertFalse(m.isActive)                  // takeover torn down — workout is safe
}

func testHardFailureStillBlocksWithRetry() async {
    let writer = MockSessionWriter(); writer.failAlways = NSError(domain: "server", code: 500)
    let m = started(writer: writer); m.beginSets()
    m.logSet(reps: 12, weight: 100)
    await m.finishAndSave()
    if case .failed = m.saveState {} else { XCTFail("expected .failed") }
    XCTAssertTrue(m.isActive)                   // unchanged BAK-31 behaviour
}
```

> Note: with the real `BufferedSessionWriter`, an offline `save` still *throws* (the inner writer threw) but the session is buffered. For unit tests of the model in isolation we can either (a) inject a `BufferedSessionWriter` wrapping the failing mock, or (b) keep injecting `MockSessionWriter` and classify the thrown error directly. Prefer (a) in at least one test so the buffered path is exercised end-to-end at the model layer.

- [ ] **Step 2: Run (fails).** Expected: FAIL (no `.pendingSync`).

- [ ] **Step 3: Implement.** Extend `SaveState`:

```swift
enum SaveState: Equatable { case idle, saving, saved, pendingSync, failed(String) }
```

Update `attemptSave()` so a thrown error is classified: offline → `.pendingSync` + `endWorkout()` (the session is safely buffered by the writer); other → existing `.failed(...)` blocking state. Keep `pendingSession` semantics for the `.failed` retry path; on `.pendingSync` we no longer need the in-memory copy (the store owns it) — clear it.

```swift
private func attemptSave() async {
    guard let session = pendingSession else { return }
    saveState = .saving
    do {
        try await sessionWriter.save(session)
        saveState = .saved
        pendingSession = nil
        endWorkout()
    } catch {
        if SaveClassification.isOffline(error) {
            // Buffered on-device by BufferedSessionWriter; safe to finish.
            saveState = .pendingSync
            pendingSession = nil
            endWorkout()
        } else {
            print("[Pulse] session save failed: \(error)")
            saveState = .failed("Couldn't save your workout. Check your connection and try again.")
        }
    }
}
```

- [ ] **Step 4: Run (passes).** Expected: PASS (updated suite green).
- [ ] **Step 5: Commit** `git add -A && git commit -m "feat(active): pendingSync save state for offline finish [BAK-32]"`

### Task 6: SummaryView non-blocking pendingSync UI

**Files:** Modify `Pulse/Features/ActiveWorkout/SummaryView.swift`

- [ ] **Step 1: Implement.** Add a `.pendingSync` branch to the banner slot — info styling (not error): an icon (`arrow.triangle.2.circlepath` / `icloud.and.arrow.up`) + "Saved on this device — will sync when you're back online", using `Theme` tokens (`surface2`, `ink`, accent per design-system rules; small label = Geist Mono eyebrow). The Done button completes/dismisses normally for `.pendingSync` (no "Retry save"). Keep `.failed` exactly as BAK-31. Add `accessibilityIdentifier("summary.pendingSync")` for the UI test.
- [ ] **Step 2: Build.** Expected: success.
- [ ] **Step 3: Commit** `git add -A && git commit -m "feat(active): non-blocking pending-sync summary state [BAK-32]"`

---

## Phase 4 — Wiring + global indicator

### Task 7: RepositoryContainer wiring + flush triggers

**Files:** Modify `Pulse/App/AppEnvironment.swift`, `Pulse/App/PulseApp.swift` / `AppShell.swift`

- [ ] **Step 1: Wire the container.** In `RepositoryContainer`, own a `PendingSessionStore` and a `ConnectivityMonitor` (real path) / no-op monitor under `-uiMock`. Wrap the chosen concrete writer: `sessionWriter = BufferedSessionWriter(wrapping: base, store: store, monitor: monitor)`. Expose the `store` (for the indicator) and a `flushPending()` passthrough. Under `-uiMock`, point the store at a temp/in-memory dir cleared at launch so UI tests are deterministic; honor a `-uiTestSaveFail` / new `-uiTestOffline` arg by setting the mock writer's `failAlways = URLError(.notConnectedToInternet)`.
- [ ] **Step 2: Flush triggers.** In the app shell, call `container.flushPending()` in a launch `.task` and on `scenePhase` → `.active`. The `ConnectivityMonitor` already auto-flushes on reconnect via the writer's subscription.
- [ ] **Step 3: Build + run.** Confirm app launches; on a clean store nothing flushes. Expected: success.
- [ ] **Step 4: Commit** `git add -A && git commit -m "feat(app): wire buffered writer + flush on launch/foreground [BAK-32]"`

### Task 8: Global pending-sync indicator on Today

**Files:** Create `Pulse/Features/Today/PendingSyncBanner.swift`; modify the Today view + model to read `RepositoryContainer`'s store.

- [ ] **Step 1: Implement** a small banner/pill shown only when `store.pendingCount > 0`: "1 workout pending sync" (pluralized), with a tap that calls `flushPending()` (and a subtle spinner while flushing). `Theme` tokens only; on an `accent`-filled pill, highlight text uses `onAccent` (never `accent2`) per the design-system rule. `accessibilityIdentifier("today.pendingSync")`.
- [ ] **Step 2:** Surface it at the top of the Today tab. Because `PendingSessionStore` is `@Observable`, the count updates reactively as sessions buffer/flush.
- [ ] **Step 3: Build.** Expected: success.
- [ ] **Step 4: Commit** `git add -A && git commit -m "feat(today): global pending-sync indicator [BAK-32]"`

---

## Phase 5 — End-to-end tests + verification

### Task 9: UI test — offline finish → indicator → recovery

**Files:** Modify the save-failure XCUITest under `PulseUITests/` (the BAK-31 `ActiveWorkoutFlow`/summary test)

- [ ] **Step 1: Implement** a test launched with `-uiMock -uiTestOffline`: log a workout, tap Done → assert `summary.pendingSync` appears and the app returns to the tab bar (non-blocking), and `today.pendingSync` is visible. Then drive the mock back online (a launch arg or a debug affordance that clears `failAlways`) and assert `today.pendingSync` disappears after a flush. If toggling connectivity mid-test is impractical via launch args, split into two assertions: (a) offline → buffered + indicator visible; (b) a separate test where `flushPending` on foreground drains a pre-seeded buffer.
- [ ] **Step 2: Run** the UI test on iPhone 17. Expected: PASS.
- [ ] **Step 3: Commit** `git add -A && git commit -m "test(active): offline finish buffers + recovers on reconnect [BAK-32]"`

### Task 10: Full suite + manual verification

- [ ] **Step 1: Run the full unit suite** `xcodebuild ... -only-testing:PulseTests test` (iPhone 17). Expected: `** TEST SUCCEEDED **` (existing + new tests green).
- [ ] **Step 2: Manual (real device/sim against the dev Supabase project):** airplane-mode → finish a workout → confirm summary shows the on-device note, app tears down, Today shows the pending pill, and the buffer file exists. Kill + relaunch → pill still there. Re-enable network → session auto-syncs, pill clears, row lands in `sessions`/`session_sets`. Screenshot before/after.
- [ ] **Step 3: Update the PR description** with results + screenshots; mark the checklist done.

---

## Self-review notes

- **Spec coverage:** durable buffer (T1), connectivity monitor (T2), buffered writer + flush (T3–4), `.pendingSync` non-blocking finish (T5–6), wiring + launch/foreground/reconnect flush (T7), global indicator (T8), UI + manual verification (T9–10). Crash-safe per-set buffering, general read-cache/write-queue, and BGTask wake-ups explicitly deferred per spec.
- **No risky changes:** `SupabaseSessionWriter` and domain models untouched; buffering is additive via a decorator on the existing `SessionWriter` seam.
- **Buffering is unconditional; classification is presentation-only** — even a "hard" failure stays buffered, so a later flush can still recover it; the classification only decides whether the UI blocks (`.failed`) or finishes calmly (`.pendingSync`).
- **Open plan-time confirmations for the implementer:** exact `SummaryView` banner-slot structure to reuse (BAK-31 added it); the Today view/model entry point for injecting the banner; whether UI tests can toggle connectivity via launch args or need the two-test split in T9; and that Application Support is the right buffer location (vs. Caches, which the OS may purge).
```
