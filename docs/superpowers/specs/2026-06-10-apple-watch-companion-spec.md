# Apple Watch Companion — Spec

**Date:** 2026-06-10
**Status:** Draft (awaiting approval)
**Sequence:** 5 of 5 (large — new target + sync; do last)

## Problem

Logging sets and managing rest from a phone propped against a rack is awkward
mid-set. A wrist app lets the user advance sets, see/control the rest timer, and —
critically — feel a **haptic when rest ends** without looking at the phone. This is
the natural home for the rest-end cue (the wrist haptic beats a phone sound).

## Goals

- A watchOS app target that **mirrors the active session**: current exercise, set
  number, target reps, and the rest countdown.
- From the watch: **log the current set** (with last/seeded weight × reps), adjust
  or skip rest, advance to the next set.
- **Haptic on rest end + 10s warning** on the wrist (`WKInterfaceDevice.play`),
  reusing the cue semantics from the Rest Timer Audio spec.
- Keep phone and watch **in sync** in real time while a session is active.

## Non-goals (v1)

- Starting/finishing a whole workout from the watch (phone starts; watch joins).
- Standalone watch use with no phone nearby (phone is source of truth in v1).
- HealthKit workout recording / heart-rate (valuable follow-up, separate spec).
- Building the watch UI for Library/Plan/Stats — active session only.

## Current state (grounded)

- App is iOS-only (no watch target in `project.yml`). Project is generated via
  XcodeGen — the watch target must be added to `project.yml`, never hand-edited.
- `ActiveWorkoutModel` is the single source of session truth (phase, current step,
  rest `restEndsAt`, seed values, `logSet`, `afterRest`, `adjustRest`).
- A Live Activity / `WorkoutActivityAttributes` already models a shareable session
  snapshot — useful precedent for the sync payload shape.

## Design

### Architecture

- New **watchOS app + extension** target in `project.yml` (`xcodegen generate`).
- Shared session-state types (current step, reps target, weight seed,
  `restEndsAt`, phase) extracted into a small module/group already importable by
  both targets — model the payload on the existing Live Activity attributes.
- **`WatchConnectivity` (`WCSession`)** transport behind a protocol so it's
  mockable and the existing `ActiveWorkoutModel` stays UI-framework-agnostic:
  - `WorkoutSyncChannel` protocol: `send(state:)`, `onCommand(handler:)`.
  - Phone implements with `WCSession` (`updateApplicationContext` for latest
    state; `sendMessage` for commands when reachable).
  - State flows **phone → watch** (snapshot on every change); commands flow
    **watch → phone** (`logSet`, `skipRest`, `adjustRest(±)`, `nextSet`). Phone
    applies the command to `ActiveWorkoutModel`, then broadcasts new state — watch
    never mutates session truth locally.
- Rest countdown on the watch is driven by the **absolute `restEndsAt`** (already
  the phone's design), so no drift; the watch schedules its own local haptics at
  `restEndsAt − 10s` and `restEndsAt`.

### Watch UI (active session only)

- **Set screen:** exercise name, set X of N, target reps, weight; "Log set" button
  (sends `logSet` with seeded values), "Skip set".
- **Rest screen:** big countdown ring (mirrors phone), `−15 / +15 / +30`, "Skip".
- Haptics: `.notification(.success)` at end, lighter at T-10s, gated by
  `soundOnRestEnd`.

### Failure handling

- Watch unreachable → phone keeps working normally; on reconnect, phone pushes the
  latest application context and the watch reconciles to it (last-write-wins from
  phone). Commands sent while unreachable are dropped (phone is authoritative);
  the watch reflects truth on next sync.

## Testing (acceptance criteria)

Unit (with a `MockWorkoutSyncChannel`):
1. Applying a `logSet` command advances the model exactly as an in-app log would.
2. `adjustRest`/`skipRest` commands change `restEndsAt` / phase identically to phone
   actions.
3. State snapshot encodes the fields the watch needs (step, reps, weight,
   `restEndsAt`, phase) and round-trips.
4. Commands received in the wrong phase (e.g. `logSet` during rest) are ignored.

Manual (paired devices — `WCSession` can't be unit-tested):
5. Logging on phone updates the watch within ~1s and vice-versa.
6. Rest-end haptic fires on the wrist at 0 and a warning at T-10s.
7. Watch out of range then back → watch reconciles to phone state.

## Open questions

- ✅ RESOLVED 2026-06-10 → watchOS minimum deployment target = **26.0** (personal
  use; owner's Apple Watch Series 8 on watchOS 26.5, no backward compat needed).
- ✅ RESOLVED 2026-06-10 → `nextSet` command dropped as redundant with `skipSet`.
- Include HealthKit workout session (rings/HR) now or as a fast follow? *Recommendation:
  follow-up spec — keep v1 to mirroring + control.*
- Should the watch be able to **start** the day's workout, or join-only? *Recommendation:
  join-only for v1.*
