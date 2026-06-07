# Offline-resilient Active Session — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Never lose a workout to connectivity — buffer the active session to disk as it's logged, queue it on finish, and flush to Supabase with automatic retry when connectivity returns.

**Architecture:** Four isolated units — a file-backed `SessionDraftStore` (in-progress draft + pending-flush queue), a `ConnectivityMonitor` (NWPathMonitor wrapper), a `SessionSyncCoordinator` (drains the queue on reconnect/foreground/launch), and an idempotent `SupabaseSessionWriter` (upsert). `ActiveWorkoutModel` writes a draft per logged set and enqueues before saving; `AppShell` offers Resume on relaunch. Builds on BAK-31's `SaveState`/`pendingSession`/`retrySave`.

**Tech Stack:** Swift 6 / SwiftUI, `@Observable`, Swift Concurrency, `Network` (`NWPathMonitor`), `Codable` JSON to Application Support, XCTest + XCUITest, XcodeGen.

**Prerequisites:** BAK-31 (PR #24) is merged into `main` (this plan assumes `ActiveWorkoutModel.SaveState`, `pendingSession`, `finishAndSave(now:)`, `attemptSave()`, `retrySave()`, and `MockSessionWriter` with `failOnce`/`failAlways`/`attempts` exist). Rebase this branch on `main` after #24 lands before starting.

**Spec:** `docs/superpowers/specs/2026-06-07-offline-active-session-design.md`

**Conventions:** After creating any new file under `Pulse/` or `PulseTests/`, run `xcodegen generate` before building (XcodeGen picks up new files on regenerate). Build/test command template:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:PulseTests/<ClassName>
```

---

## File Structure

**Create:**
- `Pulse/Core/Data/Offline/SessionDraft.swift` — the on-disk draft model.
- `Pulse/Core/Data/Offline/SessionDraftStore.swift` — protocol + `FileSessionDraftStore`.
- `Pulse/Core/Data/Offline/ConnectivityMonitor.swift` — protocol + `NWPathConnectivityMonitor`.
- `Pulse/Core/Data/Offline/SessionSyncCoordinator.swift` — `@Observable` flush owner.
- `Pulse/Core/Data/Mocks/OfflineMocks.swift` — `InMemorySessionDraftStore`, `MockConnectivityMonitor`.
- `PulseTests/Offline/FileSessionDraftStoreTests.swift`
- `PulseTests/Offline/SessionSyncCoordinatorTests.swift`
- `PulseTests/Offline/ActiveWorkoutDraftTests.swift`

**Modify:**
- `Pulse/Core/Data/Supabase/SupabaseSessionWriter.swift` — `insert` → `upsert(onConflict:)`.
- `Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift` — inject store; draft writes; enqueue-first finish; `resume(from:)`.
- `Pulse/App/AppEnvironment.swift` — add `sessionDraftStore` to `RepositoryContainer`; `-uiTestSeedDraft`.
- `Pulse/App/AppShell.swift` — build coordinator; flush on `scenePhase`; Resume prompt; pass store to the model.
- `PulseUITests/ActiveWorkoutFlowTests.swift` — Resume-prompt UI test.
- `docs/superpowers/README.md` — index row for BAK-32.

---

## Task 1: `SessionDraft` model + `FileSessionDraftStore`

**Files:**
- Create: `Pulse/Core/Data/Offline/SessionDraft.swift`
- Create: `Pulse/Core/Data/Offline/SessionDraftStore.swift`
- Test: `PulseTests/Offline/FileSessionDraftStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// PulseTests/Offline/FileSessionDraftStoreTests.swift
import XCTest
@testable import Pulse

final class FileSessionDraftStoreTests: XCTestCase {
    private var dir: URL!
    private var store: FileSessionDraftStore!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PulseDraftTests-\(UUID().uuidString)", isDirectory: true)
        store = FileSessionDraftStore(directory: dir)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func sampleDraft() -> SessionDraft {
        SessionDraft(workout: ActiveWorkoutSample.workout,
                     startedAt: Date(timeIntervalSince1970: 1000),
                     loggedSets: [1: SessionSet(exerciseID: UUID(), order: 1, reps: 10, weight: 60, type: .working)],
                     stepIdx: 1, swaps: [:], doneSteps: [1],
                     savedAt: Date(timeIntervalSince1970: 1001))
    }
    private func sampleSession(id: UUID = UUID()) -> WorkoutSession {
        WorkoutSession(id: id, workoutID: UUID(), startedAt: Date(timeIntervalSince1970: 1),
                       endedAt: Date(timeIntervalSince1970: 2),
                       sets: [SessionSet(exerciseID: UUID(), order: 0, reps: 8, weight: 50, type: .working)])
    }

    func testSaveLoadClearDraftRoundTrips() throws {
        XCTAssertNil(try store.loadDraft())
        let d = sampleDraft()
        try store.saveDraft(d)
        let loaded = try store.loadDraft()
        XCTAssertEqual(loaded, d)
        try store.clearDraft()
        XCTAssertNil(try store.loadDraft())
    }

    func testEnqueuePendingRemove() throws {
        XCTAssertTrue(try store.pending().isEmpty)
        let a = sampleSession(); let b = sampleSession()
        try store.enqueue(a); try store.enqueue(b)
        XCTAssertEqual(try store.pending().map(\.id), [a.id, b.id])
        try store.enqueue(a)   // idempotent: no duplicate, moved to end
        XCTAssertEqual(try store.pending().count, 2)
        try store.remove(id: a.id)
        XCTAssertEqual(try store.pending().map(\.id), [b.id])
    }

    func testSchemaMismatchDiscardsDraft() throws {
        try store.saveDraft(sampleDraft())
        // Corrupt the on-disk schemaVersion.
        let url = dir.appendingPathComponent("draft.json")
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        json["schemaVersion"] = 999
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        XCTAssertNil(try store.loadDraft())             // discarded
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:PulseTests/FileSessionDraftStoreTests`
Expected: BUILD FAILS — `cannot find 'SessionDraft' / 'FileSessionDraftStore' in scope`.

- [ ] **Step 3: Implement `SessionDraft`**

```swift
// Pulse/Core/Data/Offline/SessionDraft.swift
import Foundation

/// The in-progress active session, persisted to disk as each set is logged so a
/// crash/kill mid-workout can be recovered (BAK-32). Everything needed to resume
/// the active flow is captured here.
struct SessionDraft: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = SessionDraft.currentSchemaVersion
    var workout: Workout
    var startedAt: Date
    var loggedSets: [Int: SessionSet]
    var stepIdx: Int
    var swaps: [Int: Exercise]
    var doneSteps: Set<Int>
    var savedAt: Date
}
```

- [ ] **Step 4: Implement `SessionDraftStore` + `FileSessionDraftStore`**

```swift
// Pulse/Core/Data/Offline/SessionDraftStore.swift
import Foundation

/// On-disk buffer for the active flow: one in-progress draft plus a queue of
/// finished-but-unsynced sessions awaiting flush to Supabase (BAK-32).
protocol SessionDraftStore {
    func saveDraft(_ draft: SessionDraft) throws
    func loadDraft() throws -> SessionDraft?
    func clearDraft() throws
    func enqueue(_ session: WorkoutSession) throws
    func pending() throws -> [WorkoutSession]
    func remove(id: WorkoutSession.ID) throws
}

/// JSON-file implementation under Application Support (atomic writes). Inject a
/// `directory` in tests to use a temp folder.
final class FileSessionDraftStore: SessionDraftStore {
    private let directory: URL
    private let fm = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var draftURL: URL { directory.appendingPathComponent("draft.json") }
    private var pendingURL: URL { directory.appendingPathComponent("pending.json") }

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil, create: true))
                ?? FileManager.default.temporaryDirectory
            self.directory = base.appendingPathComponent("PulseSessions", isDirectory: true)
        }
        encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        try? fm.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func saveDraft(_ draft: SessionDraft) throws {
        try encoder.encode(draft).write(to: draftURL, options: .atomic)
    }

    func loadDraft() throws -> SessionDraft? {
        guard fm.fileExists(atPath: draftURL.path) else { return nil }
        let data = try Data(contentsOf: draftURL)
        guard let draft = try? decoder.decode(SessionDraft.self, from: data),
              draft.schemaVersion == SessionDraft.currentSchemaVersion else {
            try? clearDraft()   // corrupt or wrong schema → discard, never resurrect
            return nil
        }
        return draft
    }

    func clearDraft() throws {
        if fm.fileExists(atPath: draftURL.path) { try fm.removeItem(at: draftURL) }
    }

    func enqueue(_ session: WorkoutSession) throws {
        var q = (try? pending()) ?? []
        q.removeAll { $0.id == session.id }   // idempotent: re-enqueue moves to end
        q.append(session)
        try writePending(q)
    }

    func pending() throws -> [WorkoutSession] {
        guard fm.fileExists(atPath: pendingURL.path) else { return [] }
        return (try? decoder.decode([WorkoutSession].self, from: Data(contentsOf: pendingURL))) ?? []
    }

    func remove(id: WorkoutSession.ID) throws {
        var q = (try? pending()) ?? []
        q.removeAll { $0.id == id }
        try writePending(q)
    }

    private func writePending(_ q: [WorkoutSession]) throws {
        try encoder.encode(q).write(to: pendingURL, options: .atomic)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:PulseTests/FileSessionDraftStoreTests`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add Pulse/Core/Data/Offline/SessionDraft.swift Pulse/Core/Data/Offline/SessionDraftStore.swift PulseTests/Offline/FileSessionDraftStoreTests.swift project.yml
git commit -m "feat(offline): file-backed session draft + pending queue store [BAK-32]"
```

---

## Task 2: `ConnectivityMonitor` + mocks

**Files:**
- Create: `Pulse/Core/Data/Offline/ConnectivityMonitor.swift`
- Create: `Pulse/Core/Data/Mocks/OfflineMocks.swift`

No standalone unit test for the live `NWPath` monitor (it observes the real network); it's exercised via `SessionSyncCoordinatorTests` with the mock in Task 4. This task just adds the protocol, the real impl, and the test doubles.

- [ ] **Step 1: Implement the protocol + `NWPathConnectivityMonitor`**

```swift
// Pulse/Core/Data/Offline/ConnectivityMonitor.swift
import Foundation
import Network

/// Reports connectivity and fires `onOnline` when the network transitions from
/// offline → online, so queued sessions can auto-flush (BAK-32).
protocol ConnectivityMonitor: AnyObject {
    var isOnline: Bool { get }
    /// Invoked on the main actor at each offline → online transition.
    var onOnline: (() -> Void)? { get set }
    func start()
    func stop()
}

final class NWPathConnectivityMonitor: ConnectivityMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.pulse.connectivity")
    private(set) var isOnline: Bool = true
    var onOnline: (() -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let nowOnline = path.status == .satisfied
            let wasOnline = self.isOnline
            self.isOnline = nowOnline
            if nowOnline && !wasOnline {
                Task { @MainActor in self.onOnline?() }
            }
        }
        monitor.start(queue: queue)
    }

    func stop() { monitor.cancel() }
}
```

- [ ] **Step 2: Implement the test doubles**

```swift
// Pulse/Core/Data/Mocks/OfflineMocks.swift
import Foundation

/// In-memory `SessionDraftStore` for tests/previews (no disk).
final class InMemorySessionDraftStore: SessionDraftStore {
    private(set) var draft: SessionDraft?
    private(set) var queue: [WorkoutSession] = []

    func saveDraft(_ draft: SessionDraft) throws { self.draft = draft }
    func loadDraft() throws -> SessionDraft? { draft }
    func clearDraft() throws { draft = nil }
    func enqueue(_ session: WorkoutSession) throws {
        queue.removeAll { $0.id == session.id }; queue.append(session)
    }
    func pending() throws -> [WorkoutSession] { queue }
    func remove(id: WorkoutSession.ID) throws { queue.removeAll { $0.id == id } }
}

/// Manually drivable connectivity for tests.
final class MockConnectivityMonitor: ConnectivityMonitor {
    var isOnline: Bool = true
    var onOnline: (() -> Void)?
    func start() {}
    func stop() {}
    /// Simulate the offline → online transition.
    func goOnline() { isOnline = true; onOnline?() }
    func goOffline() { isOnline = false }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Pulse/Core/Data/Offline/ConnectivityMonitor.swift Pulse/Core/Data/Mocks/OfflineMocks.swift project.yml
git commit -m "feat(offline): connectivity monitor (NWPath) + offline test doubles [BAK-32]"
```

---

## Task 3: Idempotent `SupabaseSessionWriter`

**Files:**
- Modify: `Pulse/Core/Data/Supabase/SupabaseSessionWriter.swift`

The supabase-swift `upsert` is the same call shape as `insert` with an `onConflict` column; re-flushing a session that partially (or fully) wrote no longer dup-keys. No unit test (requires a live client; covered behaviorally by the coordinator dedup in Task 4 and AC3 at integration).

- [ ] **Step 1: Change both inserts to upserts**

In `func save(_ session: WorkoutSession)`, replace the two `.insert(...)` calls:

```swift
        try await client.from("sessions").upsert(SessionRow(
            id: session.id, userId: userID, workoutId: session.workoutID,
            startedAt: session.startedAt, endedAt: session.endedAt),
            onConflict: "id").execute()

        let rows = session.sets.map { s in
            SetRow(id: s.id, sessionId: session.id, exerciseId: s.exerciseID,
                   variationId: s.variationID, reps: s.reps, weight: s.weight,
                   type: s.type.rawValue, order: s.order)
        }
        if !rows.isEmpty {
            try await client.from("session_sets").upsert(rows, onConflict: "id").execute()
        }
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Pulse/Core/Data/Supabase/SupabaseSessionWriter.swift
git commit -m "fix(data): idempotent session save via upsert(onConflict: id) [BAK-32]"
```

---

## Task 4: `SessionSyncCoordinator`

**Files:**
- Create: `Pulse/Core/Data/Offline/SessionSyncCoordinator.swift`
- Test: `PulseTests/Offline/SessionSyncCoordinatorTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// PulseTests/Offline/SessionSyncCoordinatorTests.swift
import XCTest
@testable import Pulse

@MainActor
final class SessionSyncCoordinatorTests: XCTestCase {

    private func session(id: UUID = UUID()) -> WorkoutSession {
        WorkoutSession(id: id, workoutID: UUID(), startedAt: Date(timeIntervalSince1970: 1),
                       endedAt: Date(timeIntervalSince1970: 2),
                       sets: [SessionSet(exerciseID: UUID(), order: 0, reps: 5, weight: 40, type: .working)])
    }

    func testFlushDrainsAllOnSuccess() async throws {
        let store = InMemorySessionDraftStore()
        try store.enqueue(session()); try store.enqueue(session())
        let writer = MockSessionWriter()
        let coord = SessionSyncCoordinator(writer: writer, store: store, monitor: MockConnectivityMonitor())
        await coord.flushPending()
        XCTAssertTrue(try store.pending().isEmpty)
        XCTAssertEqual(writer.saved.count, 2)
        XCTAssertEqual(coord.pendingCount, 0)
    }

    func testFlushRetainsTailOnFailure() async throws {
        let store = InMemorySessionDraftStore()
        let a = session(); let b = session()
        try store.enqueue(a); try store.enqueue(b)
        let writer = MockSessionWriter(); writer.failAlways = NSError(domain: "t", code: 1)
        let coord = SessionSyncCoordinator(writer: writer, store: store, monitor: MockConnectivityMonitor())
        await coord.flushPending()
        XCTAssertEqual(try store.pending().count, 2)   // nothing drained
    }

    func testConnectivityRestoredTriggersFlush() async throws {
        let store = InMemorySessionDraftStore()
        try store.enqueue(session())
        let writer = MockSessionWriter()
        let monitor = MockConnectivityMonitor()
        _ = SessionSyncCoordinator(writer: writer, store: store, monitor: monitor)
        monitor.goOnline()                              // fires onOnline → flush
        // onOnline schedules an async flush; yield until it lands.
        for _ in 0..<20 where !(try store.pending().isEmpty) { await Task.yield() }
        XCTAssertTrue(try store.pending().isEmpty)
        XCTAssertEqual(writer.saved.count, 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:PulseTests/SessionSyncCoordinatorTests`
Expected: BUILD FAILS — `cannot find 'SessionSyncCoordinator' in scope`.

- [ ] **Step 3: Implement `SessionSyncCoordinator`**

```swift
// Pulse/Core/Data/Offline/SessionSyncCoordinator.swift
import Foundation
import Observation

/// App-scoped owner of the flush loop: drains the pending-session queue through
/// the real `SessionWriter` on reconnect, app foreground/launch, and manual retry
/// (BAK-32). Stops on the first failure so the tail stays queued for next time.
@MainActor
@Observable
final class SessionSyncCoordinator {
    private let writer: any SessionWriter
    private let store: SessionDraftStore
    private let monitor: ConnectivityMonitor
    private var isFlushing = false

    private(set) var pendingCount: Int = 0

    init(writer: any SessionWriter, store: SessionDraftStore, monitor: ConnectivityMonitor) {
        self.writer = writer
        self.store = store
        self.monitor = monitor
        refreshPendingCount()
        monitor.onOnline = { [weak self] in Task { await self?.flushPending() } }
        monitor.start()
    }

    func refreshPendingCount() { pendingCount = ((try? store.pending()) ?? []).count }

    /// Drain oldest-first; remove each session that saves; stop on first failure.
    func flushPending() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false; refreshPendingCount() }

        for session in (try? store.pending()) ?? [] {
            do {
                try await writer.save(session)
                try? store.remove(id: session.id)
            } catch {
                break
            }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:PulseTests/SessionSyncCoordinatorTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Pulse/Core/Data/Offline/SessionSyncCoordinator.swift PulseTests/Offline/SessionSyncCoordinatorTests.swift project.yml
git commit -m "feat(offline): session sync coordinator drains queue on reconnect [BAK-32]"
```

---

## Task 5: `ActiveWorkoutModel` — draft writes, enqueue-first finish, resume

**Files:**
- Modify: `Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift`
- Test: `PulseTests/Offline/ActiveWorkoutDraftTests.swift`

This injects a `SessionDraftStore` into the model (default `FileSessionDraftStore()` so existing call sites keep working), persists a draft on each state change, enqueues before saving on finish, removes from the queue on save success, and adds `resume(from:)`.

- [ ] **Step 1: Write the failing test**

```swift
// PulseTests/Offline/ActiveWorkoutDraftTests.swift
import XCTest
@testable import Pulse

@MainActor
final class ActiveWorkoutDraftTests: XCTestCase {

    private func makeModel(store: SessionDraftStore, writer: MockSessionWriter = MockSessionWriter()) -> ActiveWorkoutModel {
        ActiveWorkoutModel(exerciseRepo: MockSwapAlternativesRepository(),
                           historyRepo: MockHistoryRepository(),
                           sessionWriter: writer,
                           draftStore: store)
    }

    func testLogSetWritesDraft() throws {
        let store = InMemorySessionDraftStore()
        let m = makeModel(store: store)
        m.startWorkout(ActiveWorkoutSample.workout); m.beginSets()
        m.logSet(reps: 12, weight: 60)
        let draft = try store.loadDraft()
        XCTAssertNotNil(draft)
        XCTAssertEqual(draft?.loggedSets.isEmpty, false)
    }

    func testFinishEnqueuesBeforeSaveAndClearsDraftOnSuccess() async throws {
        let store = InMemorySessionDraftStore()
        let writer = MockSessionWriter()
        let m = makeModel(store: store, writer: writer)
        m.startWorkout(ActiveWorkoutSample.workout); m.beginSets()
        m.logSet(reps: 12, weight: 60)
        await m.finishAndSave()
        XCTAssertEqual(writer.saved.count, 1)
        XCTAssertTrue(try store.pending().isEmpty)   // removed after success
        XCTAssertNil(try store.loadDraft())          // draft cleared on finish
    }

    func testFinishKeepsSessionQueuedWhenSaveFails() async throws {
        let store = InMemorySessionDraftStore()
        let writer = MockSessionWriter(); writer.failAlways = NSError(domain: "t", code: 1)
        let m = makeModel(store: store, writer: writer)
        m.startWorkout(ActiveWorkoutSample.workout); m.beginSets()
        m.logSet(reps: 12, weight: 60)
        await m.finishAndSave()
        if case .failed = m.saveState {} else { XCTFail("expected .failed") }
        XCTAssertEqual(try store.pending().count, 1) // durably queued for auto-flush
    }

    func testResumeRestoresState() throws {
        let store = InMemorySessionDraftStore()
        let m = makeModel(store: store)
        let draft = SessionDraft(workout: ActiveWorkoutSample.workout,
                                 startedAt: Date(timeIntervalSince1970: 1000),
                                 loggedSets: [1: SessionSet(exerciseID: UUID(), order: 1, reps: 10, weight: 55, type: .working)],
                                 stepIdx: 1, swaps: [:], doneSteps: [1],
                                 savedAt: Date(timeIntervalSince1970: 1001))
        m.resume(from: draft)
        XCTAssertTrue(m.isActive)
        XCTAssertEqual(m.phase, .active)
        XCTAssertEqual(m.stepIdx, 1)
        XCTAssertEqual(m.doneSteps, [1])
        XCTAssertEqual(m.loggedSets.count, 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:PulseTests/ActiveWorkoutDraftTests`
Expected: BUILD FAILS — extra `draftStore:` argument / no `resume(from:)`.

- [ ] **Step 3: Add the stored property + init param**

In `ActiveWorkoutModel`, add after the `sessionWriter` dependency:

```swift
    private let draftStore: SessionDraftStore
```

Update the initializer:

```swift
    init(exerciseRepo: SwapAlternativesProviding,
         historyRepo: HistoryRepository,
         sessionWriter: SessionWriter,
         draftStore: SessionDraftStore = FileSessionDraftStore()) {
        self.exerciseRepo = exerciseRepo
        self.historyRepo = historyRepo
        self.sessionWriter = sessionWriter
        self.draftStore = draftStore
    }
```

- [ ] **Step 4: Persist a draft on state changes**

Add this helper (anywhere in the class):

```swift
    /// Snapshot the in-progress session to disk so a crash/kill can recover it.
    private func persistDraft() {
        guard isActive else { return }
        let draft = SessionDraft(workout: workout, startedAt: startedAt,
                                 loggedSets: loggedSets, stepIdx: stepIdx,
                                 swaps: swaps, doneSteps: doneSteps, savedAt: .now)
        try? draftStore.saveDraft(draft)
    }
```

Call `persistDraft()` at the end of `logSet(reps:weight:now:)` (just before the method returns — after the phase branch), and at the end of `skipSet()`, `afterRest()`, and `swap(exerciseIndex:to:)`. For `logSet`, place it after the `if/else if/else` phase block:

```swift
        if stepIdx == steps.count - 1 {
            phase = .summary
        } else if step.rest {
            startRest(now: now)
            phase = .rest
        } else {
            stepIdx += 1
            phase = .active
        }
        persistDraft()
    }
```

- [ ] **Step 5: Enqueue-first finish + clear draft + dequeue on success**

Replace `finishAndSave(now:)` and `attemptSave()`:

```swift
    func finishAndSave(now: Date = .now) async {
        let sets = loggedSets.values.sorted { $0.order < $1.order }
        let session = WorkoutSession(workoutID: workout.id, startedAt: startedAt,
                                     endedAt: now, sets: sets)
        pendingSession = session
        try? draftStore.enqueue(session)   // durable BEFORE attempting the save
        try? draftStore.clearDraft()       // no longer in-progress
        await attemptSave()
    }

    func retrySave() async { await attemptSave() }

    private func attemptSave() async {
        guard let session = pendingSession else { return }
        saveState = .saving
        do {
            try await sessionWriter.save(session)
            try? draftStore.remove(id: session.id)   // synced → drop from queue
            saveState = .saved
            pendingSession = nil
            endWorkout()
        } catch {
            print("[Pulse] session save failed: \(error)")
            saveState = .failed("Couldn’t save your workout. Check your connection and try again.")
        }
    }
```

- [ ] **Step 6: Add `resume(from:)`**

```swift
    /// Restore an in-progress session recovered from disk back into the active flow.
    func resume(from draft: SessionDraft) {
        workout = draft.workout
        steps = buildSteps(draft.workout)
        loggedSets = draft.loggedSets
        swaps = draft.swaps
        doneSteps = draft.doneSteps
        stepIdx = min(max(0, draft.stepIdx), max(0, steps.count - 1))
        startedAt = draft.startedAt
        restEndsAt = nil
        phase = .active
        isActive = true
        activeSheet = nil
        saveState = .idle
        pendingSession = nil
    }
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:PulseTests/ActiveWorkoutDraftTests`
Expected: PASS (4 tests).

- [ ] **Step 8: Run the existing model + flow tests to confirm no regression**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:PulseTests/ActiveWorkoutModelTests`
Expected: PASS (all existing BAK-14/BAK-31 tests still green).

- [ ] **Step 9: Commit**

```bash
git add Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift PulseTests/Offline/ActiveWorkoutDraftTests.swift
git commit -m "feat(active): persist draft + enqueue-first save + resume [BAK-32]"
```

---

## Task 6: App wiring — container, coordinator, scenePhase flush, Resume prompt

**Files:**
- Modify: `Pulse/App/AppEnvironment.swift`
- Modify: `Pulse/App/AppShell.swift`
- Modify: `PulseUITests/ActiveWorkoutFlowTests.swift`

- [ ] **Step 1: Add `sessionDraftStore` to `RepositoryContainer`**

In `RepositoryContainer` (`Pulse/App/AppEnvironment.swift`), add the stored property near `sessionWriter`:

```swift
    /// On-disk buffer for the active flow (draft + pending-flush queue).
    let sessionDraftStore: SessionDraftStore
```

In **both** branches of `init(useMock:)`, set it. Mock branch (after the `sessionWriter = writer` block from BAK-31). Use a **per-launch clean temp directory** so a seeded draft never persists across simulator launches and bleeds into other UI tests:

```swift
            // UI tests share the simulator's Application Support, so a seeded draft
            // would leak across launches. Point the mock store at a temp dir we wipe
            // on each launch; only -uiTestSeedDraft repopulates it.
            let uiDraftDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("PulseUITestDrafts", isDirectory: true)
            try? FileManager.default.removeItem(at: uiDraftDir)
            sessionDraftStore = FileSessionDraftStore(directory: uiDraftDir)
            // -uiTestSeedDraft: seed a recoverable draft so the Resume prompt shows.
            if CommandLine.arguments.contains("-uiTestSeedDraft") {
                try? sessionDraftStore.saveDraft(
                    SessionDraft(workout: ActiveWorkoutSample.workout, startedAt: .now,
                                 loggedSets: [0: SessionSet(exerciseID: ActiveWorkoutSample.bench.id,
                                                            order: 0, reps: 12, weight: 60, type: .working)],
                                 stepIdx: 0, swaps: [:], doneSteps: [0], savedAt: .now))
            }
```

Live branch (after `sessionWriter = SupabaseSessionWriter(client: client)`):

```swift
            sessionDraftStore = FileSessionDraftStore()
```

- [ ] **Step 2: Build to verify wiring compiles**

Run: `xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Wire the coordinator, scenePhase flush, and Resume prompt in `AppShell`**

In `AppShell` (`Pulse/App/AppShell.swift`):

Pass the store into the model in `init` — change the `ActiveWorkoutModel(...)` construction to add `draftStore: container.sessionDraftStore`:

```swift
        let session = ActiveWorkoutModel(
            exerciseRepo: MockSwapAlternativesRepository(),
            historyRepo: MockHistoryRepository(),
            sessionWriter: container.sessionWriter,
            draftStore: container.sessionDraftStore)
        _session = State(initialValue: session)
```

Add stored state for the coordinator and the recovery draft (after the existing `@State` properties):

```swift
    @State private var sync: SessionSyncCoordinator
    @State private var recoverableDraft: SessionDraft?
    @Environment(\.scenePhase) private var scenePhase
```

Initialize `sync` in `init` (after `_session` is set):

```swift
        _sync = State(initialValue: SessionSyncCoordinator(
            writer: container.sessionWriter,
            store: container.sessionDraftStore,
            monitor: NWPathConnectivityMonitor()))
```

Add the flush-on-foreground + recovery-on-launch modifiers to the top-level `Group` in `body` (alongside the existing `.task { await container.bootstrap() }`):

```swift
        .task {
            await sync.flushPending()
            if let draft = try? container.sessionDraftStore.loadDraft(),
               Date.now.timeIntervalSince(draft.savedAt) < 24 * 60 * 60 {
                recoverableDraft = draft
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await sync.flushPending() } }
        }
        .confirmationDialog("Resume your workout?",
                            isPresented: Binding(get: { recoverableDraft != nil },
                                                 set: { if !$0 { recoverableDraft = nil } }),
                            titleVisibility: .visible) {
            Button("Resume") {
                if let d = recoverableDraft { session.resume(from: d) }
                recoverableDraft = nil
            }
            Button("Discard", role: .destructive) {
                if let d = recoverableDraft {
                    // Keep the logged work: enqueue as finished, flush, clear draft.
                    let finished = WorkoutSession(workoutID: d.workout.id, startedAt: d.startedAt,
                                                  endedAt: .now,
                                                  sets: d.loggedSets.values.sorted { $0.order < $1.order })
                    try? container.sessionDraftStore.enqueue(finished)
                    try? container.sessionDraftStore.clearDraft()
                    Task { await sync.flushPending() }
                }
                recoverableDraft = nil
            }
        } message: {
            Text("You have an unfinished workout. Resume it, or save what you logged and close.")
        }
        .accessibilityIdentifier("app.resumePrompt")
```

- [ ] **Step 4: Add the Resume-prompt UI test**

In `PulseUITests/ActiveWorkoutFlowTests.swift`, add:

```swift
    // BAK-32 — relaunch with a recovered draft offers Resume; Resume re-enters the flow.
    func testRecoveredDraftOffersResume() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiMock", "-uiTestSeedDraft"]
        app.launch()
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 5))
        app.buttons["Resume"].tap()
        XCTAssertTrue(app.buttons["active.log"].waitForExistence(timeout: 5))  // back in active flow
    }
```

- [ ] **Step 5: Run the Resume UI test + existing flow tests**

Run: `xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:PulseUITests/ActiveWorkoutFlowTests`
Expected: PASS — `testRecoveredDraftOffersResume` plus all existing flow tests (incl. BAK-31's `testSaveFailureSurfacesErrorThenRetrySucceeds`).

- [ ] **Step 6: Commit**

```bash
git add Pulse/App/AppEnvironment.swift Pulse/App/AppShell.swift PulseUITests/ActiveWorkoutFlowTests.swift project.yml
git commit -m "feat(offline): wire sync coordinator + scenePhase flush + resume prompt [BAK-32]"
```

---

## Task 7: Full verification + index

**Files:**
- Modify: `docs/superpowers/README.md`

- [ ] **Step 1: Run the full suite**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: `** TEST SUCCEEDED **` (all unit + UI suites).

- [ ] **Step 2: Add a README index row for BAK-32**

In the table in `docs/superpowers/README.md`, add:

```markdown
| BAK-32 | Offline-resilient active session | 14, 27, 31 | [spec](specs/2026-06-07-offline-active-session-design.md) | [plan](plans/2026-06-07-offline-active-session.md) |
```

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/README.md
git commit -m "docs: index BAK-32 spec + plan [BAK-32]"
```

- [ ] **Step 4: Open the PR (do NOT merge — human gate)**

```bash
git push -u origin feature/bak-32-offline-active-session
gh pr create --base main \
  --title "BAK-32: offline-resilient active session (buffer + flush/retry)" \
  --body "Closes BAK-32. Builds on BAK-31 (#24). Buffers the active session to disk as logged, queues + flushes on finish with auto-retry on reconnect (NWPathMonitor), idempotent upsert, Resume-on-relaunch. See docs/superpowers/specs/2026-06-07-offline-active-session-design.md."
```

Then move BAK-32 to In Progress in Linear with a PR-link comment (the team has no "In Review" state).

---

## Acceptance criteria → task map

1. Draft on disk per set; relaunch offers Resume restoring sets/step → **Task 1, 5, 6** (`testLogSetWritesDraft`, `testResumeRestoresState`, `testRecoveredDraftOffersResume`).
2. Offline finish kept + auto-syncs on reconnect → **Task 4, 5** (`testFinishKeepsSessionQueuedWhenSaveFails`, `testConnectivityRestoredTriggersFlush`).
3. Partial-write re-flush is idempotent → **Task 3** (upsert `onConflict: id`).
4. Discarding a recovered draft still persists logged sets → **Task 6** (Discard branch enqueues + flushes).
5. Existing active-flow + BAK-31 tests stay green; new unit + UI coverage → **Task 5 (Step 8), Task 6 (Step 5), Task 7**.
