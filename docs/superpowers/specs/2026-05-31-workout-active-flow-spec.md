# Workout Active Flow (pre → set → rest → summary) — Spec

**Linear:** BAK-14  |  **Date:** 2026-05-31  |  **Status:** Draft for review

## Overview
The active workout flow is the heart of Pulse: the full-screen takeover a lifter runs while training. Starting a workout hides the tab bar and walks the user through four phases — **pre** (overview / start), **active** (log each set with steppers, swap, history, jump), **rest** (countdown ring with adjustments), and **summary** (receipt of the session) — driven by a flattened per-set step list and a small session state machine. This feature builds the SwiftUI screens, the `@Observable` session engine that owns the state machine and step computation, and binds them to mock repositories. Real persistence/sync (BAK-6) and the Live Activity / Dynamic Island mirror (downstream) are out of scope here, but the engine must expose the state those features will subscribe to.

## User story
As a lifter, I want to run my planned workout set by set — seeing exactly what to lift, logging each set, resting on a timer, and swapping or jumping exercises as needed — so that I can train without thinking about anything but the next set and get a clear receipt when I finish.

## Acceptance criteria
Each criterion is independently testable.

1. **Start → pre.** From a workout entry point (Today), invoking `startWorkout(_:)` puts the engine into `phase == .pre` with `stepIdx == 0`, `doneSteps` empty, `swaps` empty, and the tab bar hidden.
2. **Pre → active.** Tapping "Begin" / "Start sets" transitions `pre → active` without changing `stepIdx`.
3. **Step computation.** Given a workout, the engine produces one `STEP` per set (per round for supersets), with correct `rest`, `supersetPartnerExIdx`, `exIdx`, `setIdx` metadata, matching the `buildSteps` rules (see Data & state). The last step always has `rest == false`.
4. **Log a non-superset set.** In `active`, logging the current step adds `stepIdx` to `doneSteps` (idempotent — logging twice does not duplicate) and, because non-superset steps carry `rest == true`, transitions to `phase == .rest` while keeping the same `stepIdx`.
5. **Log mid-superset set.** Logging a step whose `rest == false` (a non-final member of a superset round) advances `stepIdx += 1` and stays in `phase == .active` (no rest). The Log button label reads `Log → {partner.ssLabel}` (e.g. "Log → 4B") for that step.
6. **Log final set → summary.** Logging the last step transitions to `phase == .summary`. The Log button on that step reads "Finish workout".
7. **Rest auto-advance.** In `rest`, when the countdown reaches 0 the engine advances to the next step (`stepIdx = min(stepIdx+1, last)`) in `phase == .active`. This is the same `afterRest` transition used by "Skip rest →".
8. **Rest adjustments.** `−15 / +15 / +30` chips change the remaining time by the delta, clamped at a 0 lower bound (no negative); there is no upper clamp. Adjusting does not change phase or `stepIdx`.
9. **Skip a set.** The Active screen "Skip" button advances to the next step (`afterRest` semantics) **without** adding the current step to `doneSteps`.
10. **Jump.** Opening Jump lists every exercise with `done/total` counts and a state glyph (done ✓ / current • / upcoming →). Tapping an exercise lands `phase == .active` on that exercise's **first un-logged set** (falls back to its first step if all logged). Out-of-order jumps are allowed and safe because `doneSteps` is a per-set ledger.
11. **Swap (session-only).** Opening Swap offers alternatives by muscle group with the current marked "NOW". Picking writes `swaps[exIdx]` and the Active screen renders the swapped name, drops the original variation, and tags the eyebrow "· SWAPPED" — **without mutating the workout**. The variation chip opens the same Swap sheet; it is shown only when the exercise has a variation.
12. **Failure set rendering.** A `failure` set renders the hero numeral as `∞` with "To failure / Max reps.", **hides** the weight/reps steppers, and the footer eyebrow reads "BODYWEIGHT" (not "{wt} LBS · {reps} REPS").
13. **Set-type pill.** Every set type — `working | warmup | dropset | failure | amrap` — renders a defined uppercase pill label (no `undefined`/blank). `working` is a solid `accent` fill with `onAccent` text; all other types are transparent with an `inkFaint`/white-40% border and `onAccent`/`ink` text.
14. **Rep-schedule line.** The hero rep-schedule lists only non-warmup sets' rep targets joined by " → ", with the current set's number underlined in `accent2`.
15. **Superset partner peek.** During a superset, a partner peek card appears below the steppers labeled "NEXT IN PAIR" (when the next logged step is the partner) or "PAIRED", previewing the partner's reps/weight for the current round.
16. **Summary receipt.** The summary shows a "WORKOUT COMPLETE · {date}" eyebrow, title, "Day n · program" sub, a 2×2 stat grid (VOLUME / TIME / SETS = `done/total` dimmed / PR in an `accent2`-bordered box), and a LOG list (one row per exercise with summary line and per-exercise volume). Stats are **derived from logged sets / `doneSteps`**, not hardcoded.
17. **End / Done.** "Done" on summary (and back/pause from pre/active) calls `endWorkout`, clearing the session and returning to the Today tab with the tab bar restored.
18. **Phase transition animation.** Each phase change (pre → active → rest → summary) re-triggers the fade+rise mount transition (.28s, +6pt).
19. **Theme parity.** All four phases render correctly in both Coastal and Mint, using only `Theme` tokens; switching palette re-skins instantly with no background flash.

## Screen / UX behavior
Grounded in README §10, Interactions & Behavior, State Management, and `pulse-app.jsx` (ActiveScreen 371–492, RestScreen 659–719, SummaryScreen 724–760, controller 1755–1801).

**Takeover shell.** While a session exists the tab bar is hidden and the active flow replaces the screen (top-level branch in the app shell gated on session state). Phase changes key the `fadein` transition.

**Pre.** Workout overview with a primary "Begin" button (md/lg pressable button: capsule, `2px solid ink`, `accent` fill, `onAccent` text, hard `0 5px 0 ink` drop shadow collapsing to `0 1px` on press). Back/pause icon button calls `endWorkout`.

**Active set.**
- Top bar: pause/back `←` icon button + "EX n/N" (Geist Mono eyebrow) + `⋯`.
- Set-progress segments for the current exercise's sets: done = `accent`, current = `accent2`-outlined, upcoming = faint (`inkFaint`).
- Exercise group eyebrow + name + optional variation chip (`{variation} ⇆`, tap opens Swap). Eyebrow gains "· SWAPPED" when overridden.
- Action chip row: ⇆ Swap · ↻ History · ☰ Jump (open bottom sheets).
- **Hero accent card** (`accent` fill, radius 20): set-type pill + "SET n/N" + lockup (rep number as the giant Oswald numeral; `∞` for failure). Bottom-right = rep schedule "15 → 12 → 10 → 8", current set underlined in `accent2`. Small highlight text on this card uses `onAccent`, never `accent2`.
- Weight & reps steppers below (hidden for `failure`).
- Superset partner peek card (4A/4B style) when applicable.
- Bottom: secondary "Skip" + primary "Log set →" (label becomes "Log → 4B" mid-pair, "Finish workout" on last step).

**Rest.** Countdown ring: SVG circle, `accent2` stroke, `strokeDashoffset = C·(1 − remaining/total)` animating linearly; center `mm:ss` in Oswald + "OF 1:30" eyebrow. `−15 / +15 / +30` chips. "UP NEXT" preview card driven by the next step (exercise name, set number, reps/weight or `∞`, "UP NEXT · {ssLabel}" eyebrow for supersets). "Skip rest →" primary button and a top-bar forward icon both call `afterRest`. Auto-advances at 0.

**Summary (receipt).** "WORKOUT COMPLETE · {date}" eyebrow, title, "Day n · program" sub. 2×2 stat grid — VOLUME (k lbs), TIME (min elapsed), SETS (`done/total`, dimmed), PR (`+n`, `accent2`-bordered box). LOG list: index badge, name, summary line (e.g. "15·12·10·8 @ 140lb"; supersets collapsed to "3 rounds"; failure "To failure · 18"), per-exercise volume, optional PR tag. Buttons: "Edit log" (secondary) + "Done" (primary → `endWorkout`).

**Sheets** (Swap / History / Jump) render only during `phase == .active`, bound to the current step's exercise. Standard bottom-sheet pattern: 26pt top radius, `rgba(0,0,0,.55)` tap-dismiss scrim, 42×4 `inkFaint` handle, Geist Mono eyebrow + Hanken title + ✕ header, .25s slide from +24pt.

## Data & state

**`ActiveWorkoutModel` (`@Observable`)** — owns the state machine and step list. Approximate shape:

```swift
@Observable final class ActiveWorkoutModel {
    enum Phase { case pre, active, rest, summary }
    enum ActiveSheet { case swap, history, jump }

    private(set) var workout: Workout
    private(set) var steps: [WorkoutStep]          // computed once via buildSteps
    private(set) var phase: Phase = .pre
    private(set) var stepIdx: Int = 0
    private(set) var doneSteps: Set<Int> = []
    private(set) var swaps: [Int: Exercise] = [:]  // exIdx → session override
    private(set) var loggedSets: [Int: SessionSet] = [:] // stepIdx → actual logged values
    var activeSheet: ActiveSheet? = nil
    private(set) var startedAt: Date

    // rest state
    private(set) var restTotal: TimeInterval = 90
    private(set) var restEndsAt: Date?             // absolute end (Live-Activity-friendly)

    func startWorkout(_ w: Workout)                // → .pre, resets
    func beginSets()                               // .pre → .active
    func logSet(reps: Int, weight: Double)         // mark done; branch summary/rest/active
    func afterRest()                               // advance + .active (rest done OR skip)
    func skipSet()                                 // advance without logging
    func adjustRest(_ delta: TimeInterval)         // clamp remaining ≥ 0
    func jump(toExerciseIndex: Int)                // first un-logged step
    func swap(exerciseIndex: Int, to: Exercise)    // swaps[exIdx] = alt
    func endWorkout()                              // clear session

    // derived for UI / downstream Live Activity
    var currentStep: WorkoutStep { steps[stepIdx] }
    var nextStep: WorkoutStep? { steps[safe: stepIdx + 1] }
    var displayName(forExercise:): String          // respects swaps
    var summary: SessionSummary                     // volume/time/sets/PR from loggedSets
}
```

**`WorkoutStep`** (new, in `Core/Workout`): `{ exIdx: Int, setIdx: Int, rest: Bool, supersetPartnerExIdx: Int? }`, plus a derived `ssLabel` (e.g. "4A"/"4B"). `buildSteps(_ workout:)` walks exercises in order:
- Non-superset (`supersetGroup == nil`): one step per set, all `rest == true`, no partner.
- Superset group (consecutive members sharing `supersetGroup`): `rounds = max(member.sets.count)`; for each round emit a step per member that still has a set at that index; `rest == true` only on the last member of the round; `supersetPartnerExIdx` points at the other member.
- Final fixup: the very last emitted step's `rest` is forced `false`.
Also build `exerciseSteps: [Int: [Int]]` (exIdx → step indices) for Jump and per-exercise done counts.

**Set-type label map** (in the engine, not the builder): must cover all five `SetType` cases including `dropset` (the prototype's active map omits it — define a label such as "DROP SET" so a dropset set never renders blank).

**Repository protocols (mock-backed, from BAK-6).** This feature consumes:
- A workout/program source to obtain the `Workout` to run (e.g. `WorkoutRepository.workout(id:)`) — for UI-first this is an in-memory mock returning sample data.
- An exercise-alternatives source for Swap (e.g. `ExerciseRepository.alternatives(muscleGroup:)`).
- A history source for the History sheet (e.g. `HistoryRepository.recentSets(exerciseID:)`).
- (Deferred) a session-write method to persist the finished `WorkoutSession`/`SessionSet`s — stubbed against the mock; real wiring is BAK-6.
All access goes through repository protocols; the model never touches Supabase. Sample data drives every screen so the flow is fully runnable without a backend.

**Existing models reused:** `Workout`, `WorkoutExercise`, `Exercise`, `Variation`, `SetSpec`, `SetType`, `SessionSet`, `WorkoutSession` from `Pulse/Core/Models/WorkoutModels.swift`. `SessionSet` already carries actual `reps/weight/type` for the receipt.

## Out of scope
- Real Supabase persistence/sync of the logged session (BAK-6).
- The Live Activity / Dynamic Island lock-screen timer and Widgets (downstream; depend on this engine). This spec only ensures the engine **exposes** the state they need (phase, current/next step context, absolute `restEndsAt`, overall progress).
- The "Edit log" destination/flow on the summary (button present; target screen not specified — see Open questions).
- The History sheet's full content/design beyond surfacing recent sets for the current exercise.
- The Builder, calendar/Plan, stats/PR screens, Today entry-point screen, and Exercise Detail (other features).
- Real PR detection logic and persistence of PRs (the receipt shows a PR count; the source of truth for "is this a PR" is undefined here — see Open questions).
- Loading/empty/error chrome for the workout source: per README line 100 these are explicitly "not yet built" for v1; with mock data the workout is always present.

## Edge cases
- **Single-set / single-exercise workout:** the only step is also the last; logging it goes straight to `summary` (no rest).
- **Superset member with fewer sets than the round count:** that member is skipped in rounds beyond its set count (no step emitted), so partner peek must tolerate a missing partner set (`partner.sets[setIdx] ?? partner.sets.first`).
- **All sets logged then Jump to a fully-done exercise:** lands on that exercise's first step (fallback), phase `.active`; re-logging is idempotent.
- **Skip on the last step:** `afterRest`/skip clamps `stepIdx` at the last index; it does not roll into summary (only `logSet` on the final step does). Confirm intended behavior (see Open questions).
- **Rest adjust below zero:** clamped to 0 → immediate auto-advance on next tick.
- **Failure set:** steppers hidden; `logSet` still records a `SessionSet` (reps from the rep target / `∞` treatment) — define what reps value is stored for a failure set logged (see Open questions).
- **Dropset label:** must not render blank (AC 13).
- **Theme switch mid-session:** all four phases re-skin via tokens with no `.screen` background animation; the rest ring (`accent2`) updates to the new palette instantly.
- **Volume/PR with zero logged sets (e.g. user skipped everything then finished):** summary stats must handle empty `loggedSets` (VOLUME 0, SETS 0/total, PR +0) without crashing.

## Open questions
1. **Default rest duration source.** The prototype hardcodes 90s; README references a You → Preferences "Default rest timer 90s". Should `restTotal` come from a per-workout/per-exercise value, a global preference, or stay a constant 90 for this feature?
2. **PR detection.** The receipt shows a PR count, but the prototype hardcodes it. What defines a PR (per-exercise best weight? best volume? est. 1RM?) and where does the baseline come from — history repository? This is needed to make AC 16's PR box real rather than mocked.
3. **Failure-set logged value.** When a `failure` set is logged with steppers hidden, what `reps`/`weight` are persisted to the `SessionSet`? (Prototype sample uses `reps: null, wt: 0`.)
4. **"Edit log" destination.** Where does the summary's "Edit log" button go — an editable list overlay, back into the active flow, or a separate screen? Not specified in the design.
5. **Skip-on-final-step semantics.** Should "Skip" on the last step finish the workout (go to summary) or be a no-op? `afterRest` clamps and stays active; the design doesn't address skipping the final set.
6. **Weight/reps stepper defaults & increments.** What initial values do the steppers seed from (the planned target?), and what are the increment steps (e.g. ±2.5 lb / ±1 rep) and units (lb vs kg)? Not specified.
7. **History sheet content.** What exactly does the History sheet show (last session's sets for this exercise? all-time? a chart?) — only the entry point is defined.
8. **Pre screen contents.** README §10 doesn't detail the pre-workout overview beyond "start"; what does it list (exercise summary, est. time, warm-up note)?

## Tests required

**Unit tests — `ActiveWorkoutModelTests` (engine / `@Observable` model):**
- `buildSteps`: non-superset workout → one step per set, all `rest == true`, last forced `false`.
- `buildSteps`: superset group → round-interleaved order (A1, B1, A2, B2), `rest` only on last member per round, correct `supersetPartnerExIdx`/`ssLabel`.
- `buildSteps`: superset member with fewer sets is skipped in later rounds.
- `startWorkout` resets phase/stepIdx/doneSteps/swaps and sets `startedAt`.
- `beginSets`: `.pre → .active`, stepIdx unchanged.
- `logSet` idempotency: logging same step twice keeps `doneSteps` size stable.
- `logSet` branching: non-superset → `.rest`; mid-superset (`rest == false`) → `stepIdx+1`, `.active`; final step → `.summary`.
- `afterRest`: advances and clamps at last index; phase `.active`.
- `skipSet`: advances without adding to `doneSteps`.
- `adjustRest`: deltas applied; clamped at 0; no upper clamp.
- `jump`: lands on first un-logged step; falls back to first step when all logged; sets `.active`.
- `swap`: writes `swaps[exIdx]`, does not mutate `workout`; `displayName` reflects override.
- Set-type label map covers all five `SetType` cases (no nil/empty), including `dropset`.
- `summary`: volume/sets derived from `loggedSets`; SETS = `doneSteps.count / steps.count`; empty-log case yields zeros without crash.
- `endWorkout`: clears session state.

**Acceptance / UI tests (map to acceptance criteria):**
- AC 1–2: start hides tab bar, pre→active on Begin.
- AC 4–6: logging shows rest / advances mid-superset / shows summary; Log button label text ("Log → 4B", "Finish workout").
- AC 7–8: rest ring reaches 0 auto-advances; ±15/±30 chips adjust and clamp.
- AC 9: Skip advances without marking done (verify progress segment unchanged).
- AC 10: Jump list glyphs/counts; tap lands on first un-logged set.
- AC 11: Swap shows swapped name + "· SWAPPED" eyebrow; workout unchanged; variation chip opens Swap; chip hidden when no variation.
- AC 12–14: failure hero `∞` + hidden steppers + "BODYWEIGHT"; all five pill labels render; rep-schedule underline in `accent2`.
- AC 16–17: summary stat grid + LOG list populated from logged sets; Done returns to Today with tab bar.
- AC 18–19: phase transitions animate; both Coastal and Mint render (snapshot in both palettes).

## Files that will change
- `Pulse/Core/Workout/WorkoutStep.swift` — `WorkoutStep` struct + `buildSteps(_:)` + `exerciseSteps` map + set-type label map.
- `Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift` — `@Observable` session engine / state machine.
- `Pulse/Features/ActiveWorkout/ActiveWorkoutFlowView.swift` — phase router + fade/rise transition + takeover shell.
- `Pulse/Features/ActiveWorkout/PreWorkoutView.swift` — pre phase.
- `Pulse/Features/ActiveWorkout/ActiveSetView.swift` — active phase (top bar, progress segments, hero lockup card, steppers, partner peek, Skip/Log).
- `Pulse/Features/ActiveWorkout/RestView.swift` — rest phase (ring, adjust chips, UP NEXT, skip).
- `Pulse/Features/ActiveWorkout/SummaryView.swift` — summary receipt.
- `Pulse/Features/ActiveWorkout/Sheets/SwapSheet.swift` — swap/variation override sheet.
- `Pulse/Features/ActiveWorkout/Sheets/JumpSheet.swift` — jump-to-exercise sheet.
- `Pulse/Features/ActiveWorkout/Sheets/HistorySheet.swift` — history sheet.
- `Pulse/Core/Data/` — consume workout/exercise/history repository protocols + mocks (defined by BAK-6); add a session-write stub if not present.
- `Pulse/App/` — app shell branch to enter/exit the takeover and hide the tab bar while a session is active.
- `project.yml` — register new files/folders if XcodeGen globbing requires it; run `xcodegen generate` (never hand-edit `.xcodeproj`).
- `PulseTests/ActiveWorkout/ActiveWorkoutModelTests.swift` — engine unit tests.
- `PulseUITests/ActiveWorkoutFlowTests.swift` — acceptance/UI tests.

## Dependencies
- **BAK-7 (Design System):** `Theme` tokens, pressable `ButtonStyle`, lockup view, bottom-sheet pattern, fonts. All visuals depend on it.
- **BAK-6 (Data layer):** repository protocols + in-memory mocks + sample data this flow binds to. UI-first here assumes the mocks exist.
- **Downstream (Live Activity / Widgets):** depend on this engine. The model must publish phase, current/next step context (name respecting swaps, set n/N, type label incl. dropset, reps/weight, failure `∞` treatment, ssLabel/mid-pair flag), an absolute `restEndsAt` (not a tick count), and overall progress (`doneSteps.count / steps.count`), and must allow content to be re-pushed on swap/jump/log/rest transitions.
