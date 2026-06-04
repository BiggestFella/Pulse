# Supabase data layer — design (BAK-27)

- **Date:** 2026-06-04
- **Issue:** BAK-27 — Wire the real Supabase backend
- **Status:** Approved (brainstorm) → ready for implementation plan
- **Related:** BAK-6 (protocols + schema, Done), BAK-8 (Auth & onboarding, deferred), BAK-24 (retire Today stopgap)

## Context

Every screen of Pulse is built, but the app runs entirely on in-memory mocks. BAK-6
delivered the repository **protocols** (`Pulse/Core/Data/Repositories/`), the SQL
**schema** (`supabase/migrations/0001`, `0002`), Codable domain models, and Supabase
**stubs that throw `.notImplemented`**. This work makes the app talk to a real
Supabase backend so data actually persists.

A fresh Supabase project has been provisioned for this:

- **Project:** `Pulse` (Oceania/Sydney, `ap-southeast-2`)
- **Ref:** `zczhnwiizykozfsdmsga` · URL `https://zczhnwiizykozfsdmsga.supabase.co`
- Repo **linked** (`supabase/config.toml`); migrations `0001`/`0002` **applied** (all 9 tables live).
- **Dev user** created (`dev@pulse.app`, `user_id 7816633c-c06f-476a-a8c5-08323c043d38`).

> Secrets (anon key, dev-user password, DB password, service_role) live **only** in the
> gitignored `Secrets.xcconfig` / Supabase dashboard — never committed. The service_role
> key must never ship in the app.

## Goals

- Implement the 9 `Supabase*Repository` stubs against the live schema.
- App runs against Supabase by default; data persists across launches.
- Every screen (Today, Library, Plan, You, Exercise detail, History, Builders, Stats, PRs)
  works end-to-end against real data for the dev user.

## Non-goals (deferred)

- **Real auth / onboarding** (BAK-8) — a single hardcoded dev user stands in for now.
- **Offline / caching / write queue** — online-first only this round (revisit as a
  follow-up if gym connectivity proves it necessary).
- **Folder persistence** — `FolderRepository` stays in-memory; Library folders already
  use `MockLibraryRepository`. Tracked separately.

## Key decisions

1. **Online-first** — repositories call Supabase directly; failures surface as the
   existing load/error states. No local cache or write queue.
2. **Dedicated dev user** — the app signs in `dev@pulse.app` (email/password from
   Secrets) once at launch; supabase-swift attaches the JWT to every PostgREST call so
   RLS sees `auth.uid()`.
3. **Seed** — global exercise catalog + a starter PPL program + a few sessions for the
   dev user, so read-heavy screens show real data.

## Architecture

- **`SupabaseClientProvider`** — builds one `SupabaseClient` from `Secrets`
  (URL + anon key) at launch.
- **`AuthGateway`** — signs in the dev user once at startup, exposes the session;
  repositories remain auth-unaware (the client auto-attaches the token).
- **`RepositoryContainer`** (`Pulse/App/AppEnvironment.swift`) — real Supabase path
  builds the 9 repositories sharing the one client.
- **Shared decoding** — one configured `JSONDecoder`/`Encoder` (`convertFromSnakeCase`
  + a Postgres `timestamptz` `Date` strategy) handed to the Postgrest client.
- **File structure** — split the single stub file into one file per repository under
  `Pulse/Core/Data/Supabase/`, matching the protocols.

## Per-repository implementation

- **Reads** use PostgREST **embedded selects** for nested graphs, e.g.
  `workouts?select=*,workout_exercises(*,set_specs(*))` → nested JSON decoded straight
  into the nested models (one round-trip). Add `CodingKeys` where embed/column names
  differ from Swift property names.
- **Writes** insert/update with `returning: representation`. Session logging:
  `startSession` → insert `sessions`; `appendSet` → insert `session_sets`;
  `finishSession` → update `ended_at`.
- **Derived** (`StatsRepository`, `PRRepository`) stay **client-side**: fetch the
  dev user's sessions+sets for the range and compute via the existing `WorkoutAnalytics`
  (Epley est-1RM, volume). No DB views.

### Table ↔ model mapping (existing schema)

- `programs` → `Program` (+ `is_active`, see Gaps); `workouts` → `Workout`;
  `workout_exercises` + `set_specs` → `WorkoutExercise`/`SetSpec`;
  `exercises` + `variations` → `Exercise`/`Variation`;
  `sessions` + `session_sets` → `WorkoutSession`/`SessionSet`;
  `plan_entries` → `DayPlan`. Settings: a `user_settings` row (new tiny table or a
  `profiles` field — decided in the plan).

## Config, secrets, seeding

- **`Secrets.xcconfig`** (gitignored): `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
  `DEV_USER_EMAIL`, `DEV_USER_PASSWORD`. Committed **`Secrets.example.xcconfig`**
  template + README note. Wired via `project.yml` → Info.plist → read at runtime.
- **Seed** (`supabase/seed_dev.sql`, applied via the CLI): global catalog + variations
  (the mock's 20 exercises), a starter PPL program, and a few sessions tied to the dev
  `user_id`.

## Wiring & test strategy

- The **app defaults to Supabase** (DEBUG + release).
- **All tests use mocks.** Unit tests inject `InMemory*` directly (unaffected). UI tests
  that currently rely on the DEBUG-mock default (Builders/History/Plan/You) are updated
  to pass `-uiMock`; `RepositoryContainer.useMock` returns `true` whenever `-uiMock` is
  present (even in DEBUG). Net: CI stays green on mocks; the real app runs on Supabase.

## Gaps resolved here

- **`Program.isActive`** → migration `0003` adds `is_active boolean default false` to
  `programs` (one active per user, enforced app-side).
- **Folders** → out of scope; `FolderRepository` stays in-memory.

## Testing & verification

- Unit tests: unchanged, mock-backed, run in CI.
- **Supabase repositories are not CI-tested** — they need network + secrets CI must not
  hold. Verification is: **run the app against the seeded dev project and confirm each
  screen shows real data**, plus an optional *local-only* integration test target that
  hits the dev project. This coverage gap is accepted and called out.

## Sequencing (for the plan)

1. Foundation — add supabase-swift package, `SupabaseClientProvider`, `Secrets`
   plumbing, `AuthGateway` dev sign-in.
2. Read paths + shared decoding + nested hydration (catalog, programs, workouts,
   sessions, schedule).
3. Write paths (session logging, save program/workout, schedule mutations).
4. Migration `0003` (`is_active`) + seed the dev project; verify each screen.
5. Flip `RepositoryContainer` default to Supabase; update tests to `-uiMock`; confirm
   CI green.

## Acceptance criteria

- App launches, signs in the dev user, and loads Today/Library/Plan/You/Stats/PRs/
  History from Supabase with the seeded data visible.
- Logging a workout via the active flow persists a session + sets; it appears in History
  and updates Stats/PRs on next load.
- Creating a workout/program via the Builders persists and appears in the Library.
- `Secrets.xcconfig` is gitignored; no secret keys are committed.
- All existing unit + UI tests stay green (on the mock path, via `-uiMock`).
