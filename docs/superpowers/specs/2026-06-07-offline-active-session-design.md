# Offline-resilient active session — design (BAK-32)

Status: **approved design** (brainstorm 2026-06-07). Approach **C** was decided in
the BAK-32 ticket (2026-06-06): keep it contained — buffer the *active* workout
locally and flush on finish with retry; reads stay online (full offline read-cache +
write-queue is approach B, deferred).

## Context

Triggered by real gym usage (BAK-31): a finished workout was lost because the data
layer is **online-only** (BAK-27) and gym connectivity dropped at save time. BAK-31
fixed the *silent* part — `ActiveWorkoutModel.finishAndSave()` now surfaces a visible
`SaveState` (idle/saving/saved/failed), holds the session pending, and offers a manual
Retry. BAK-32 makes the session **durable** and the retry **automatic**: the workout
is buffered to disk as it's logged, queued on finish, and flushed when connectivity
returns — so neither a dropped connection nor an app kill loses a session.

**Builds on:** BAK-31 (PR #24) — `SaveState`, `pendingSession`, `retrySave()`.

## Goals

- Persist the in-progress session to disk **as each set is logged** (survives an app
  crash/kill mid-workout).
- On finish, durably **queue** the session, then attempt the save.
- **Auto-flush** queued sessions when connectivity is restored, on app
  foreground/launch, and via BAK-31's manual Retry.
- Make re-flush **idempotent** (a partial write that's retried must not dup-key).
- On relaunch with an unfinished draft, offer **Resume**.

## Non-goals (deferred)

- **Offline reads / response cache** (approach B) — reads stay online-only.
- Conflict resolution beyond idempotent upsert (single-user, single-device; last
  write wins by stable `id`).
- Editing/syncing *past* sessions offline.
- Background flush while the app is suspended (flush is triggered by app-active +
  connectivity events, not `BGTaskScheduler`).

## Key decisions

1. **Buffer scope = in-progress + finished.** Draft written on every logged set;
   finished session moved to a pending-flush queue.
2. **Auto-flush on reconnect** via `NWPathMonitor` (Network framework), plus
   foreground/launch and manual Retry.
3. **Resume prompt on relaunch.** Resume restores the active flow; **Discard still
   saves** the logged-so-far session (flushes it as finished) so no logged set is
   lost, then clears the draft.
4. **Idempotent persistence** — `SupabaseSessionWriter.save` upserts `sessions` and
   `session_sets` on `id`. *(Only data-layer touch; coordinate with BAK-27 seeding.)*
5. **File-backed JSON** under Application Support (models are already `Codable`);
   atomic writes; `schemaVersion` on the draft (discard gracefully on mismatch).

## Architecture

Four new, independently testable units; everything else is wiring.

- **`SessionDraftStore`** (protocol) + **`FileSessionDraftStore`** — the on-disk buffer.
  - Draft (single, in-progress): `saveDraft(_ draft: SessionDraft)`, `loadDraft() -> SessionDraft?`, `clearDraft()`.
  - Pending queue (finished, unsynced): `enqueue(_ session: WorkoutSession)`, `pending() -> [WorkoutSession]`, `remove(id: WorkoutSession.ID)`.
  - Two JSON files (`draft.json`, `pending.json`) written atomically (`.atomic`).
  - `SessionDraft`: `schemaVersion`, `workout` (identity needed to resume), `startedAt`,
    `loggedSets: [Int: SessionSet]`, `stepIdx`, `swaps`, `doneSteps`, `savedAt`.
- **`ConnectivityMonitor`** (protocol) + **`NWPathConnectivityMonitor`** — wraps
  `NWPathMonitor` on a background queue; exposes `isOnline` and an offline→online
  callback. A `MockConnectivityMonitor` drives tests.
- **`SessionSyncCoordinator`** (`@Observable`, app-scoped) — owns flush.
  - Deps: `SessionWriter` (real), `SessionDraftStore`, `ConnectivityMonitor`.
  - `flushPending() async` — drain `pending()` oldest-first via the writer; `remove`
    each on success; **stop on first failure** (leave the rest queued for next trigger).
  - Subscribes to connectivity-restored → `flushPending()`. Re-entrancy guarded
    (a single in-flight flush; coalesce triggers).
  - `pendingCount` for optional UI (e.g. a "1 workout pending sync" hint).
- **Idempotent `SupabaseSessionWriter`** — `.upsert(..., onConflict: "id")` for both
  inserts (was `.insert`). Same wire shape; safe to re-run.

## Integration with `ActiveWorkoutModel` (on top of BAK-31)

- Inject `SessionDraftStore` and `SessionSyncCoordinator`.
- `startWorkout(_:)` — `clearDraft()` (abandon any stale draft already recovered/flushed), start a fresh draft.
- `logSet`/`skipSet`/`afterRest`/`swap` (state-mutating steps) — `saveDraft(...)` the
  current snapshot. Writes are small and synchronous-to-disk via the store; failures
  are non-fatal (logged, workout continues).
- `finishAndSave(now:)` — build the `WorkoutSession`; **`enqueue` it first** (durable),
  then `writer.save`. Success → `remove(id:)` + `clearDraft()` → `.saved` + teardown.
  Failure → `.failed` (BAK-31 banner/Retry) while the session stays queued for
  auto-flush. `retrySave()` delegates to `coordinator.flushPending()`.

## Recovery (relaunch with a draft)

- On launch, `AppShell` asks the coordinator/store for a recent `loadDraft()`.
- If present, show a **"Resume your workout?"** prompt:
  - **Resume** → `ActiveWorkoutModel.resume(from: draft)` restores phase/step/logged
    sets and re-enters the active flow.
  - **Discard** → treat the logged-so-far as a finished session: `enqueue` + flush,
    then `clearDraft()`. (Labeled clearly so the user knows their logged sets are kept.)
- "Recent" guard: ignore/cleanup drafts older than a sane TTL (e.g. 24h) to avoid
  resurrecting an abandoned session days later (still flushed, never silently dropped).

## Data flow

1. **Logging** — set logged → model updates state → `saveDraft` (disk).
2. **Finish** — model builds `WorkoutSession` → `enqueue` → `writer.save` (upsert) →
   success removes from queue + clears draft.
3. **Reconnect / foreground / launch** — `coordinator.flushPending()` drains queue
   (upsert each), removing those that succeed.

## Error handling

- **Offline finish** — session is queued; `SaveState = .failed` (BAK-31 UI);
  auto-flush on reconnect; manual Retry available.
- **Partial flush** (session row ok, sets fail) — idempotent upsert makes the retry
  safe; no duplicate-key error, sets re-upserted.
- **Disk write failure** — non-fatal: log and continue; never crash the active flow.
- **Draft schema mismatch** — decode failure → discard the draft (no resume), logged.
- **Flush re-entrancy** — coordinator guards a single in-flight flush; concurrent
  triggers coalesce.

## Testing & verification

- **`FileSessionDraftStore`** (temp dir): save/load/clear draft round-trips; enqueue
  → pending → remove; atomic overwrite; schema-version mismatch discards.
- **`SessionSyncCoordinator`**: `flushPending` drains on success, retains the tail on
  failure (reuse BAK-31's `MockSessionWriter` `failOnce`/`failAlways`); a
  `MockConnectivityMonitor` offline→online event triggers a flush; re-entrancy guard.
- **`ActiveWorkoutModel`**: writes a draft on `logSet`; `finishAndSave` enqueues
  before saving and clears the draft + dequeues on success; `resume(from:)` restores
  state (mock store).
- **UI**: launch with a seeded draft → "Resume your workout?" → Resume re-enters the
  active flow (new `-uiTestSeedDraft` launch arg, mirroring BAK-31's `-uiTestSaveFail`).
  BAK-31's save-failure→retry UI test stays green.
- Build + full suite green; `xcodegen generate` clean.

## Dependencies & coordination (read before implementing)

- **Depends on BAK-31 (PR #24)** — the `SaveState`/pending/retry foundation. Land #24
  first (or rebase BAK-32 on it).
- **Touches `SupabaseSessionWriter`** (insert → upsert) — overlaps the in-flight
  **BAK-27** seeding session. Coordinate / rebase to avoid a clobber.
- **Adds app-scoped wiring** in `RepositoryContainer` + `AppShell` (coordinator,
  monitor, store, resume prompt) — **BAK-24**'s branch also edits `AppShell`; sequence
  after BAK-24 merges or expect a small merge.

## Sequencing (for the plan)

1. `SessionDraftStore` protocol + `FileSessionDraftStore` + tests.
2. `ConnectivityMonitor` protocol + `NWPath` impl + `Mock` + tests.
3. `SupabaseSessionWriter` → idempotent upsert.
4. `SessionSyncCoordinator` + tests.
5. `ActiveWorkoutModel`: draft writes + enqueue-first finish + `resume(from:)` + tests.
6. App wiring: inject into `RepositoryContainer`/`AppShell`; flush on scenePhase +
   connectivity; Resume prompt + `-uiTestSeedDraft` + UI test.
7. Verify: full suite + `xcodegen generate`.

## Acceptance criteria

1. Logging a set writes a draft to disk; killing the app mid-workout and relaunching
   offers **Resume**, which restores the logged sets and current step.
2. Finishing a workout while offline keeps it (queued + `.failed` UI), and it
   **auto-syncs** once connectivity returns — no manual action required.
3. A finished session that partially wrote can be re-flushed **without** a
   duplicate-key error (idempotent upsert).
4. Discarding a recovered draft still **persists** the logged-so-far session.
5. All existing active-flow + BAK-31 tests stay green; new unit + UI tests cover the
   store, coordinator, model draft/enqueue/resume, and the Resume prompt.
