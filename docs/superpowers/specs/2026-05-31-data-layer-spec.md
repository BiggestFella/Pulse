# Data layer: repository protocols, mock data, Supabase mapping — Spec

**Linear:** BAK-6  |  **Date:** 2026-05-31  |  **Status:** Draft for review

## Overview
This feature is the data contract for the entire app: a set of async/throwing **repository protocols** that own all data access (per CLAUDE.md, views and `@Observable` models never touch Supabase directly), an **in-memory mock implementation** of each protocol seeded from one coherent **sample dataset**, and a shared **analytics helper** that computes derived values (volume, PRs, streak) so no screen recomputes them. It is the cornerstone of the UI-first build strategy: every screen feature (Today, Library, Plan, Stats, PRs, History, Exercise Detail, Builders, active flow) binds to these protocols and renders against the mocks, with real Supabase wiring deferred and slotted in behind the same contract. This spec also reconciles three sources of truth — the Swift domain structs in `Core/Models/WorkoutModels.swift`, the SQL schema in `supabase/migrations/0001_initial_schema.sql`, and the design doc data model — and lands the model changes and a new scheduling table needed before real persistence is possible.

## User story
As a Pulse engineer (and, transitively, as a lifter using the app), I want every screen to read and write workout data through stable repository protocols backed by realistic in-memory mock data, so that I can build, preview, and test the full UI — Builder save appearing in Library, a logged set appearing in History, derived stats and PRs looking real — before any Supabase or RLS work exists, and then swap in the live backend with zero view-code changes.

## Acceptance criteria
1. Eight repository protocols exist in `Pulse/Core/Data/Repositories/` — `ProgramRepository`, `WorkoutRepository`, `ExerciseRepository`, `SessionRepository`, `ScheduleRepository`, `StatsRepository`, `PRRepository` — with all methods `async throws` and typed in terms of the `Core/Models` domain structs (no Supabase types leak into the protocol surface).
2. A single `enum SampleData` exposes one internally consistent world via `static let` graphs: a "Push / Pull / Legs" `Program` (6 weeks, 3 workouts pinned to weekdays 1 / 3 / 5), an exercise catalog of ~18–24 `Exercise`s grouped by muscle with 1–3 `Variation`s each (at least one single-variation exercise to exercise the "switcher hidden when ≤1" rule and a `defaultVariationID` on each), ~8–12 `WorkoutSession`s across the last ~30 days, and a month of schedule entries. All ids referenced across graphs resolve (a session's `workoutID` points at a real workout, a `SessionSet.exerciseID` at a real exercise, etc.).
3. An in-memory implementation of each protocol (`InMemory*Repository`) is seeded from `SampleData` and implements the full protocol so CRUD round-trips persist within the running app instance: a `saveWorkout` then `fetchWorkouts` returns the saved workout; `appendSet` then `fetchSession` returns the appended set; `setPlan` then `plan(for:)` reflects the change; `deleteProgram` removes it from `fetchPrograms`.
4. A composition root (`AppEnvironment` / `RepositoryContainer`) bundles one instance of each repository and is injected into the SwiftUI environment at the app root, so any model resolves its repositories from the environment rather than constructing them.
5. A single flag / build configuration / launch argument (e.g. `-uiMock`) selects mock vs live repositories at the composition root; no view or model code changes when flipping it.
6. `Program`/`Workout` fetches are **hydrated**: `fetchProgram(id:)` and `fetchWorkout(id:)` return their full nested graph (workouts → workout-exercises → embedded `Exercise` + chosen variation → ordered `SetSpec`s) ready to render the pre-workout "THE PLAN" and to feed the active-session engine.
7. The `SessionSet` Swift struct gains an `exerciseID: Exercise.ID` field (and the analytics/grouping code uses it), so logged sets can be grouped per-exercise for Session Detail, History, and PR derivation.
8. A pure analytics helper (`Core/Data/Analytics` or `Core/Workout`) is the single source for derived math: set volume (`reps × weight`, working/amrap only — warmups excluded), session volume, est. 1RM, PR detection, and streak; `StatsRepository` and `PRRepository` call this helper rather than each reimplementing it.
9. `StatsRepository` returns range-scoped aggregations for all five `StatRange` chips (7D / 30D / 3M / YR / ALL): a volume series, a summary (sessions / new PRs / avg duration / streak), volume-by-muscle, current streak, and per-exercise recent volume history — all computed from the in-memory sessions.
10. `PRRepository` derives personal records (it does not read a stored PRs table): max weight (and/or est. 1RM) per exercise/variation across all logged sets, with an `isNew` flag for records achieved within a given range; the sample dataset contains at least one session that produces a fresh PR so a "NEW" badge can render.
11. A new SQL migration adds a scheduling table (e.g. `scheduled_days` / `plan_entries`: `user_id`, `date`, `workout_id?`, `state ∈ {planned, rest, done}`, optional `session_id`) backing `ScheduleRepository.DayPlan`; the design's Plan tab and the prototype `sched{}` state have no SQL home today.
12. The same SQL migration closes the model/schema gaps: RLS + FK-walking policies on the child tables (`workouts`, `workout_exercises`, `set_specs`, `session_sets`) and a `using(true)` read policy on the catalog (`exercises`, `variations`), plus a `default_variation_id` resolution for exercises (column or documented convention). (Migration only — live wiring may remain stubbed.)
13. `Supabase*Repository` stubs exist for each protocol so the live path compiles; they may throw `notImplemented` or return empty until live wiring lands, but the build configuration that selects them must compile and launch.
14. Loading / empty / error are representable through the async/throwing surface: a repository can throw (models surface an error state), an empty fetch returns `[]` (models surface an empty state), and an in-flight `await` is the loading state — the mocks can be configured to simulate latency and a forced error for testing those states.

## Screen / UX behavior
This feature has **no screens of its own** — it is the data substrate every screen consumes. Grounded in `docs/design/README.md` ("State Management", "Data model (for engineering)") and `pulse-app.jsx`, the protocols map to concrete UI needs as follows (token usage and layout belong to each consuming feature; listed here only to justify the method surface):

- **Today / hero card** → `ProgramRepository.activeProgram()`, `WorkoutRepository.todaysWorkout(on:)`, `StatsRepository.currentStreak()`.
- **Library (RECENT, Routines, Exercises)** → `WorkoutRepository.fetchWorkouts()`, `ProgramRepository.fetchPrograms()`, `ExerciseRepository.fetchCatalog()` / `fetchExercises(muscleGroup:)`.
- **Pre-workout "THE PLAN" + active flow** → `WorkoutRepository.fetchWorkout(id:)` (hydrated) feeds the session engine (BAK-14); logging a set calls `SessionRepository.appendSet(_:to:)`; finishing calls `finishSession(id:endedAt:)`. The active-session flattening (`STEPS[]`, `doneSteps[]`, `swaps{}` from README "State Management") is engine state in `Core/Workout`, **not** a repository concern — swaps/variation overrides apply to the session only and never mutate the saved workout.
- **Swap sheet** → `ExerciseRepository.alternatives(for:)` (same muscle group).
- **Exercise Detail** → `ExerciseRepository.fetchExercise(id:)`, `PRRepository.personalBest(forExercise:)`, `StatsRepository.exerciseVolumeHistory(_:lastN:)` (the 4-bar chart), `SessionRepository.lastSessions(forExercise:limit:)` (the "LAST 4" history sheet).
- **Plan calendar + agenda** → `ScheduleRepository.plan(for:)`, `upcoming(from:days:)`, `setPlan(_:on:)` (the Schedule sheet; `nil` clears a day).
- **Stats tab** → `StatsRepository.volumeSeries(range:)`, `summary(range:)`, `volumeByMuscle(range:)`.
- **PRs grid** → `PRRepository.allPRs()`, `prs(muscleGroup:)`, `newPRs(in:)`.
- **History + Session Detail** → `SessionRepository.fetchSessions(limit:)`, `fetchSession(id:)` (sets grouped by `exerciseID`).
- **Builders (Workout / Routine)** → `WorkoutRepository.saveWorkout(_:)`, `ProgramRepository.saveProgram(_:)`, `ExerciseRepository.saveExercise(_:)`; saved items appear in Library because the mock persists in its in-memory array.

## Data & state
This feature defines data, it does not own an `@Observable` screen model. Its "state" is the repository contract and the mock-held mutable graphs.

- **Domain types:** the existing `Core/Models/WorkoutModels.swift` structs, amended (criterion 7) so `SessionSet` carries `exerciseID` (and consideration of an explicit `order`; arrays remain authoritative for `SetSpec`/`WorkoutExercise` order, but repos must preserve the SQL `"order"` on round-trip — see Open Questions).
- **New derived value types** (live in `Core/Models`, not the schema): `VolumePoint(label/date, volume)`, `StatsSummary(sessions, newPRs, avgDuration, streak)`, `MuscleVolume(muscleGroup, volume)`, `PersonalRecord(exerciseID, variationID?, weight, reps, achievedAt, isNew)`; supporting enums `StatRange { d7, d30, m3, year, all }` and `DayPlan { workout(Workout.ID), rest, done(WorkoutSession.ID) }`.
- **Mock implementations** hold their seed in a mutable, isolation-safe store (`actor` or `@MainActor`) so concurrent reads/writes during a session are safe; all mocks read from the same `SampleData` graphs so ids are consistent across repos.
- **Composition root** (`AppEnvironment` / `RepositoryContainer`): a value/`@Observable` bundling the eight repos, injected via `.environment`; the mock-vs-live selection happens here (criterion 5). It also powers SwiftUI `#Preview`s and the test fixtures CLAUDE.md requires.
- **Repository protocol surface** (illustrative, not full implementations):
  ```swift
  protocol SessionRepository {
      func startSession(workoutID: Workout.ID, at: Date) async throws -> WorkoutSession
      func appendSet(_ set: SessionSet, to sessionID: WorkoutSession.ID) async throws
      func finishSession(id: WorkoutSession.ID, endedAt: Date) async throws -> WorkoutSession
      func fetchSessions(limit: Int?) async throws -> [WorkoutSession]
      func fetchSession(id: WorkoutSession.ID) async throws -> WorkoutSession?
      func lastSessions(forExercise: Exercise.ID, limit: Int) async throws -> [WorkoutSession]
      func deleteSession(id: WorkoutSession.ID) async throws
  }
  ```
  (Full protocol set per the research digest §2; mutating methods return the persisted entity so server-assigned ids/timestamps round-trip.)

## Out of scope
- **Real Supabase wiring** — network calls, auth/session token plumbing, decoding, conflict handling. Only the `Supabase*Repository` *stubs* and the SQL *migration* ship here; the live implementations land later behind the same protocols.
- **Auth / onboarding** (BAK separate) — the mocks ignore `user_id`; `activeProgram()` returns the sample program with no auth gate.
- **The Design System** (BAK-7) and **every screen feature** — they *consume* this layer; this spec only guarantees the contract and the mock data they bind to.
- **The active-session engine** (BAK-14) — `STEPS[]` / `doneSteps[]` / `swaps{}` flattening, rest-timer logic, and the Live Activity / Widgets that depend on it; this layer only provides the hydrated `Workout` it reads and the `SessionRepository` it writes to.
- **Materializing a `personal_records` table** — PRs are derived in v1 (revisit only if query cost matters).
- **Offline sync / caching / migration of existing user data** — there is no v1 data to migrate.
- **Search and "+ Tag"** (decorative stubs in the prototype) need no repository method here.

## Edge cases
- **Empty fetches:** a fresh user / filtered query with no matches returns `[]`, not an error — consuming models render an empty state. (The sample dataset is non-empty; mocks should expose a way to start empty for testing.)
- **Thrown errors:** a repository method can throw; models map it to an error state. The mock supports a configurable forced-error mode to test this path.
- **Latency / loading:** the `await` boundary is the loading state; the mock supports an injectable delay so loading UI is testable in previews.
- **Single-variation exercise:** `fetchExercise` returns an exercise with one `Variation`; the Swap/variation switcher hides (rule lives in the consuming view, but the data must support it).
- **`defaultVariationID` resolution:** if unset, fall back to the first/lowest-order variation (and the SQL gap in criterion 12).
- **Warmup sets in volume/PRs:** warmups are excluded from volume and PR derivation (only `working`/`amrap` count) — verified by the analytics helper, not per-screen.
- **Superset ordering:** hydrated workouts preserve `supersetGroup` and exercise order so the engine can produce A1 → B1 → A2 → B2 logging order.
- **Swap is session-scoped:** a swap during a session must not mutate the saved `Workout` returned by `fetchWorkout(id:)`.
- **Clearing a schedule day:** `setPlan(nil, on:)` removes the entry; `plan(for:)` no longer returns that date.
- **Date-boundary / timezone:** streak and "today's workout" depend on calendar-day bucketing; the analytics helper must use a single, explicit calendar (see Open Questions).
- **Theme switching:** not applicable — this layer carries no view tokens.

## Open questions
1. **`SessionSet.order`** — the SQL `session_sets` has an explicit `"order"` but the Swift struct relies on array index. Should the Swift `SessionSet` gain an explicit `order`, or is array index authoritative with repos populating `"order"` on write only? (Criterion 7 adds `exerciseID`; `order` is undecided.)
2. **`default_variation_id` in SQL** — add a real `default_variation_id` column to `exercises`, or adopt a convention (lowest `order` / first variation)? The design says "Exercise has a default Variation" but the schema has no column.
3. **Scheduling table shape** — exact name and columns for the new table (`scheduled_days` vs `plan_entries`), and whether a `done` day stores a `session_id` FK or derives "done" from the existence of a session on that date. The design's Plan tab is unspecified at the persistence level.
4. **Streak definition** — does the streak count *consecutive days with a completed session*, or consecutive *scheduled* days honored (with rest days neither breaking nor extending it)? The design shows a streak number but not its rule.
5. **PR metric** — is a PR max raw weight, max est. 1RM, or max weight-at-reps? Affects `PersonalRecord` and the analytics helper; the design shows PR cards but not the formula. Which 1RM formula (Epley?) if est. 1RM is used.
6. **`StatRange` bucketing** — for the volume series, are 7D/30D bucketed by day and 3M/YR/ALL by week/month? The design shows a hero bar chart but not the bucket granularity per range.
7. **`activeProgram` selection** — with no auth/"followed program" concept yet, how is the single active program chosen (most recent? a flag?)? Mock can hardcode the PPL program, but the live contract is unspecified.
8. **Calendar / timezone** — which calendar and timezone anchor day-bucketing for streak, "today's workout", and schedule (device-local assumed, but unconfirmed).

## Tests required
Unit tests (in `PulseTests`, using `SampleData`):
- **Mock CRUD round-trips** (criterion 3): save→fetch, append-set→fetch-session, set-plan→plan, delete→absent, for each repository.
- **Hydration** (criterion 6): `fetchWorkout(id:)`/`fetchProgram(id:)` return the full nested graph with chosen variation and ordered sets.
- **Sample dataset integrity** (criterion 2): every cross-graph id resolves; at least one single-variation exercise exists; each exercise has a `defaultVariationID`; at least one session yields a fresh PR.
- **Analytics helper** (criterion 8): set/session volume excludes warmups; est. 1RM and PR detection on a known fixture; streak on a hand-built session sequence.
- **Stats aggregations** (criterion 9): `summary`, `volumeSeries`, `volumeByMuscle`, `currentStreak`, `exerciseVolumeHistory` over each `StatRange` against `SampleData` produce expected counts/totals.
- **PR derivation** (criterion 10): `allPRs` / `prs(muscleGroup:)` / `personalBest(forExercise:)` / `newPRs(in:)` correct on the fixture; `isNew` true only within range.
- **Session-set grouping** (criterion 7): logged sets group by `exerciseID` for Session Detail / History.
- **Error & empty & latency modes** (criterion 14): mock forced-error throws; configured-empty returns `[]`; injected delay observed.
- **Swap isolation** (edge case): session-scoped swap does not alter the persisted workout.
- **Composition-root flag** (criterion 5): the container returns mock vs live repos per the flag.

Acceptance/integration tests:
- A model-level test that drives a representative flow against the container — e.g. start session → append sets → finish → appears in `fetchSessions` and produces a `newPRs` entry — proving the contract supports the active flow and History without a live backend.
- A migration smoke test (or documented manual check) that the new SQL applies cleanly and the RLS/catalog/`default_variation_id` changes are present (criteria 11–12).

## Files that will change
- `Pulse/Core/Models/WorkoutModels.swift` — add `exerciseID` to `SessionSet` (and possibly `order`).
- `Pulse/Core/Models/DerivedModels.swift` *(new)* — `VolumePoint`, `StatsSummary`, `MuscleVolume`, `PersonalRecord`, `StatRange`, `DayPlan`.
- `Pulse/Core/Data/Repositories/ProgramRepository.swift` *(new)*
- `Pulse/Core/Data/Repositories/WorkoutRepository.swift` *(new)*
- `Pulse/Core/Data/Repositories/ExerciseRepository.swift` *(new)*
- `Pulse/Core/Data/Repositories/SessionRepository.swift` *(new)*
- `Pulse/Core/Data/Repositories/ScheduleRepository.swift` *(new)*
- `Pulse/Core/Data/Repositories/StatsRepository.swift` *(new)*
- `Pulse/Core/Data/Repositories/PRRepository.swift` *(new)*
- `Pulse/Core/Data/Mock/SampleData.swift` *(new)* — the one coherent dataset.
- `Pulse/Core/Data/Mock/InMemoryProgramRepository.swift` *(new)* and one `InMemory*Repository.swift` per protocol *(new)*.
- `Pulse/Core/Data/Supabase/SupabaseClient.swift` *(new or extended)* and `Supabase*Repository.swift` stubs per protocol *(new)*.
- `Pulse/Core/Data/Analytics/WorkoutAnalytics.swift` *(new)* — pure volume / 1RM / PR / streak math.
- `Pulse/App/AppEnvironment.swift` *(new)* — `RepositoryContainer`, mock-vs-live selection, `.environment` injection at the app root.
- `supabase/migrations/0002_schedule_and_rls.sql` *(new)* — scheduling table, child/catalog RLS policies, `default_variation_id` resolution.
- `PulseTests/Data/SampleDataTests.swift`, `PulseTests/Data/InMemoryRepositoriesTests.swift`, `PulseTests/Data/WorkoutAnalyticsTests.swift`, `PulseTests/Data/StatsRepositoryTests.swift`, `PulseTests/Data/PRRepositoryTests.swift` *(new)*.
- `project.yml` — register new files/folders if XcodeGen groups need it (run `xcodegen generate`; never hand-edit the `.xcodeproj`).
