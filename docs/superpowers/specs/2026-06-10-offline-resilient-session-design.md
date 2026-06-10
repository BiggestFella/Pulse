# Offline-resilient active session — design (BAK-32)

- **Date:** 2026-06-10
- **Issue:** BAK-32 — Offline-resilient active session (approach C: buffer + flush/retry)
- **Status:** Draft (brainstorm) → ⏸ awaiting human approval of this spec
- **Related:** BAK-31 (surface save errors + don't silently drop — groundwork already on
  branch), BAK-27 (online-first Supabase writer, Done), BAK-32 supersedes the deferred
  offline note in the BAK-27 data-layer spec.

## Context

Real gym usage lost a finished workout to flaky connectivity (BAK-31): the save threw,
and although BAK-31 now surfaces the failure and keeps the session **in memory** for a
manual retry, that retry is lost the moment the app is killed or the user navigates away.

The active flow already has the right seam:

- `ActiveWorkoutModel` holds a `pendingSession: WorkoutSession?` and a
  `SaveState { idle, saving, saved, failed(String) }`, with `finishAndSave()` →
  `attemptSave()` → `retrySave()` (`Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift`).
- `SummaryView` surfaces `.failed` with a "Retry save" button.
- `SessionWriter` is a one-method protocol (`save(_ session:) async throws`) injected via
  `RepositoryContainer`; the real impl is `SupabaseSessionWriter`.
- `WorkoutSession` / `SessionSet` are already `Codable`.

What's missing: the buffer is **in-memory only**, there is **no connectivity monitoring**,
and a pending save is **invisible once you leave the summary**. This ticket adds durability
+ auto-retry on top of BAK-31.

This is **approach C** (contained): buffer the in-flight session locally and flush on
finish with retry on reconnect. Full offline read-cache + general write-queue (approach B)
stays deferred to its own future ticket.

## Decisions (confirmed 2026-06-10)

1. **Buffer on finish + on failure** — when the user taps Done we persist the assembled
   `WorkoutSession` to disk, attempt the remote save, and clear the buffer on success /
   keep it on failure. We do **not** write incrementally on every logged set, so an app
   crash *mid-workout* is not recoverable (out of scope) — this targets the BAK-31
   connectivity-loss-at-finish case.
2. **Auto-flush on reconnect** — introduce a lightweight connectivity monitor
   (`NWPathMonitor`); when the network returns (and on app foreground / launch) any pending
   buffered session is flushed in the background. The manual "Retry save" button stays.
3. **Global pending-sync indicator** — a persistent "1 workout pending sync" affordance
   visible after the user leaves the summary (Today tab), in addition to the existing
   summary-screen error UI.

## Goals

- A finished workout is **never lost** to connectivity: it persists locally until it
  reaches Supabase, surviving app kill/relaunch.
- On reconnect (or next launch / foreground) a pending session **flushes automatically**
  with no user action.
- The user can always **see** there is a workout pending sync, and can still retry/flush
  manually.

## Non-goals (deferred)

- **Crash-safe incremental buffering** (persist every logged set mid-workout).
- **General offline read-cache / write-queue** for programs, schedule, builders (approach B).
- **Multiple queued sessions** beyond what naturally falls out of the store — v1 expects at
  most one or a small handful pending; no dedupe/conflict UI.
- **Background-task (BGTask) wake-ups** while the app is suspended — flush happens on
  foreground/launch/reconnect-while-running, not via background scheduling.

## Architecture

A **decorator** around the existing `SessionWriter`, plus a tiny local store and a
connectivity monitor — no change to `SupabaseSessionWriter` or the domain models.

- **`PendingSessionStore`** (`Pulse/Core/Data/Offline/`) — durable store for buffered
  sessions. File-based JSON in Application Support (`pending-sessions.json` via a
  configured `JSONEncoder`/`Decoder`), since the app has no SwiftData and the payload is a
  small `Codable` array. API: `enqueue(_:)`, `all()`, `remove(id:)`, `isEmpty`. `@MainActor`
  `@Observable` so views can read pending count reactively.
- **`ConnectivityMonitor`** (`Pulse/Core/Data/Offline/`) — wraps `NWPathMonitor` on a
  background queue, exposes an `@Observable isOnline: Bool` and an async stream / callback
  for "became reachable". Injected, with a mock for tests.
- **`BufferedSessionWriter`** — `SessionWriter` decorator wrapping the real writer + the
  store + the monitor. `save(_:)`:
  1. persist to the store first (durability),
  2. attempt the wrapped remote `save`,
  3. on success → `remove(id:)` and return normally,
  4. on failure → leave it in the store and rethrow (so `ActiveWorkoutModel` still shows
     `.failed` exactly as today).
  Also exposes `flushPending()` — drains the store (best-effort, removing each on success),
  invoked on launch, on app foreground, and when the monitor reports reachability.
- **`RepositoryContainer`** wiring (`Pulse/App/AppEnvironment.swift`) — wrap whichever
  concrete writer is chosen (mock or Supabase) in `BufferedSessionWriter`, and own the
  shared `PendingSessionStore` + `ConnectivityMonitor` so a global indicator can read the
  pending count. Under `-uiMock` the store is in-memory/cleared so UI tests stay
  deterministic.

### Distinguishing "pending" from "hard failure"

Buffering must not mask a genuinely un-savable session (e.g. auth misconfig that would
fail forever). v1 keeps it simple: **all** save failures buffer + retry (network is by far
the common case, and a persistent failure simply keeps retrying harmlessly). We classify
*only* for the message — a network/offline error shows "Saved on this device — will sync
when you're back online" (treated as success-ish for teardown), while other errors keep the
existing `.failed("Couldn't save…")` blocking state with the retry button. Exact
classification (URLError vs. others) is pinned down in the plan.

### SaveState change

Add a `pendingSync` case to `SaveState`:
`{ idle, saving, saved, pendingSync, failed(String) }`. When the buffered writer reports the
session is safely on-device but not yet remote (offline), the model enters `.pendingSync`
and **tears down the takeover** (the workout is safe), rather than blocking on `.failed`.
`SummaryView`'s Done label/branching and the BAK-31 tests are updated accordingly.

## UI

- **Summary screen** — `.pendingSync` shows a calm "Saved on this device — will sync when
  you're back online" note (reuses the BAK-31 banner slot, info styling not error styling)
  and the Done button completes normally. `.failed` (non-network) is unchanged.
- **Global indicator** — a small "1 workout pending sync" pill/banner on the **Today** tab,
  driven by `PendingSessionStore` pending count, with a tap-to-retry that calls
  `flushPending()`. Hidden when the store is empty. Uses `Theme` tokens only (Geist Mono
  eyebrow / `onAccent` rules per design system); placement detailed in the plan.

## Testing & verification

- **Unit (CI, mock-backed):**
  - `PendingSessionStore`: enqueue/persist/reload/remove round-trips (inject a temp
    directory); survives "reload" (new instance reads the same file).
  - `BufferedSessionWriter`: success removes from store; failure keeps it + rethrows;
    `flushPending` drains on a now-succeeding writer; offline → `.pendingSync`.
  - `ActiveWorkoutModel`: offline finish → `.pendingSync` + teardown + session buffered;
    reconnect/flush → buffer empties. Existing BAK-31 retry tests updated for the new case.
  - `ConnectivityMonitor`: drive a mock to assert flush fires on "became reachable".
- **UI (XCUITest, via `-uiMock`):** extend the existing save-failure test — with a
  persistently-offline mock writer, finishing shows the on-device note + tabs appear (not
  blocked), and the Today pending-sync indicator is visible; then flip the mock online and
  assert the indicator clears.
- **Manual:** airplane-mode a real session end → workout saved locally, indicator shows;
  re-enable network → session syncs automatically and indicator clears (verify the row
  lands in Supabase).

## Acceptance criteria

- Finishing a workout with no connectivity does **not** lose it: it is written to disk,
  the summary shows a non-blocking "saved on device, will sync" state, and the app tears
  the takeover down normally.
- A pending session survives **app kill + relaunch** and is still flushed afterwards.
- When connectivity returns (reconnect while running, app foreground, or next launch) the
  pending session **flushes automatically** and lands in Supabase.
- A **persistent, visible** "pending sync" indicator appears while anything is buffered and
  clears once everything has synced; it offers a manual retry.
- Genuine non-network failures still surface the BAK-31 blocking error + retry button.
- All existing unit + UI tests stay green (mock path via `-uiMock`); no `Theme` token or
  design-system rules violated.

## Sequencing (for the plan)

1. `PendingSessionStore` (file-based, Codable, injectable dir) + unit tests.
2. `ConnectivityMonitor` (NWPathMonitor wrapper + mock) + unit tests.
3. `BufferedSessionWriter` decorator + `flushPending`; wire into `RepositoryContainer`.
4. `SaveState.pendingSync` + `ActiveWorkoutModel`/`SummaryView` updates; update BAK-31 tests.
5. Global Today-tab pending-sync indicator (Theme-tokened) + UI test.
6. Flush triggers (launch, foreground, reconnect) + full verification.
