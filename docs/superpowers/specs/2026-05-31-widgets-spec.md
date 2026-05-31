# Widgets (WidgetKit) — Spec
**Linear:** BAK-19  |  **Date:** 2026-05-31  |  **Status:** PARKED — needs its own brainstorm (not in the prototype; this draft is derived/assumption-heavy)

## Overview
Home Screen and Lock Screen widgets that surface Pulse's "what do I do right now?" answer outside the app: today's prescribed workout, the current-week progress strip, and the training streak. The widgets live in the `PulseWidgets` extension (WidgetKit) and render from a small, view-ready snapshot shared from the app via an App Group, refreshed on a `TimelineProvider` schedule. Tapping a widget deep-links into the relevant in-app screen (Today, or directly into the active workout via the start hook). This is the static/glanceable widget surface; it is distinct from the **Live Activity / Dynamic Island** real-time workout timer, which is downstream of the active session engine (BAK-14) and specified separately.

## User story
As a lifter, I want a Home Screen and Lock Screen widget that shows today's workout, my week progress, and my streak, so that I can see what I'm training and jump straight into it without opening the app first.

## Acceptance criteria
1. The extension registers a `WidgetBundle` (`PulseWidgetBundle`) exposing at least one `Widget` ("Today's Workout") with supported families: `systemSmall`, `systemMedium` (Home Screen) and `accessoryRectangular` + `accessoryCircular` (Lock Screen). `systemLarge` is optional (see Open questions).
2. `systemSmall` renders: a Geist-Mono eyebrow (`TODAY · <programLabel>`), the workout name (Hanken bold, may truncate to 2 lines), and the exercise count as an Oswald numeral with a small `EXERCISES` unit label — on an `accent`-filled background with `onAccent` text.
3. `systemMedium` renders the small content plus the 7-cell week strip (state-styled per the Today spec: `done`/`today`/`plan`/`rest`) and the streak numeral (`<n>D`, Oswald, `accent2`).
4. `accessoryRectangular` (Lock Screen) renders a compact two-line summary: line 1 `TODAY · <programLabel>`, line 2 `<name> · <exerciseCount> EX` (single tint, no color fills — accessory widgets are rendered monochrome by the system).
5. `accessoryCircular` (Lock Screen) renders the week-progress as a `Gauge`/progress ring showing `doneCount / plannedCount` with the done count in the center.
6. **Rest-day / no workout today:** when there is no scheduled workout, every family renders a rest treatment (e.g. eyebrow `REST DAY`, no exercise numeral, no Start affordance) instead of stale or blank workout content.
7. **No data / not-yet-loaded (placeholder):** the provider's `placeholder(in:)` returns redacted sample content so the widget gallery and first-add render shows a coherent layout, never an empty box.
8. Tapping the Home Screen widget opens the app via a `widgetURL` / `Link` deep link: the workout-present widget links to a "start today's workout" route; the rest-day widget links to the Today tab.
9. The `TimelineProvider` produces entries that refresh at least at the start of each day (midnight local) and when the app writes a new snapshot (post-workout, schedule change, streak change) by calling `WidgetCenter.shared.reloadAllTimelines()`.
10. All colors, spacing, radii, and type come from `Theme` tokens shared with the app; the widget renders in the user's selected palette (Coastal/Mint) read from the shared App Group, with a sensible default when unset.
11. The widget reads its data only from a shared read model (App Group container), never from Supabase or a live repository inside the extension; the app owns writing the snapshot.
12. Widgets render correctly in both light and dark system appearances and in the Lock Screen's monochrome/vibrant rendering mode without illegible contrast.

## Screen / UX behavior
WidgetKit families and layout (no widget mockup exists in the design doc — derived from the Today hero, week strip, and streak; reuses Today's visual language):

- **`systemSmall` (Home Screen):** `accent` fill, radius per system (widgets clip to the system container; do not draw a custom outer radius). Top: Geist-Mono eyebrow `TODAY · <programLabel>` in `onAccent` at ~.85 opacity. Center/bottom: a compact Lockup — Oswald exercise-count numeral (`onAccent`) with the workout name (Hanken 700, `onAccent`, truncating). On accent fills, small highlight text uses `onAccent`, never `accent2` (per the enforced color rule).
- **`systemMedium` (Home Screen):** two-column composition — left column = the small-widget Lockup (eyebrow + numeral + name); right column = the 7-cell week strip (equal cells, Geist-Mono day letters, state styling: `done` = `onAccent`/filled dot, `today` = `accent2` outline, `plan` = faint, `rest` = dashed/dimmed) above or beside the streak numeral `<n>D` (Oswald, `accent2`). Because the medium widget background is `accent`, the `accent2` streak/today markers must be verified for contrast on `accent` — if they fail, fall back to `onAccent` emphasis (see Open questions).
- **`accessoryRectangular` (Lock Screen):** system-tinted monochrome. Two lines using `.widgetAccentable()` for the lead glyph/eyebrow; no token fills (system ignores them). Content: `TODAY · <programLabel>` / `<name> · <n> EX`. Rest day: `REST DAY` / `Recover.`
- **`accessoryCircular` (Lock Screen):** a `Gauge(value:)` progress ring (week completion fraction) with `doneCount` centered. Uses `accent2`-equivalent accent via `.widgetAccentable()` (system renders the tint).
- **Deep linking:** Home Screen families wrap content in `Link`/`widgetURL` with a custom URL scheme (e.g. `pulse://start-today` when a workout is present, `pulse://today` on a rest day). The app shell resolves the URL: `start-today` routes into the active workout start hook (BAK-14); `today` selects the Today tab. Accessory families use `widgetURL` (single tap target).
- **Refresh / freshness:** the visible content is a snapshot; it is acceptable for it to be up to a refresh interval stale. The eyebrow/date reflects the snapshot's intended day; on a new day with no fresh write, the provider's midnight entry must re-evaluate the rest/empty treatment rather than show yesterday's workout.

This feature depends on the Design System (BAK-7) for `Theme` tokens, the Lockup composition, eyebrow/numeral text styles, and the week-cell styling — these must be reachable from the `PulseWidgets` target (shared module / shared files via target membership in `project.yml`). It depends on the data-layer (BAK-6) for the snapshot read-model type and the App-Group write path, and on the active-workout flow (BAK-14) for the start deep-link route.

## Data & state
The extension is driven by a `TimelineProvider` plus a small `Codable` snapshot read from the shared App Group; there is no `@Observable` model inside the widget (WidgetKit is timeline-driven, not Observation-driven). The app side owns a thin writer.

**Shared snapshot (in `Core/`, target-shared with `PulseWidgets`):**
```swift
struct WidgetSnapshot: Codable, Equatable {
    var palette: String                 // "coastal" | "mint"
    var generatedAt: Date
    var programLabel: String?           // "PPL" — nil if no program
    var todayWorkoutName: String?       // nil = rest / no workout today
    var exerciseCount: Int?             // nil on rest day
    var week: [WeekCellSnapshot]        // exactly 7
    var streak: Int
    var startRoute: String              // "pulse://start-today"
}
struct WeekCellSnapshot: Codable, Equatable {
    var dayLetter: String               // "M"
    var state: String                   // "done" | "today" | "plan" | "rest"
}
```

**Timeline entry + provider:**
```swift
struct PulseEntry: TimelineEntry { let date: Date; let snapshot: WidgetSnapshot }

struct PulseProvider: TimelineProvider {
    func placeholder(in: Context) -> PulseEntry           // redacted sample
    func getSnapshot(in:, completion:)                    // reads App Group, falls back to sample
    func getTimeline(in:, completion:)                    // entry now + next-midnight entry; .atEnd policy
}
```

**App-side writer (owned partly by BAK-6 wiring; referenced here):**
- `WidgetSnapshotWriter` (in the app target, `Core/Data` or `Core/Widget`) encodes a `WidgetSnapshot` to the shared App Group container (`UserDefaults(suiteName:)` or a file in the group container) and calls `WidgetCenter.shared.reloadAllTimelines()`.
- The app builds the snapshot from the same repository data the Today tab consumes (today's workout, current week, streak) — so the snapshot mirrors `TodayModel`'s projected state. The widget never calls a repository directly.

**Mock sample data** (mirrors the Today spec / `pulse-app.jsx`, used by `placeholder` and `getSnapshot` fallback):
- `programLabel: "PPL"`, `todayWorkoutName: "Chest & Tris"`, `exerciseCount: 7`, `streak: 27`.
- `week`: `[M done, T done, W done, T today, F plan, S rest, S rest]` → `doneCount 3`, `plannedCount 5`.
- Rest-day sample variant: `todayWorkoutName: nil`, `exerciseCount: nil`, today's cell state `rest`.

`doneCount` / `plannedCount` are derived in the widget views from `week` (same rule as Today: `plannedCount` excludes `rest`).

## Out of scope
- The **Live Activity / Dynamic Island** real-time workout timer (rest countdown ring, current/next set, skip/log intents) — that is the active-flow downstream surface (BAK-14), driven by `ActivityKit` + the session engine's published state, not by this static timeline widget.
- The active workout flow itself and its state machine (BAK-14); this feature only consumes the start deep-link route.
- Real Supabase repositories / persistence and the production snapshot-write trigger plumbing — BAK-6 (this feature renders from the shared snapshot + mock fallback; the writer hook is referenced, not fully wired to live data here).
- Widget configuration / `AppIntentConfiguration` (e.g. letting the user pick which program or stat to show) — fixed content for v1 unless raised in Open questions.
- Interactive widget buttons / `AppIntent` actions (e.g. "log set" from the widget) — deep-link tap only.
- Multiple distinct widgets beyond "Today's Workout" (e.g. a standalone streak widget or PR widget) — Open question.
- Watch / StandBy / desk-mode specific treatments.

## Edge cases
- **No snapshot written yet (fresh install / pre-first-launch):** `getSnapshot`/`getTimeline` fall back to the mock sample (or a neutral "Open Pulse" state — see Open questions) rather than crashing or rendering blank.
- **Rest day / no workout today:** `todayWorkoutName == nil` → rest treatment in every family; the Home Screen deep link points at the Today tab, not the start route.
- **Streak of 0:** render `0D` or hide the streak (Open questions); must not show blank or `nilD`.
- **All-rest week:** `plannedCount == 0` → `accessoryCircular` gauge must avoid divide-by-zero (render 0/0 as an empty/0% ring), and the week strip renders all-dashed.
- **Week array not exactly 7:** treat as corrupt snapshot → fall back to placeholder/sample; never render a malformed strip.
- **Long workout names:** name truncates (small) or wraps to 2 lines (medium) without overflowing the system widget bounds.
- **Theme switch (Coastal ↔ Mint):** palette is read from the snapshot; after the user changes palette in You, the app must re-write the snapshot and reload timelines so the widget re-skins (it will not update live mid-render). Accessory families ignore palette (system monochrome).
- **Stale snapshot across midnight:** the next-midnight timeline entry must re-derive the day's treatment; if `generatedAt` is from a prior day and no fresh write occurred, prefer a neutral/"open to refresh" treatment over showing a stale workout (Open questions on exact behavior).
- **Light vs dark appearance & Lock Screen vibrant tint:** verify `onAccent`/`accent` contrast in both; accessory families must remain legible under system tinting.
- **App Group not configured / entitlement missing:** the read must fail gracefully to placeholder, not crash the extension.

## Open questions
1. Which widget families ship in v1 — is `systemLarge` included, and do we ship Lock Screen accessory widgets at launch or fast-follow?
2. Is there more than one widget kind (e.g. a separate "Streak" or "This Week" widget), or a single configurable "Today's Workout" widget? Should it use `AppIntentConfiguration` to let the user choose the stat shown?
3. Exact rest-day copy and whether the rest widget offers any CTA beyond opening Today.
4. Streak-at-0 behavior in the widget: show `0D` or hide the streak element?
5. Deep-link contract: confirm the URL scheme/host (`pulse://start-today`, `pulse://today`) and how the app shell resolves them into tab selection + the BAK-14 start hook.
6. App Group identifier and storage medium (shared `UserDefaults` suite vs file in the group container) — owned jointly with BAK-6; needs to be fixed before the writer/reader are implemented.
7. Refresh policy specifics: beyond midnight + explicit reloads, do we want a periodic `getTimeline` refresh (e.g. hourly), and what is acceptable staleness?
8. On `accent`-filled medium widget, do `accent2` markers (today outline / streak) have sufficient contrast, or should they fall back to `onAccent`? (The Today spec uses `accent2` on `bg`, not on `accent`.)
9. Stale-across-midnight fallback: show a neutral "Open Pulse to refresh" state, or attempt a best-effort rest/empty treatment from the last snapshot's week data?
10. Does the widget need to reflect "workout in progress" (i.e. defer to the Live Activity) or always show the static today/plan view even mid-session?

## Tests required
**Unit tests — `PulseWidgetsTests`:**
- `WidgetSnapshot` round-trips through `Codable` (encode → decode equals original) including nil `todayWorkoutName`/`exerciseCount` (rest-day variant).
- Snapshot reader returns the decoded snapshot from the shared store when present, and the mock sample fallback when absent/corrupt (missing data, non-7 week array).
- `doneCount`/`plannedCount` derivation from `week` matches the Today rule (`3` and `5` for the sample; `0`/`0` for all-rest).
- `PulseProvider.placeholder` returns coherent redacted sample content; `getTimeline` includes a now-entry and a next-midnight entry with the expected refresh policy.
- Rest-day snapshot maps to the rest deep-link route; workout-present snapshot maps to the start route.

**Acceptance / view tests (map to acceptance criteria; snapshot tests where infra exists):**
- AC2/AC3: small and medium render eyebrow, exercise numeral, name, week strip (7 cells), and streak from sample snapshot.
- AC4/AC5: `accessoryRectangular` two-line summary and `accessoryCircular` gauge render from sample (and all-rest gauge does not divide by zero).
- AC6: rest-day snapshot renders the rest treatment in every family (no Start affordance, no exercise numeral).
- AC7: placeholder renders non-empty.
- AC8: each Home Screen family carries the correct `widgetURL`/`Link` (start vs today) per snapshot state.
- AC10/AC12: rendering in Coastal vs Mint snapshot palette, and in light vs dark / accessory-tint, stays legible (snapshot comparison in both palettes if snapshot infra exists).
- App-side: writing a snapshot via `WidgetSnapshotWriter` persists a decodable payload to the shared store and triggers a timeline reload (reload call observed via a test seam).

## Files that will change
- `PulseWidgets/PulseWidgetBundle.swift` — `@main WidgetBundle` registering the widget(s).
- `PulseWidgets/TodayWorkoutWidget.swift` — the `Widget` declaration, supported families, and `widgetURL`/`Link` deep links.
- `PulseWidgets/PulseProvider.swift` — `TimelineProvider` (placeholder, getSnapshot, getTimeline + refresh policy).
- `PulseWidgets/Views/` — per-family SwiftUI views (`SmallWidgetView`, `MediumWidgetView`, `AccessoryRectangularView`, `AccessoryCircularView`) using shared `Theme`/Lockup/week-cell components.
- `Pulse/Core/Widget/WidgetSnapshot.swift` — shared `Codable` read-model (`WidgetSnapshot`, `WeekCellSnapshot`), target-shared with `PulseWidgets`.
- `Pulse/Core/Widget/WidgetSnapshotWriter.swift` — app-side writer to the App Group + `WidgetCenter` reload (writer hook; live-data wiring owned by BAK-6).
- `Pulse/App/AppShell.swift` — resolve the widget deep-link URLs (`onOpenURL`) into tab selection + the BAK-14 start hook.
- `PulseWidgetsTests/WidgetSnapshotTests.swift`, `PulseWidgetsTests/PulseProviderTests.swift` — unit tests.
- `PulseWidgetsTests/WidgetViewTests.swift` — view/snapshot tests mapping to acceptance criteria.
- `project.yml` — add the `PulseWidgets` app-extension target (if not already present), its App Group entitlement, shared `Theme`/Lockup/snapshot file membership, and the app's App Group entitlement; regenerate via `xcodegen generate` (never hand-edit the `.xcodeproj`).
