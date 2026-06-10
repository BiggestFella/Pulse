# RPE/RIR Per-Set Logging → Fatigue/Deload Signal — Spec

**Date:** 2026-06-10
**Status:** Draft (awaiting approval)
**Sequence:** 4 of 5 (medium — includes a schema migration)

## Problem

Pulse logs reps × weight but captures **no effort metric**, so it can't tell a
grinding top set from an easy one. The *planned* model (`SetSpec`) already carries
`rir: Int`, but the *logged* model (`SessionSet`) does not — so actual effort is
never recorded. Without it there's no basis for fatigue tracking or a deload nudge.

## Goals

- Capture an optional **RIR** (Reps In Reserve) value per logged working set
  during the active session.
- Persist it through the data layer (model + Supabase schema + repositories +
  mocks) and surface it in History / Session Detail and Exercise Detail.
- Compute a simple **fatigue/deload signal** from recent RIR trends and surface a
  gentle suggestion ("Hard week — consider a deload").

## Non-goals

- RPE 1–10 scale (we standardise on **RIR**, consistent with `SetSpec.rir`; RIR
  and RPE are interconvertible, `RPE ≈ 10 − RIR`). A display toggle is a follow-up.
- Auto-generating a deload week / mutating the program (signal is advisory only).
- Backfilling RIR onto historical sets (older sets read as "unset").

## Decision: RIR vs RPE

Use **RIR** for storage and capture, matching the existing `SetSpec.rir` field and
keeping one effort vocabulary across planned and logged sets. (Confirm in Open
Questions — switching to RPE is a rename + scale flip if preferred.)

## Current state (grounded)

- `Pulse/Core/Models/WorkoutModels.swift` — `SetSpec.rir: Int` exists (planned);
  `SessionSet` has `reps`, `weight`, `type` but **no** effort field.
- `Pulse/Features/ActiveWorkout/ActiveSetView.swift` — `model.logSet(reps:weight:)`.
- `supabase/migrations/` — session-set table schema (logged sets) to extend.
- Repositories: `InMemory*`, `Supabase*` session writers/readers + History/Stats.

## Design

### 1. Model

Add `var rir: Int? = nil` to `SessionSet` (optional → older call sites and rows
compile/migrate cleanly; `nil` = "not recorded").

### 2. Persistence

- New migration `supabase/migrations/00NN_session_set_rir.sql`: `ALTER TABLE … ADD
  COLUMN rir smallint NULL` on the logged-set table.
- Map the column in `SupabaseSessionWriter` / readers and the History/Stats reads;
  thread through `InMemory*` mocks. `nil` round-trips as SQL `NULL`.

### 3. Capture UI

- `ActiveSetView`: optional compact **RIR selector** (chips `0 1 2 3 4+`, or a
  small stepper) shown for working/amrap sets, defaulting to unset. Logging without
  touching it stores `nil` — never blocks the existing fast log path.
- `model.logSet(reps:weight:rir:)` (default `nil`) records it.

### 4. Surfacing

- History / Session Detail and Exercise Detail set rows show `@RIR n` when present.

### 5. Fatigue/deload signal (`Pulse/Core/Workout/FatigueSignal.swift`, pure)

```swift
func deloadSuggestion(recentSessions: [WorkoutSession]) -> DeloadSuggestion?
```
Heuristic v1 (advisory only): over the last N (e.g. 6) sessions of a muscle group /
exercise, if average RIR on top working sets trends ≤1 across consecutive sessions
(consistently near-failure) → suggest a deload. Require a minimum count of
RIR-tagged sets before firing; otherwise `nil` (no nagging on sparse data). Surface
as a dismissible banner on Today or Exercise Detail.

## Testing (acceptance criteria)

Unit:
1. `SessionSet` encodes/decodes with and without `rir` (nil round-trips).
2. `deloadSuggestion`: consistently low RIR over N sessions → suggestion; mixed/high
   RIR → `nil`; below minimum tagged-set count → `nil`.

Persistence:
3. Write a session with RIR via the Supabase writer (or local mock), read it back,
   value preserved; legacy rows read as `nil`.

UI/acceptance:
4. RIR selector appears for working sets; logging without it stores `nil`.
5. Logged RIR shows in Session Detail / Exercise Detail.
6. Deload banner appears under the heuristic and is dismissible.

## Open questions

- **RIR vs RPE** for capture/display. *Recommendation: RIR (matches `SetSpec`).*
- Capture per **set** vs once per **exercise** (last set only)? *Recommendation:
  per set, optional.*
- Deload signal scope: per exercise, per muscle group, or whole-session? *Tune
  during implementation; start per muscle group.*
