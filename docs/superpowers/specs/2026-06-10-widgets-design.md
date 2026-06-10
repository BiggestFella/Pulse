# Widgets (WidgetKit) — design (BAK-19)

- **Date:** 2026-06-10
- **Issue:** BAK-19 — Home/Lock-screen widgets (WidgetKit)
- **Status:** Draft (brainstorm) → ⏸ awaiting human approval of this spec
- **Supersedes:** the PARKED `docs/superpowers/specs/2026-05-31-widgets-spec.md` (assumption-heavy draft).
- **Related:** BAK-7 (design system — `Theme`/`Lockup`, already in the extension), BAK-9 (Today projections this mirrors), BAK-24 (Today → RepositoryContainer; once it lands the snapshot auto-upgrades to real data), BAK-20 (Live Activity — separate surface, untouched).

## Context

`PulseWidgets` today contains **only** the Live Activity (`WorkoutLiveActivity`, ActivityKit). There is no static home/lock-screen widget. `Theme`, `Palette`, `Lockup`, and typography are already cross-compiled into the extension (`project.yml`), and the Live Activity shows the pattern for rendering palette-resolved views in a widget target. There is **no App Group** configured yet, and the extension has no data access.

This adds a glanceable **"Today's Workout"** widget that answers "what do I train right now?" outside the app — today's workout, the week-progress strip, and the streak — deep-linking back in. It is timeline-driven (not `@Observable`), reading a small `Codable` snapshot the app writes to a shared App Group; it never touches Supabase.

## Decisions (confirmed 2026-06-10)

1. **Families:** `systemSmall`, `systemMedium`, `systemLarge` (Home Screen) + `accessoryRectangular`, `accessoryCircular` (Lock Screen) — all five in v1.
2. **One widget kind:** a single fixed "Today's Workout" widget (no `AppIntentConfiguration`, no separate Streak widget in v1).
3. **Real data:** the app writes a live `WidgetSnapshot` (built from the Today repository's `TodaySnapshot`) to the App Group on the relevant triggers, and reloads timelines. The widget falls back to a mock sample when no snapshot is present. (Because Today currently runs on the mock repo until BAK-24, the snapshot reflects mock data today and real data automatically once BAK-24 lands — the writer is source-agnostic.)

## Goals

- A single "Today's Workout" widget rendering across all five families from a shared snapshot, in the user's palette, with coherent rest-day and placeholder treatments.
- Tapping deep-links into the app (start today's workout, or the Today tab on a rest day).
- The app keeps the snapshot fresh (launch/foreground, post-workout, schedule change, palette change) and at day boundaries.

## Non-goals (deferred)

- Live Activity / Dynamic Island (BAK-20 — separate, untouched).
- Interactive widget `AppIntent` actions (e.g. "log set" from the widget) — deep-link tap only.
- Widget configuration (`AppIntentConfiguration`) and additional widget kinds (Streak/PR/This-Week).
- Watch / StandBy / desk-mode treatments.
- A periodic (hourly) refresh — v1 refreshes on app writes + a daily midnight boundary only.

## Architecture

```
App (Pulse)                                   Extension (PulseWidgets)
TodayRepository → TodaySnapshot               PulseProvider: TimelineProvider
        │                                          │ reads
        ▼ maps                                     ▼
WidgetSnapshotWriter ──writes──► App Group ──────► WidgetSnapshotStore (read)
   + WidgetCenter.reloadAllTimelines()         (UserDefaults suite, Codable JSON)
                                                   │
                                            TodayWorkoutWidget (5 families) → Theme views
                                                   │ widgetURL
                                            pulse://start-today | pulse://today → AppShell.onOpenURL
```

- **Shared read-model** `WidgetSnapshot` (`Pulse/Core/Widget/WidgetSnapshot.swift`, cross-compiled into both targets): `Codable`, holds `palette`, `generatedAt`, `programLabel?`, `dayLabel?`, `todayWorkoutName?`, `exerciseCount?`, `week: [WeekCellSnapshot]` (7), `streak`, `startRoute`. `nil` workout name = rest/no-workout day. Derived `doneCount`/`plannedCount` computed from `week` (excludes `rest`), matching the Today rule.
- **`WidgetSnapshotStore`** (shared): one place that encodes/decodes the snapshot to the App Group `UserDefaults(suiteName:)`. Reader returns the decoded snapshot, or a **mock sample** when absent/corrupt (incl. a non-7 week array → treated as corrupt).
- **`WidgetSnapshotWriter`** (app target): maps the Today repo's `TodaySnapshot` (+ current `Palette`) → `WidgetSnapshot`, writes via the store, calls `WidgetCenter.shared.reloadAllTimelines()`.
- **`PulseProvider: TimelineProvider`** (extension): `placeholder` → redacted sample; `getSnapshot` → store read w/ fallback; `getTimeline` → a now-entry + a next-midnight entry, policy `.after(nextMidnight)`. The midnight entry re-derives the day treatment so a workout never shows stale into a new day.
- **`TodayWorkoutWidget`** + per-family views (`PulseWidgets/Widgets/`): reuse `Theme`/`Lockup`/week-cell styling. Registered in the existing `PulseWidgetsBundle` alongside the Live Activity.
- **App Group**: `group.au.com.codeheroes.pulse`, added as an entitlement to **both** targets in `project.yml` (regenerate via `xcodegen`). The selected palette also moves to (or is mirrored in) the App Group so the widget can read it (today `Theme` uses `UserDefaults.standard` under key `pulse-pal`).

## UI (per family)

All Home Screen families: `accent` fill; **small highlight text uses `onAccent`, never `accent2`** (enforced design rule) — so the `today`-marker and streak use `onAccent` emphasis on the accent fill, not `accent2`. Clip to the system container (no custom outer radius).

- **`systemSmall`:** Geist-Mono eyebrow `TODAY · <programLabel>`, Oswald exercise-count numeral + `EXERCISES` unit, workout name (Hanken 700, truncating). 
- **`systemMedium`:** small content (left) + 7-cell week strip and `<n>D` streak (right).
- **`systemLarge`:** medium content with the week strip given more room + the day label (`Day 23`) and a larger lockup; same data, no new fields.
- **`accessoryRectangular`:** system-monochrome two lines — `TODAY · <programLabel>` / `<name> · <n> EX` (`.widgetAccentable()` lead). Rest day: `REST DAY` / `Recover.`
- **`accessoryCircular`:** `Gauge` ring of week completion (`doneCount/plannedCount`) with `doneCount` centered; guards `plannedCount == 0` (all-rest) against divide-by-zero (empty ring).
- **Rest day** (`todayWorkoutName == nil`): every family shows a rest treatment (eyebrow `REST DAY`, no numeral, no Start affordance); deep link → `pulse://today`.
- **Placeholder** (`placeholder(in:)`): redacted coherent sample, never blank.
- **Deep links:** Home families wrap in `Link`/`widgetURL` — `pulse://start-today` when a workout is present, `pulse://today` on rest day; accessory families use `widgetURL`. `AppShell.onOpenURL` selects the Today tab and, for `start-today`, invokes the existing start hook.

## Decisions on the draft's open questions

1. Families — **all five** (decision above).
2. Single fixed widget, **no AppIntent config**.
3. Rest-day copy: `REST DAY` / `Recover.`; CTA opens Today only.
4. **Streak 0 → render `0D`** (never hidden — consistent with the Today product decision).
5. Deep-link scheme: `pulse://start-today` and `pulse://today`, resolved in `AppShell.onOpenURL`.
6. App Group: **`group.au.com.codeheroes.pulse`**, shared `UserDefaults` suite (JSON-encoded snapshot).
7. Refresh: app writes + a daily **midnight** boundary entry. No periodic refresh in v1.
8. On `accent` fills, markers/streak use **`onAccent`** (not `accent2`) to satisfy the color rule + contrast.
9. Stale-across-midnight: midnight entry re-derives; if `generatedAt` precedes today and no fresh write, render a neutral "Open Pulse to refresh" treatment rather than a stale workout.
10. Workout-in-progress: the static widget **always shows the today/plan view**; the in-session surface is the Live Activity (out of scope here).

## Palette sharing

`Theme` persists the palette to `UserDefaults.standard` (key `pulse-pal`). For the widget to match, the app also writes the palette into the App Group (the `WidgetSnapshot.palette` field carries it per-write; on a palette change the app re-writes the last snapshot with the new palette and reloads). Accessory families ignore palette (system monochrome).

## Testing & verification

- **Unit (`PulseWidgetsTests`, CI):**
  - `WidgetSnapshot` `Codable` round-trip incl. nil workout/exerciseCount (rest variant).
  - `WidgetSnapshotStore` reader: returns stored snapshot when present; mock sample when absent/corrupt (missing + non-7 week).
  - `doneCount`/`plannedCount` derivation matches Today (`3`/`5` sample; `0`/`0` all-rest).
  - `PulseProvider.placeholder` non-empty; `getTimeline` emits now + next-midnight entries with the expected policy.
  - Rest snapshot → `pulse://today`; workout snapshot → `pulse://start-today`.
- **App-side unit (`PulseTests`):** `WidgetSnapshotWriter` maps a `TodaySnapshot` → correct `WidgetSnapshot` and persists a decodable payload; reload is observed via a test seam (so CI doesn't need WidgetKit). Deep-link URL parsing in `AppShell` maps to the right tab/route.
- **Note on CI:** unit-testable logic (mapping, store, provider entries, URL parsing) is covered in CI on the simulator; pixel rendering of widget families is verified manually (Xcode widget previews / add to Home & Lock Screen), since WidgetKit view snapshotting isn't in the current test infra. This coverage gap is accepted and called out (same stance as the Live Activity tests).

## Acceptance criteria

- A single "Today's Workout" widget is offered in all five families and renders today's workout, week strip, and streak from the shared snapshot in the user's palette.
- Rest day renders the rest treatment (no numeral/Start) in every family; placeholder renders coherent redacted content.
- `accessoryCircular` shows the week-completion gauge and never divides by zero on an all-rest week.
- Tapping a workout-present widget deep-links to start today's workout; a rest-day widget opens the Today tab; `AppShell` resolves both.
- The app writes a fresh snapshot on launch/foreground, after finishing a workout, on schedule change, and on palette change, and reloads timelines; a midnight timeline entry prevents showing a stale workout into a new day.
- App Group is configured on both targets; a missing/corrupt snapshot degrades to the sample, never crashes.
- All colors/spacing/type come from `Theme`; `onAccent` (not `accent2`) on accent fills.
- All existing + new unit tests pass in CI (mock path); the rendering-snapshot gap is documented.

## Sequencing (for the plan)

1. App Group entitlement on both targets (`project.yml`) + shared `WidgetSnapshot` model + `WidgetSnapshotStore` (+ unit tests).
2. App-side `WidgetSnapshotWriter` (map `TodaySnapshot`→`WidgetSnapshot`, persist, reload) + wiring (Today load success, post-workout, palette change, foreground) + tests.
3. `PulseProvider` (placeholder/getSnapshot/getTimeline + midnight policy) + tests.
4. `TodayWorkoutWidget` + the five family views (Theme-tokened) registered in `PulseWidgetsBundle`.
5. Deep-link scheme + `AppShell.onOpenURL` routing (+ URL-parsing tests).
6. Manual verification across families/palettes/appearances; document the rendering-snapshot gap.
