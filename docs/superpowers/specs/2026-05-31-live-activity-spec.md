# Live Activity (lock screen / Dynamic Island timer) — Spec

**Linear:** BAK-20  |  **Date:** 2026-05-31  |  **Status:** Draft for review

## Overview
While a workout is running, Pulse surfaces the live session on the iOS lock screen and in the Dynamic Island via a WidgetKit + ActivityKit **Live Activity**. It mirrors the active-session engine's two phone-facing phases — `active` (the current set) and `rest` (the countdown) — so a lifter can keep their phone on the bench, glance at rest time remaining, see what's next, and skip rest without unlocking. The Live Activity is a *projection* of engine state, not a second source of truth: the app owns `stepIdx`/`doneSteps`, pushes content updates on every transition, and routes any interaction back into the same `logSet`/`afterRest` engine functions.

This feature depends on the Design System (BAK-7) for tokens/typography, the active-flow session engine (BAK-14) which owns the state this Activity renders, and the data-layer repositories + mocks (BAK-6) for the underlying workout/exercise data. It is UI-first: it renders against the mock-backed session driven by sample workout data, with no Supabase wiring.

## User story
As a lifter mid-workout, I want my rest timer and current/next set to appear on the lock screen and Dynamic Island, and to skip rest from there, so that I can rest with my phone down and not miss the auto-advance without keeping the app foregrounded.

## Acceptance criteria
1. Starting a workout (engine enters `pre`→`active`) **starts a Live Activity**; ending or finishing the workout (`endWorkout`, or reaching `summary`) **ends the Live Activity**.
2. During the `rest` phase, the lock-screen presentation and the Dynamic Island show a **live countdown** that ticks down without app updates, driven by an absolute end timestamp (`Text(timerInterval:)`), and a ring/bar whose progress reflects `remaining / totalRest`.
3. When rest reaches zero, the countdown shows `0:00`/complete and the engine auto-advances; on the next content push the Activity flips to the `active` presentation for the new step.
4. During the `active` phase, the Activity shows the **current set**: exercise display name (respecting session swaps), `SET n/N`, set-type label, target reps and weight, with `failure` sets rendered as `∞` / "To failure" and **no** weight target.
5. The set-type label is defined for **all five** types — `working | warmup | dropset | failure | amrap` — including `dropset` (the in-app active hero map omits it; the Live Activity content must not render an empty label).
6. The expanded Dynamic Island and lock-screen card show an **UP NEXT** preview: the next step's exercise name and reps/weight (or `∞`), matching the in-app RestScreen preview; for supersets it carries the partner `ssLabel`.
7. The Activity content is **re-pushed on every relevant engine transition**: `logSet`, `afterRest` (timer reaches 0, "Skip rest", or Active "Skip"), rest adjustments (`−15 / +15 / +30`), `swapExercise`, and `jumpToExercise`.
8. Adjusting rest (`−15 / +15 / +30`) in the app pushes a **new end timestamp** so the lock-screen countdown stays in sync; the value is clamped to a minimum of `0` and has no upper clamp.
9. The Dynamic Island **compact** presentation shows, at minimum, a phase glyph and the rest time remaining (rest phase) or set position (active phase); the **minimal** (multi-activity) presentation degrades gracefully to a single glyph + value.
10. A "Skip rest" affordance on the Live Activity (during `rest`) routes through the **same `afterRest`** transition as the in-app button (advances without logging); after BAK-14/App Intents wiring it requires no other path. If interactive intents are out of scope for v1 (see Open Questions), tapping the Activity **deep-links into the running workout** at the current phase.
11. All Live Activity surfaces use **Theme tokens only** (no hardcoded hex) and the **correct families** — Oswald for the countdown/set numerals, Geist Mono for uppercase labels/eyebrows, Hanken for names — consistent with the in-app Rest/Active screens.
12. Mid-superset transitions (engine step with `rest:false`) go **active → active with no rest segment**; the Activity must not flash a zero-length or stale timer between paired sets.

## Screen / UX behavior
The Live Activity has three required presentations (lock screen + the three Dynamic Island states). All are projections of `ActivityContentState` published by the session engine.

**Lock screen / banner (rest phase):**
- Eyebrow (Geist Mono, `inkSoft`): e.g. `REST` plus the next set/`ssLabel` ("UP NEXT · 4B").
- Large countdown numeral in **Oswald** (mm:ss) via `Text(timerInterval:)`, with a progress affordance (ring or bar) using **`accent2`** as the progress stroke over an `inkFaint` track — mirroring the in-app rest ring.
- UP NEXT line: next exercise name (Hanken), reps + weight (or `∞`).
- Background uses `bg`/`surface` tokens; card chrome uses `inkFaint` borders. A skip control if intents are in scope (see AC10).

**Lock screen / banner (active phase):**
- Eyebrow: exercise group / `EX n/N` style label; "· SWAPPED" suffix when the step's exercise is a session swap.
- Set-type pill label (`WORKING`/`WARMUP`/`DROP SET`/`AMRAP`/`FAILURE`) — `working` styled as a filled chip (`accent` fill, `onAccent` text), others as outlined (`onAccent` text on transparent with a faint border), matching the active hero pill rules.
- `SET n/N` + target reps numeral (Oswald), weight as a small unit label (Geist Mono). `failure` renders `∞` and hides weight.

**Dynamic Island:**
- **Compact leading/trailing:** phase glyph + the primary value — rest time remaining (`Text(timerInterval:)`) during rest, `SET n/N` (or set count) during active.
- **Expanded:** the rest ring / set lockup on one side, UP NEXT preview on the other, with optional skip action region. Reuse the same token + type treatment as the lock-screen card.
- **Minimal:** single glyph + value (e.g. countdown), per AC9.

**Navigation / lifecycle:** the Activity exists only while a session exists and is in `active` or `rest`. `pre` and `summary` are in-app only; the engine should start the Activity on first `active` and end it when leaving the session. Tapping any surface deep-links into the running workout at its current phase.

## Data & state
This feature does not introduce its own screen `@Observable` model; it is a publisher driven by the session engine (BAK-14). The engine owns the canonical session state (`stepIdx`, `phase`, `doneSteps`, `swaps`, precomputed `STEPS[]`). A thin coordinator (an `@Observable` controller in the active-session feature, or an extension of it) translates engine state into Live Activity content and calls the ActivityKit API.

**`ActivityContentState` (the published projection):** illustrative shape, not an implementation —
```swift
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: Codable { case active, rest }
        var phase: Phase
        var exerciseName: String        // resolves session swaps
        var setIndex: Int               // 1-based
        var totalSets: Int
        var setTypeLabel: String        // defined for all 5 types incl. dropset
        var targetReps: Int?            // nil → render ∞ for failure
        var targetWeight: Double?       // nil/0 → omit for failure / bodyweight
        var ssLabel: String?            // "4A"/"4B" for supersets
        var isMidPair: Bool             // engine step.rest == false within a pair
        var restEndsAt: Date?           // absolute end; nil when phase == .active
        var totalRest: TimeInterval     // resolved rest duration → ring fraction base
        var nextExerciseName: String?   // UP NEXT preview
        var nextReps: Int?
        var nextWeight: Double?
        var nextSsLabel: String?
        var completedSets: Int          // doneSteps.count
        var totalStepCount: Int         // STEPS.count
    }
}
```

**Repository methods called:** none directly. The session engine has already resolved the workout via the repository protocols (e.g. `WorkoutRepository`/`ExerciseRepository` from BAK-6). The coordinator reads engine state only; it must not bypass the engine to fetch data.

**Mock data:** renders against the sample workout that drives the active flow (the prototype's sample program/workout, including the single-set `failure` finisher and at least one superset pair), surfaced through the in-memory mock repositories. `totalRest` derives from the resolved rest duration (currently the engine's fixed 90s, intended to come from You → Preferences "Default rest timer 90s").

**State sync rules:** the coordinator pushes a new `ContentState` on each of: `logSet`, `afterRest`, rest adjust, `swapExercise`, `jumpToExercise`. Rest adjustments recompute `restEndsAt`. Auto-advance at 0 is owned by the engine; the Activity reflects it on the subsequent push.

## Out of scope
- Real Supabase persistence/sync (BAK-6) and persisting in-progress sessions across app kills.
- The in-app Rest/Active/Summary screens themselves (BAK-14) — this spec only mirrors them.
- Local notifications for rest completion (separate from Live Activity countdown).
- Logging actual reps/weight, editing the log, or PR computation.
- Apple Watch / WatchOS complications.
- The "pre" and "summary" phases (no Live Activity presentation for them).
- Multiple concurrent workout Activities.

## Edge cases
- **Mid-superset (no rest):** engine step with `rest:false` → active→active with no rest segment; do not show a zero/stale timer (AC12). `isMidPair`/`ssLabel` drive a "NEXT IN PAIR" framing instead of a rest preview.
- **`failure` set:** `targetReps == nil` → render `∞` / "To failure"; omit weight; no rest target ambiguity (the final step always has `rest:false`).
- **`dropset` label:** must resolve to a non-empty label (the in-app active hero map omits it; this feature must define it). Builder copy uses "Drop set".
- **Final step:** last `STEPS` entry forces `rest:false`; logging it transitions to `summary` → the Activity ends, never showing a trailing rest.
- **Rest adjust clamping:** `−15` cannot drive remaining below `0`; `+15/+30` have no upper clamp.
- **Rest reaches 0 while phone locked:** the WidgetKit timer must show `0:00`/complete on its own; the phase flip to `active` only appears when the app pushes the next state (app may be backgrounded — accept the latency, see Open Questions).
- **Swap/jump mid-session:** current exercise changes without a log/rest event → must still re-push content (AC7).
- **Theme switching:** changing Coastal/Mint mid-session must re-skin the Live Activity to the active theme's tokens; if a token snapshot is captured at Activity start, a theme change must trigger a re-push (see Open Questions on how WidgetKit reads the theme).
- **Activity request denied / unsupported device:** if the user has Live Activities disabled or the device lacks Dynamic Island, the workout must run unaffected in-app (graceful no-op).

## Open questions
1. **Interactive intents vs deep-link only for v1:** does the Live Activity "Skip rest" use an App Intent (button on the Activity) routing into `afterRest`, or is v1 limited to deep-linking into the app? AC10 covers both; the design doc does not specify Live Activity controls.
2. **Theme propagation to the widget extension:** how does the `PulseWidgets` extension read the current Coastal/Mint selection — shared `@AppStorage`/App Group, or a token snapshot embedded in `ContentState`? The design doc only specifies in-app theme switching.
3. **Resolved rest duration source:** is `totalRest` the You → Preferences "Default rest timer 90s" value, or per-exercise? The engine currently hardcodes 90s; the design notes 90s as the intended default but does not confirm per-exercise overrides.
4. **Active-phase staleness:** during a long `active` phase the Activity shows a static set with no countdown; is that acceptable, or should it show elapsed-set or total-session elapsed time? Not specified.
5. **Background-update latency at rest-zero:** the phase flip to `active` after auto-advance depends on an app push while backgrounded. Is a small visible lag acceptable, or must we schedule the end-state push in advance?
6. **Set-type label for `dropset` in the Live Activity:** confirm the exact uppercase string ("DROP SET"? "DROPSET"?) since the active hero map omits it; the builder uses "Drop set".
7. **`onAccent` vs `accent2` on set-type pill:** the design rule says small highlight text on an accent-filled card uses `onAccent`, not `accent2`; confirm this applies identically on the Live Activity's set-type pill.

## Tests required
**Unit tests (coordinator / content mapping — `@Observable` engine projection):**
- `ContentState` mapping for an `active` working set: correct name, `SET n/N`, label `WORKING`, reps, weight.
- `failure` set maps to `targetReps == nil` (renders `∞`) and `targetWeight` omitted.
- `dropset` set maps to a non-empty `setTypeLabel`.
- `rest` phase produces a `restEndsAt` consistent with `totalRest` and an unelapsed `now`; ring fraction = `remaining / totalRest`.
- Rest adjust `−15` clamps remaining at `0`; `+30` increases `restEndsAt` with no upper clamp; both push new state.
- Superset round order A1→B1→A2→B2: mid-pair step (`rest:false`) maps `isMidPair == true` and emits **no** rest segment; UP NEXT carries partner `ssLabel`.
- `swapExercise` and `jumpToExercise` each trigger a content re-push with the updated `exerciseName`/`stepIdx`.
- Lifecycle: first `active` requests an Activity; `endWorkout` and reaching `summary` end it; `pre`/`summary` produce no Activity content.
- `completedSets`/`totalStepCount` equal `doneSteps.count`/`STEPS.count`.

**Acceptance / UI tests (map to acceptance criteria):**
- Start→active starts Activity; finish/end ends it (AC1).
- Rest countdown renders and decreases via timer interval; ring reflects fraction (AC2); flips to active after zero (AC3).
- Active presentation shows current set fields incl. `failure` `∞`/no-weight (AC4, AC5).
- UP NEXT preview matches RestScreen preview, incl. superset `ssLabel` (AC6).
- Re-push on log/rest-adjust/swap/jump (AC7, AC8).
- Dynamic Island compact + minimal degrade correctly (AC9).
- Skip rest from Activity (or deep-link) reaches `afterRest`/foreground at current phase (AC10).
- Snapshot/visual tests assert token + font usage on each surface (AC11).
- Mid-superset active→active shows no stale timer (AC12).

## Files that will change
- `Pulse/Features/ActiveWorkout/WorkoutLiveActivityController.swift` — `@Observable` coordinator that projects session-engine state into `ContentState` and drives ActivityKit lifecycle (new; lives alongside the active-flow feature from BAK-14).
- `Pulse/Core/Workout/WorkoutActivityAttributes.swift` — shared `ActivityAttributes` + `ContentState` (shared between app and widget targets).
- `Pulse/Core/Workout/SetTypeLabel.swift` — shared set-type → uppercase label map covering all five types incl. `dropset` (or extend the existing engine label source so app + widget share one definition).
- `PulseWidgets/WorkoutLiveActivity.swift` — the `ActivityConfiguration`: lock-screen view + Dynamic Island (compact/expanded/minimal), built on Theme tokens.
- `PulseWidgets/WorkoutLiveActivityViews.swift` — shared SwiftUI subviews (rest ring, set lockup, UP NEXT card) used by the lock screen and expanded Island.
- `project.yml` — register the `WorkoutActivityAttributes`/`SetTypeLabel`/shared views in both the app and `PulseWidgets` targets; add `NSSupportsLiveActivities` to the app Info plist settings. (Edit `project.yml`, then `xcodegen generate`; never hand-edit the `.xcodeproj`.)
- `PulseTests/WorkoutLiveActivityControllerTests.swift` — unit tests for the content mapping/lifecycle above.
- `PulseUITests/WorkoutLiveActivityTests.swift` — acceptance/UI tests mapping to the acceptance criteria.
- `docs/superpowers/specs/2026-05-31-live-activity-spec.md` — this spec (new).
