# BAK-24 — Migrate Today tab onto RepositoryContainer (retire TodayRepository stopgap)

**Branch:** `claude/bak-24-today-repository-container`
**Status:** awaiting plan approval (human gate)

## Goal
Retire the standalone `TodayRepository` / `MockTodayRepository` stopgap and its
parallel `TodaySnapshot` sample data. Compose the Today screen from the shared
`RepositoryContainer` repositories so there is a single source of truth (no drift
between the Today numbers and `SampleData`).

## Hard constraints discovered
1. **No local build/test.** This container is Linux with no `swift`/`xcodebuild`;
   the project is iOS + XCUITest. Verification happens on CI only — so changes must
   be careful, and we iterate through CI rather than a local red/green loop.
2. **`SampleData` is anchored to the real current date** (`daysAgo(_:)` uses
   `Date()`), and `InMemoryStatsRepository` filters/streaks against **real `Date()`**
   (`sessionsInRange` line 18). 8+ Data test files depend on this relative anchoring.
   → A global re-anchor to a frozen date is **out of scope** (too much blast radius).
   Determinism for Today is achieved by **injecting `now`** into the Today
   composition, not by freezing `SampleData`.

## Design

### Keep (consumed elsewhere)
`TodaySnapshot`, `TodayWorkoutCard`, `WeekDayCell`, `SessionRecap` — the View and
`WidgetSnapshotWriter` depend on these. `TodaySnapshot` moves out of the deleted
`TodayRepository.swift` into `Features/Today/TodayViewModels.swift`.

### New: `TodaySnapshotComposer` (`Features/Today/TodaySnapshotComposer.swift`)
Pure `@MainActor` struct holding the mapping logic, given the repositories + a
`now: Date`:
- **dateEyebrow** — format `now` ("WED · MAY 28", fixed `en_US_POSIX` locale, uppercase).
- **greetingName** — `UserRepository.currentProfile().displayName`, **first word only**
  (so "Alex Mason" → "Alex"; keeps the greeting tight).
- **streak** — `StatsRepository.currentStreak()`.
- **today** — `WorkoutRepository.todaysWorkout(on: now)`; nil ⇒ rest day. Mapped to
  `TodayWorkoutCard`:
  - `programLabel` ← profile `programLabel` ("PPL").
  - `name`, `exerciseCount` ← workout.
  - `week`/`day` ← **derived deterministically** from completed-session count:
    `day = completedSessions + 1`, `week = ceil(day / workoutsPerWeek)`
    (proposed; see Open decisions).
  - `estimatedMinutes` ← simple heuristic from set count (proposed: `exerciseCount * 9`)
    or a constant; see Open decisions.
- **week** — current Mon–Sun strip: for each weekday, `ScheduleRepository.plan(for:)`
  → `WeekDayCell.State` (`.done` → done, `.workout` → today if that day == today
  else plan, `.rest` → rest). `dayLetter`/`label` from the resolved workout.
- **yesterday** — `SessionRepository.fetchSessions(limit: 1).first` → `SessionRecap`
  via existing helpers (`SessionSummary` duration + `totalVolume`, `SessionPRs` count),
  formatted "71M · 18.7K KG · +1 PR".

### `TodayModel`
Replace `repository: any TodayRepository` with the repositories it needs (programs,
workouts, stats, schedule, sessions, user) + `now: Date = .now` + existing callbacks
(`onStartWorkout`, `onOpenSession`, `onSnapshot`) and the optional `sessionRepo`
(already present for the deload banner — reuse `sessions`). `load()` calls the
composer; phase/empty/error logic unchanged.

### `AppShell` + `RepositoryContainer`
- Build `TodayModel` from `container` repositories.
- Re-express the UI-test variants through the container instead of
  `MockTodayRepository`:
  - `-uiTestRestDay` → inject a `now` on a known rest weekday (e.g. Sunday) so
    `todaysWorkout` returns nil → `.empty` ("Rest day.").
  - `-uiTestError` → add a `forceError` knob to `RepositoryContainer(useMock:)` that
    sets `MockStore.forceError = true`, so the first repo call throws → `.error`.
- Keep widget mirroring inert under `-uiMock` (unchanged).

### Delete
- `Pulse/Core/Data/TodayRepository.swift` (move `TodaySnapshot` first)
- `Pulse/Core/Data/MockTodayRepository.swift`
- `PulseTests/MockTodayRepositoryTests.swift`

## Tests to update (assert SampleData-composed values)
- **`PulseTests/TodayModelTests.swift`** — construct the model from a seeded
  `MockStore` + a **fixed `now`** (a Wednesday). Assert the composed values
  (greeting "Alex", a deterministic streak, today's workout name from SampleData,
  week count 7, yesterday name). Rest-day/error/no-history cases via `now` on a rest
  day / `forceError` / empty store.
- **`PulseTests/TodayThemeTests.swift`** — swap `MockTodayRepository.sample` for the
  same seeded-store construction; assertions (theme-agnostic) unchanged.
- **`PulseTests/TodayViewModelsTests.swift`** — drop assertions on the removed
  `TodaySnapshot.sample*` statics; keep the struct/computed-label tests.
- **`PulseUITests/TodayTabTests.swift`** — make value assertions **structural** where
  the value is now date-dependent: eyebrow matches the weekday·month format; week
  strip has its container + 7 cells; progress label matches `^\d+ OF \d+ DONE$`.
  Keep exact-identifier assertions (`today.hero.name`, `today.hero.start`,
  `today.weekStrip`, `today.yesterday`, `today.retry`) and the rest-day / error flows.
- Update `TodayView` default init + previews to build from a mock container/composer.

## Open decisions (recommended defaults; adjust on review)
1. **Greeting**: first name only ("Alex"). *(Recommended)*
2. **Card week/day**: derive from completed-session count (`day = sessions+1`,
   `week = ceil(day / perWeek)`), giving WEEK 4 for SampleData's 10 sessions.
   Alternative: drop the day counter from the card.
3. **estimatedMinutes**: `exerciseCount * 9` heuristic vs a stored field. No model
   field exists today; heuristic avoids a schema change.

## Verification
- All `PulseTests` Today + Data suites and `PulseUITests/TodayTabTests` green on CI.
- No remaining references to `TodayRepository` / `MockTodayRepository` / removed
  `TodaySnapshot.sample*` statics.
