# Estimated 1RM Surfacing + Calculator — Spec

**Date:** 2026-06-10
**Status:** Draft (awaiting approval)
**Sequence:** 2 of 5 (small — mostly UI; math already exists)

## Problem

Pulse already **computes** estimated one-rep max (Epley) and uses it to rank PRs,
but never **shows the number** to the user. A lifter can't see "your estimated 1RM
on Bench is 102 kg" or quickly answer "if I hit 5 reps at 80 kg, what's my 1RM?"

## Goals

- Show the **estimated 1RM** explicitly on the Personal Records cards and the
  Exercise Detail Personal Best card, clearly labelled as an estimate with the
  formula name.
- Add a lightweight **1RM calculator / what-if**: enter weight + reps → est. 1RM,
  plus a small table of common %-of-1RM working weights (e.g. 90/85/80/75/70%).

## Non-goals

- New 1RM formulas / formula picker (Epley only; matches existing math).
- 1RM-over-time trend chart (candidate follow-up, not this spec).
- Changing how PRs are detected or stored.

## Current state (grounded)

- `Pulse/Core/Data/Analytics/WorkoutAnalytics.swift` — `estimatedOneRepMax(weight:reps:)`
  (Epley) and `bestSet(in:)`. Wrapped by `Pulse/Core/Workout/PRMath.swift`
  (`epley1RM`, `bestEpley`).
- `Pulse/Features/PersonalRecords/PersonalRecordsModel.swift` — `Item.estimatedOneRepMax`
  exists; records **sorted by est-1RM desc** — value is computed but the card UI
  (`PersonalRecordsView`) shows top weight + `×reps`, not the est-1RM number.
- `Pulse/Features/ExerciseDetail/ExerciseDetailModel.swift` / `…View.swift` —
  Personal Best card shows `topWeight` + reps, derived via est-1RM but not shown.

## Design

### 1. Surface the number (reuse existing values)

- **PR cards** (`PersonalRecordsView`): add a small mono eyebrow/line per card,
  e.g. `EST. 1RM · 102 kg` (Geist Mono label per design system). Value already on
  `Item.estimatedOneRepMax` → format with `WeightFormat`. No model change.
- **Exercise Detail PB card** (`personalBestCard`): add `EST. 1RM · NNN kg` under
  the existing lockup. Expose `personalBest.estimatedOneRepMax` on the model's
  PB struct if not already present (compute via `epley1RM` from `topWeight`/reps).

All labels read "EST." and use `onAccent` on accent-filled cards (design rule).

### 2. 1RM calculator (small utility)

- New sheet `OneRepMaxCalculatorSheet` reachable from Personal Records (toolbar
  "1RM" button) and optionally Exercise Detail.
- Inputs: weight stepper (2.5 kg) + reps stepper, reusing the active-flow stepper
  pattern.
- Output: large est-1RM numeral (`epley1RM`) + a %-table (90→70%) of working
  weights, rounded to the nearest 2.5 kg.
- Pure derived view; no persistence.

## Testing (acceptance criteria)

Unit:
1. `epley1RM(weight:reps:)` already covered; add tests for the %-table rounding
   (e.g. 1RM 100 → 90/85/80/75/70 = 90/85/80/75/70 kg; non-round 1RM rounds to 2.5).
2. Calculator model: weight 80, reps 5 → est-1RM == `epley1RM(80,5)`.

UI/acceptance:
3. A PR card displays the `EST. 1RM · <kg>` line for the standout record.
4. Exercise Detail PB card shows the est-1RM line.
5. Calculator sheet opens, updates est-1RM and %-table live as steppers change.

## Open questions

- Show est-1RM on **every** PR card or only the standout? *Recommendation: every
  card (value already computed per item).*
- Surface the calculator from Exercise Detail too, or PR tab only? *Recommendation:
  both entry points, one shared sheet.*
