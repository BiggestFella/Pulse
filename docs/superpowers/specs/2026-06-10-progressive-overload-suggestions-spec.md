# Progressive-Overload Suggestions — Spec

**Date:** 2026-06-10
**Status:** Draft (awaiting approval)
**Sequence:** 3 of 5 (medium)

## Problem

During an active workout, the user has to remember (or look up via the "↻ History"
chip) what they did last time and decide whether to add weight. The
`UserSettings.autoProgressWeight` flag (default `true`) exists but **drives no
logic** — nothing currently suggests a heavier load. Progression is the core of
strength training and Pulse leaves it entirely manual.

## Goals

- For each working set, compute a **suggested weight × reps** from the user's last
  performance of that exercise/variation and surface it in the active set screen.
- Make the suggestion **one tap to accept** (prefill the steppers) and trivial to
  override.
- Gate behaviour on `autoProgressWeight`; when off, fall back to "repeat last time".
- Show a short **rationale** so the suggestion is trustworthy
  (e.g. "Hit all reps last time → +2.5 kg").

## Non-goals

- Periodised/percentage-based programming or RPE-driven autoregulation (RPE/RIR is
  a separate spec; this rule is reps-completion-based for v1).
- Per-exercise custom increment configuration (use a sensible default by movement
  type; see Open Questions).
- Deload detection (lives in the RPE/RIR spec).

## Current state (grounded)

- `Pulse/Features/ActiveWorkout/ActiveSetView.swift` — steppers seed from
  `model.seedReps` / `model.seedWeight` on appear; a `↻ History` chip
  (`active.chip.history`) already exists; `model.logSet(reps:weight:)` records.
- `Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift` — injected `historyRepo`
  (last-session lookups) and `exerciseRepo`; owns the per-set seed values.
- `Pulse/Core/Models/ProfileModels.swift` — `autoProgressWeight: Bool`.
- `SetSpec.reps` is the planned target rep count for the current set.

## Design

### Suggestion engine (`Pulse/Core/Workout/ProgressionSuggestion.swift`)

A pure function — easy to unit test, no I/O:

```swift
struct ProgressionInput {
    let target: SetSpec            // planned reps/type for this set
    let lastSets: [SessionSet]     // same exercise+variation, most recent session
    let increment: Double          // kg step for this movement (default 2.5)
    let autoProgress: Bool
}
struct ProgressionSuggestion {
    let weight: Double
    let reps: Int
    let rationale: String          // shown under the suggestion
}
func suggestProgression(_ input: ProgressionInput) -> ProgressionSuggestion?
```

Rule (v1, double-progression style):
- No history → no suggestion (return `nil`; steppers seed from `SetSpec` as today).
- `autoProgress == false` → suggest **repeat** last weight × last reps,
  rationale "Repeat last session".
- Last time the matching set **met or beat** its target reps → **+1 increment**,
  same target reps, rationale "Hit all reps last time → +<inc> kg".
- Last time the set **missed** target reps → **same weight**, target reps,
  rationale "Missed target last time → hold weight".

`increment` default 2.5 kg; heavier default for lower-body compounds is an Open
Question — keep one default for v1.

### Wiring

- `ActiveWorkoutModel` gains `func progressionSuggestion(forStep:) -> ProgressionSuggestion?`
  that pulls the most recent `SessionSet`s for the step's exercise/variation from
  `historyRepo` and calls `suggestProgression`. It feeds `seedReps`/`seedWeight`
  (so accepting is the default) **and** exposes the rationale for display.
- `ActiveSetView`: add a dismissible **suggestion pill** above the steppers, e.g.
  `SUGGESTED · 62.5 kg × 8` + rationale caption + a "Use" affordance (or pre-seed
  so the steppers already show it and the pill is purely informational). Mono label
  per design system; lives next to the existing `↻ History` chip.

## Testing (acceptance criteria)

Unit (`suggestProgression`, pure):
1. No history → `nil`.
2. Hit target last time, autoProgress on → weight +1 increment, reps == target.
3. Missed target last time → same weight, reps == target.
4. autoProgress off → repeat last weight × last reps.
5. Increment is configurable (passing 5.0 yields +5.0).

Model/integration:
6. `progressionSuggestion(forStep:)` returns +increment after a logged session
   that met targets (via `MockHistoryRepository`).
7. Seed values reflect the suggestion when present, else fall back to `SetSpec`.

UI/acceptance:
8. Active set screen shows the suggestion pill + rationale when a suggestion exists;
   hidden when none.

## Open questions

- ✅ RESOLVED 2026-06-10 → **flat 2.5 kg** increment for every lift in v1.
  Per-movement increments are a follow-up.
- "Pre-seed steppers" vs "explicit Use button"? *Recommendation: pre-seed +
  informational pill (lowest friction).*
- Which set's history defines "last time" for multi-set exercises — match by set
  index, or use the top set? *Recommendation: match by set index, fall back to top
  working set.*
