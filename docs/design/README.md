# Handoff: Pulse Gym — workout tracking app

## Overview
Pulse Gym is a mobile workout-tracking app for solo lifters. A user follows a multi-week **program**, runs a **workout** (logging sets in real time with rests, supersets, swaps, and history lookups), plans sessions on a **calendar**, builds their own workouts/routines/folders in a **library**, and reviews **stats / PRs / history**. The aesthetic is bold and energetic — oversized condensed numerals, high-contrast color "skins", chunky pressable buttons — inspired by the *Not Boring* app family.

## About the Design Files
The files in this bundle are **design references created in HTML/React-via-Babel** — prototypes showing the intended look and behavior. They are **not production code to copy directly**. The task is to **recreate these designs in the target codebase's environment** (e.g. React Native, SwiftUI, Flutter) using that platform's established patterns, navigation, and component libraries. If no codebase exists yet, choose the most appropriate mobile framework and implement there. The prototype is a single-file React app (`pulse-app.jsx`) rendered inside a fake phone frame for presentation — the phone bezel, palette toggle, and "stage" background are presentation scaffolding only and should NOT be reproduced in the real app.

## Fidelity
**High-fidelity.** Final colors, typography, spacing, and interactions are all specified. Recreate the UI faithfully using the target platform's primitives. Exact hex/spacing/type values are in **Design Tokens** below.

---

## Global Structure

- **App shell:** a fixed bottom **tab bar** with 4 tabs — **Today · Library · Plan · You**.
- **Navigation model:** each tab is a root screen. Secondary screens (program detail, exercise detail, stats, PRs, history, session detail, builders) push as a **stack overlay** with a back button. The **active workout** is a full takeover (tab bar hidden) with phases: pre-workout → active set → rest → summary.
- **Bottom sheets / drawers** are used for: set editing, exercise swap, history lookup, jump-to-exercise, exercise picker, create-chooser, workout picker, and day scheduling. All slide up from the bottom, have a dim backdrop (tap to close), a drag handle, a title, and a ✕.
- **Two color themes** ("Coastal" default, "Mint") — in the real app this is a user setting under **You → Theme/Palette**. The prototype's floating top-right palette toggle is scaffolding; the real control lives in You.

---

## Screens / Views

### 1. Today (tab)
- **Purpose:** what to do right now.
- **Layout:** top bar (date eyebrow + ⋯), greeting H1 + streak number top-right. Scroll body: hero "today's workout" accent card → "THIS WEEK" 7-dot week strip → "YESTERDAY" recap row.
- **Hero card:** accent background, "TODAY · PPL · WEEK 4" eyebrow, a **lockup** (giant Oswald numeral `7` with mono label "Day 23" tucked top-right and bold "Chest & Tris." beneath), footer row "7 EXERCISES · ~60M" + dark **Start →** button.
- **Week strip:** 7 cells, done = filled accent + dot, today = accent-2 outline, rest = dashed faint.

### 2. Library (tab)
- **Purpose:** browse/organize all workouts, folders, programs, and the exercise catalog.
- **Layout:** "+" in top bar opens the **Create chooser** sheet. Search field (decorative placeholder), filter chips: **All / Workouts / Folders / Exercises / Programs**.
- **Default (All):** "FOLDERS · 3" list (folder icon + name + sub), then "RECENT" workouts. Folders: Push/Pull/Legs (the active program), Cardio, One-offs.
- **Exercises filter:** catalog grouped by muscle (Chest/Back/Legs/Shoulders/Triceps), each row = name + equipment + variation count, PR badge where relevant. Tap → **Exercise Detail**.

### 3. Exercise Detail (stack)
- Variation pills (All / D-bar / Neutral Grip / Wide…), a **Personal Best** accent card (lockup), a 4-bar **volume chart** (most recent bar in accent-2), and a "LAST 4 SESSIONS" list (date · reps · top weight · volume).

### 4. Plan (tab)
- **Purpose:** schedule sessions.
- **Calendar/Agenda** segmented toggle (defaults Calendar).
- **Calendar:** "May / 2026" header, "THIS MONTH 20/22 · 91%" accent card, Mon-start month grid. Day states: done (accent fill + on-accent dot), today (accent-2 outline), plan (faint fill + accent-2 dot), empty (dashed border). **Tap any day → Schedule sheet** (pick a workout / rest day / clear / replace). Tapping today launches the workout.
- **Agenda:** vertical date-list of upcoming days.

### 5. You (tab)
- Avatar + name, a 3-up mini-stat strip (Streak / Sessions / Volume). "YOUR DATA" nav rows → **Stats**, **Personal records**, **Workout history**. Then Palette swatch picker, Preferences (units, default rest, toggles), Notifications.

### 6. Stats (stack, under You)
- Range chips (7D/30D/3M/YR/ALL), hero "30D VOLUME" accent card with lockup + 12-bar chart, 2×2 sub-stat grid (Sessions/New PRs/Avg Time/Streak), "VOLUME BY MUSCLE" horizontal bar list.

### 7. Personal Records (stack, under You)
- Muscle filter chips, a headline PR accent card, then a 2-col grid of PR cards (NEW badge in accent-2 for fresh ones).

### 8. Workout History (stack, under You)
- Filter chips, sessions grouped "THIS WEEK / LAST WEEK", each row = day/date + name + "time · volume" + optional PR badge. Tap → **Session Detail**.

### 9. Session Detail (stack)
- Read-only past session: date/duration eyebrow, name, VOLUME + PR stat boxes, full per-exercise log list, "Duplicate" / "Repeat workout" buttons.

### 10. Workout (active flow — tab bar hidden)
- **Pre-workout:** title, "Heavy day…" sub, chips (N EXERCISES / ~time / PYRAMID), "THE PLAN" exercise list (supersets shown grouped with SS badge + indented A/B members), big **Start session →**.
- **Active set:** top bar (pause/back ← + "EX n/N" + ⋯). Set-progress segments (done=accent, current=accent-2 outlined, upcoming=faint). Exercise group eyebrow + name + variation chip (tap = swap). **Action chip row: ⇆ Swap · ↻ History · ☰ Jump.** Optional cue line. **Hero accent card** = set-type pill (WORKING/WARMUP/AMRAP/FAILURE) + "SET n/N" + **lockup** (the rep number is the big numeral; failure shows ∞). Bottom-right of card = rep schedule "15 → 12 → 10 → 8" with the **current set's number underlined in accent-2**. Weight & reps steppers (hidden for failure sets). For supersets, a partner peek card (4A/4B) shows below. Bottom: **Skip** + **Log set →** (label becomes "Log → 4B" mid-superset, "Finish workout" on last set).
- **Rest:** countdown ring (accent-2 progress) with mm:ss, −15/+15/+30 chips, "UP NEXT" preview card, **Skip rest →**. Auto-advances at 0.
- **Summary (receipt):** "WORKOUT COMPLETE" eyebrow, title, 2×2 stat boxes (Volume/Time/Sets/PR — PR box accent-bordered), "LOG" list, **Done**.

### Sheets / Drawers
- **Set Editor** (from builder): scrollable per-set list — numbered badge (accent-2 for non-working), reps input, compact RIR −/+ stepper, remove ✕; per-set **type chip row** (Working/Warm-up/Drop set/To failure/AMRAP); "+ Add set"; "Done".
- **Swap:** alternatives by muscle group (equipment labels); current marked NOW; session-only override.
- **History:** per-exercise tabs ("This lift" + related lifts), each with a volume chart + last-4-sessions list.
- **Jump:** all exercises with set-progress + state (done ✓ / current • / upcoming →); tap to jump (lands on first un-logged set).
- **Create chooser:** Workout / Routine / Folder.
- **Exercise Picker:** search + group filter chips (pinned, non-scrolling), multi-select catalog (added = dimmed ✓), "Add N selected".
- **Workout Picker** (routine builder): pinned "Create new workout" card + scrollable "FROM YOUR LIBRARY" list.
- **Schedule** (calendar): assign / replace / clear a day, or set Rest.

### Builders
- **Workout Builder:** editable name, PUSH/PULL/LEGS tag chips, exercise list (compact rows = "N sets · reps · MIXED"). Each row: grip handle, index/SS badge, name, **⛓ link** (superset with row below → grouped accent-2 card badged A/B, with UNLINK), remove ✕. Tap a row → Set Editor drawer. "+ Add exercise" → picker. Cancel / Save.
- **Routine Builder:** editable name, **PROGRAM LENGTH** week stepper (±), "WEEKLY SPLIT" day list (rest days dashed, remove ✕), **"+ Add / create workout"** → Workout Picker, "+ Add rest day". Save routine.
- **Folder:** large colored folder icon preview, editable name, 6-swatch color picker. Create folder.

---

## Interactions & Behavior
- **Press feedback:** primary buttons are pill-shaped with a hard bottom shadow (`0 5px 0 var(--ink)`) + inner highlight/shadow; on `:active` they translate down ~4px and the shadow collapses to `0 1px` (physical "press").
- **Screen transitions:** fade+rise on mount (`@keyframes fadein` — opacity 0→1, translateY 6px→0, .28s `cubic-bezier(.2,.7,.3,1)`).
- **Sheets:** slide up (`translateY 24px→0`, .25s), dim backdrop, close via backdrop / ✕ / Done.
- **Rest timer:** 1s `setTimeout` tick; SVG ring `stroke-dashoffset` transitions linearly; auto-advances to next set at 0.
- **Superset logging order:** A1 → B1 → A2 → B2 (log a set, advance to partner; rest only after the pair). The "Log set" button label reflects the next target.
- **Swap / variation override:** applies to the current session only (does not edit the saved workout).
- **Jump:** out-of-order exercise selection; progress is tracked per set so users return to the first un-logged set.
- **Theme:** switching palette re-skins everything instantly via CSS variables (no transition on `.screen` background — was removed to avoid stale color).

## State Management
- **Theme:** `palette` ("coastal" | "mint"), persisted to `localStorage` ("pulse-pal").
- **Navigation:** active `tab`; an overlay `stack` (array) for pushed screens; `session` object `{ stepIdx, phase }` for the active workout (phase = pre|active|rest|summary).
- **Workout session:** flattened `STEPS[]` (one entry per set, computed from the workout's exercises × sets, with superset/rest metadata), `doneSteps[]` (logged step indices), `swaps{}` (exIdx→alternative).
- **Builders:** local component state — workout items each `{ id, name, group, equip, setList:[{reps, rir, type}], ssGroup }`; routine `{ name, weeks, days[] }`; calendar `sched{}` (day-of-month → `{state, nm}`).
- **Data model (for engineering):** Program → has many Workouts (ordered, per weekday) → has many WorkoutExercises `(Exercise, Variation, ssGroup?)` → has many Sets `{reps, rir, type}`. A logged **Session** references the Workout and stores **SessionSets** (actual reps/weight/type). `set.type ∈ {working, warmup, dropset, failure, amrap}`. Exercise has a default Variation; the variation switcher hides when only one exists.
- **Not yet built (out of v1 scope or to spec server-side):** persistence/sync, auth/onboarding, empty/loading/error states, search, notifications, real exercise media. Decorative stubs: search fields, "+ Tag".

## Design Tokens

**Typography** (Google Fonts)
- Display / body: **Hanken Grotesk** (400/500/600/700/800/900)
- Big numerals / stats: **Oswald** (500/600/700) — condensed; used for all hero numbers, often `letter-spacing:-.02em`, occasionally `transform:scaleY(1.1–1.35)` for poster effect
- Mono / labels / eyebrows: **Geist Mono** (400/500/600) — uppercase, `letter-spacing:.1–.16em`
- H1: Hanken 800, ~28–32px, `line-height:1`, `letter-spacing:-.025em`
- Eyebrow: Geist Mono 500, 9–11px, uppercase, `letter-spacing:.16em`

**Coastal (default theme)**
- `--bg:#06121F` · `--surface:#0E1F33` · `--surface-2:#16314D`
- `--ink:#FFF4D6` · `--ink-soft:rgba(255,244,214,.62)` · `--ink-faint:rgba(255,244,214,.16)`
- `--accent:#26B6F6` · `--accent-deep:#0E5BA8` · `--accent-2:#FF6A1F` · `--on-accent:#06121F`

**Mint (alt theme)**
- `--bg:#0F1814` · `--surface:#1A2620` · `--surface-2:#26332B`
- `--ink:#E1F4E8` · `--ink-soft:rgba(225,244,232,.64)` · `--ink-faint:rgba(225,244,232,.16)`
- `--accent:#00D9B8` · `--accent-deep:#007A6C` · `--accent-2:#FFCC33` · `--on-accent:#0F1814`

**Note on color usage:** `accent` = primary actions/fills; `accent-2` = secondary highlight (current-set marker, streaks, "new"/PR flags, the rest-ring). On an `accent`-filled card, small highlight text must use `on-accent` ink, **not** `accent-2` (low contrast — this was a deliberate fix).

**Radii:** cards 14–20px · pill/buttons 999px · sheets 26px top corners · small chips 8–10px
**Spacing:** 4 / 8 / 10 / 12 / 14 / 18 / 24px rhythm
**Borders:** structural borders `1.5–2px solid var(--ink-faint)`; emphasis `2px solid var(--accent)` or `var(--accent-2)`
**Buttons:** `border:2px solid var(--ink)`, `box-shadow: inset 0 2px 0 rgba(255,255,255,.28), inset 0 -3px 0 rgba(0,0,0,.22), 0 5px 0 var(--ink)`; sizes md 52px / lg 60px / sm 42px tall.
**Grain:** a subtle SVG fractal-noise overlay sits over the bg at low opacity (optional flourish; skip if it complicates the platform).

## Assets
- **Fonts:** Hanken Grotesk, Oswald, Geist Mono (Google Fonts) — substitute platform-appropriate equivalents (condensed font for Oswald is essential to the look).
- **Icons:** inline SVG (bolt, library, calendar, user, chart, chevrons) + text glyphs (→ ← + ✕ ⛓ ⋯). Replace with the codebase's icon set.
- No raster images or logos; exercise media is not included (real app should add thumbnails/illustrations).

## Files (in this bundle)
- `Pulse Gym App.html` — the interactive prototype shell (loads fonts, React, styles, mounts `pulse-app.jsx`). **Primary reference.**
- `pulse-app.jsx` — all screens, sheets, builders, and the workout-session engine. **The source of truth for behavior.**
- `PULSE Design System.html` — the original design-system doc (type scale, color, buttons, principles) across all three original skins.
- `Pulse Gym Wireframes.html` — lo-fi wireframes of every screen + variations explored before this build (context for decisions).

To run the prototype: open `Pulse Gym App.html` in a browser. Use the bottom tabs; the top-right palette toggle switches themes (real app: a setting under You).
