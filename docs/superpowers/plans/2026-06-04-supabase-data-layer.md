# Supabase Data Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the in-memory mock data layer with real Supabase-backed repositories so Pulse persists data for a stubbed dev user.

**Architecture:** One `SupabaseClient` (built from `Secrets.xcconfig`) signs in a dedicated dev user at launch; supabase-swift auto-attaches the JWT so RLS sees `auth.uid()`. The 9 `Supabase*Repository` types implement the existing protocols using PostgREST queries — nested reads via embedded selects, derived Stats/PRs computed client-side via `WorkoutAnalytics`. The app defaults to Supabase; all tests stay on the in-memory mocks via `-uiMock`.

**Tech Stack:** Swift / SwiftUI, supabase-swift (Supabase, Auth, PostgREST), XcodeGen, Supabase CLI.

---

## Environment (already provisioned)

- Project ref `zczhnwiizykozfsdmsga`, URL `https://zczhnwiizykozfsdmsga.supabase.co` (Sydney). Repo linked; migrations `0001`/`0002` applied.
- Dev user `dev@pulse.app`, `user_id 7816633c-c06f-476a-a8c5-08323c043d38`.
- Anon key, dev password, DB password: in `Secrets.xcconfig` / dashboard — **never commit**.

## File Structure

- Create `Pulse/Core/Data/Supabase/SupabaseClientProvider.swift` — builds the shared client.
- Create `Pulse/Core/Data/Supabase/AuthGateway.swift` — dev sign-in + session.
- Create `Pulse/Core/Data/Supabase/SupabaseDecoding.swift` — shared decoder/encoder.
- Create `Pulse/Core/Data/Supabase/Rows/*.swift` — Codable row DTOs (snake_case) per table.
- Replace `Pulse/Core/Data/Supabase/SupabaseRepositories.swift` with one file per repo:
  `Supabase{Exercise,Program,Workout,Session,Schedule,Stats,PR,User,Settings}Repository.swift`.
- Create `Pulse/Core/Config/AppConfig.swift` — reads Secrets from the bundle.
- Create `Secrets.xcconfig` (gitignored) + `Secrets.example.xcconfig` (committed).
- Create `supabase/migrations/0003_program_is_active.sql`, `supabase/seed_dev.sql`.
- Modify `project.yml` (package + xcconfig), `Pulse/App/AppEnvironment.swift` (Supabase path),
  `Pulse/App/PulseApp.swift` / `AppShell.swift` (sign-in at launch), and the UI tests that rely
  on the DEBUG-mock default.

> **Testing reality:** the network repositories cannot run in CI (no secrets/network). Unit-test the
> pure pieces (decoder, row→model mapping, `AppConfig`); verify the repositories by **running the app
> against the seeded dev project** (Task 20). Use `xcodebuild ... -only-testing:PulseTests test` on
> `platform=iOS Simulator,name=iPhone 17` as the CI-equivalent gate after each code task.

---

## Phase 1 — Foundation

### Task 1: Add supabase-swift package

**Files:** Modify `project.yml`

- [ ] **Step 1: Add the package + dependency**

In `project.yml`, add a top-level `packages:` entry and add the product to the `Pulse` target's `dependencies`:

```yaml
packages:
  Supabase:
    url: https://github.com/supabase/supabase-swift
    from: 2.5.1
targets:
  Pulse:
    dependencies:
      - package: Supabase
        product: Supabase
```

- [ ] **Step 2: Regenerate + resolve**

Run: `xcodegen generate && xcodebuild -project Pulse.xcodeproj -resolvePackageDependencies`
Expected: package resolves; `Supabase` available to import.

- [ ] **Step 3: Build**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add project.yml && git commit -m "chore(deps): add supabase-swift package [BAK-27]"
```

### Task 2: Secrets plumbing + AppConfig

**Files:** Create `Secrets.example.xcconfig`, `Secrets.xcconfig`, `Pulse/Core/Config/AppConfig.swift`, `PulseTests/Config/AppConfigTests.swift`; Modify `project.yml`

- [ ] **Step 1: Create the committed template** `Secrets.example.xcconfig`

```
// Copy to Secrets.xcconfig (gitignored) and fill in. See docs/superpowers/specs/2026-06-04-supabase-data-layer-design.md
SUPABASE_URL = https:/$()/your-ref.supabase.co
SUPABASE_ANON_KEY = your-anon-key
DEV_USER_EMAIL = dev@pulse.app
DEV_USER_PASSWORD = your-dev-password
```

> Note: `$()` splits the `//` so xcconfig doesn't treat the URL as a comment. Keep that trick in the real file too.

- [ ] **Step 2: Create the real `Secrets.xcconfig`** (gitignored — verify with `git check-ignore Secrets.xcconfig`) with the actual project URL, anon key, and dev creds from the dashboard / this session's notes.

- [ ] **Step 3: Wire xcconfig + Info.plist keys in `project.yml`**

Point the Pulse target's debug/release configs at `Secrets.xcconfig`, and surface the values as Info.plist entries so they're readable at runtime:

```yaml
targets:
  Pulse:
    configFiles:
      Debug: Secrets.xcconfig
      Release: Secrets.xcconfig
    settings:
      base:
        INFOPLIST_KEY_SUPABASE_URL: $(SUPABASE_URL)
        INFOPLIST_KEY_SUPABASE_ANON_KEY: $(SUPABASE_ANON_KEY)
        INFOPLIST_KEY_DEV_USER_EMAIL: $(DEV_USER_EMAIL)
        INFOPLIST_KEY_DEV_USER_PASSWORD: $(DEV_USER_PASSWORD)
```

(If `INFOPLIST_KEY_*` injection proves unreliable for custom keys, fall back to an explicit `Info.plist` with `$(SUPABASE_URL)` substitutions referenced via `INFOPLIST_FILE`.)

- [ ] **Step 4: Write the failing test** `PulseTests/Config/AppConfigTests.swift`

```swift
import XCTest
@testable import Pulse

final class AppConfigTests: XCTestCase {
    func testParsesValuesFromDictionary() throws {
        let cfg = try AppConfig(info: [
            "SUPABASE_URL": "https://x.supabase.co",
            "SUPABASE_ANON_KEY": "anon",
            "DEV_USER_EMAIL": "dev@pulse.app",
            "DEV_USER_PASSWORD": "pw",
        ])
        XCTAssertEqual(cfg.supabaseURL.absoluteString, "https://x.supabase.co")
        XCTAssertEqual(cfg.anonKey, "anon")
        XCTAssertEqual(cfg.devEmail, "dev@pulse.app")
    }

    func testThrowsOnMissingKey() {
        XCTAssertThrowsError(try AppConfig(info: ["SUPABASE_URL": "https://x.supabase.co"]))
    }
}
```

- [ ] **Step 5: Run it (fails — no AppConfig)**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/AppConfigTests test`
Expected: FAIL (cannot find `AppConfig`).

- [ ] **Step 6: Implement** `Pulse/Core/Config/AppConfig.swift`

```swift
import Foundation

struct AppConfig {
    let supabaseURL: URL
    let anonKey: String
    let devEmail: String
    let devPassword: String

    enum ConfigError: Error { case missing(String), badURL(String) }

    init(info: [String: Any]) throws {
        func str(_ k: String) throws -> String {
            guard let v = info[k] as? String, !v.isEmpty else { throw ConfigError.missing(k) }
            return v
        }
        let urlString = try str("SUPABASE_URL")
        guard let url = URL(string: urlString) else { throw ConfigError.badURL(urlString) }
        self.supabaseURL = url
        self.anonKey = try str("SUPABASE_ANON_KEY")
        self.devEmail = try str("DEV_USER_EMAIL")
        self.devPassword = try str("DEV_USER_PASSWORD")
    }

    /// Reads from the main bundle's Info.plist at runtime.
    static func fromBundle(_ bundle: Bundle = .main) throws -> AppConfig {
        try AppConfig(info: bundle.infoDictionary ?? [:])
    }
}
```

- [ ] **Step 7: Run it (passes)** — same command as Step 5. Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add project.yml Secrets.example.xcconfig Pulse/Core/Config/AppConfig.swift PulseTests/Config/AppConfigTests.swift
git commit -m "feat(config): AppConfig + Secrets.xcconfig plumbing [BAK-27]"
```

### Task 3: SupabaseClientProvider

**Files:** Create `Pulse/Core/Data/Supabase/SupabaseClientProvider.swift`; replace the placeholder `SupabaseClientProvider.swift` if one exists.

- [ ] **Step 1: Implement**

```swift
import Foundation
import Supabase

enum SupabaseClientProvider {
    /// Builds the shared client from AppConfig. Call once; share the instance.
    static func make(_ config: AppConfig) -> SupabaseClient {
        SupabaseClient(supabaseURL: config.supabaseURL, supabaseKey: config.anonKey)
    }
}
```

- [ ] **Step 2: Build** (no unit test — thin wrapper)

Run: `xcodebuild ... build` (iPhone 17). Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit** `git add -A && git commit -m "feat(data): SupabaseClientProvider [BAK-27]"`

### Task 4: AuthGateway (dev sign-in)

**Files:** Create `Pulse/Core/Data/Supabase/AuthGateway.swift`

- [ ] **Step 1: Implement**

```swift
import Foundation
import Supabase

/// Signs in the stubbed dev user once at launch so RLS sees auth.uid().
/// Real onboarding (BAK-8) replaces this later.
actor AuthGateway {
    private let client: SupabaseClient
    private let config: AppConfig
    init(client: SupabaseClient, config: AppConfig) { self.client = client; self.config = config }

    /// Idempotent: signs in if there is no current session.
    func ensureSignedIn() async throws {
        if (try? await client.auth.session) != nil { return }
        _ = try await client.auth.signIn(email: config.devEmail, password: config.devPassword)
    }
}
```

- [ ] **Step 2: Build.** Expected: success.

- [ ] **Step 3: Commit** `git commit -am "feat(data): AuthGateway dev sign-in [BAK-27]"`

### Task 5: Shared decoder/encoder

**Files:** Create `Pulse/Core/Data/Supabase/SupabaseDecoding.swift`, `PulseTests/Data/SupabaseDecodingTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Pulse

final class SupabaseDecodingTests: XCTestCase {
    struct Row: Codable, Equatable { let startedAt: Date; let userId: String }

    func testSnakeCaseAndTimestamptzDecode() throws {
        let json = #"{"started_at":"2026-06-04T08:00:00.123456+00:00","user_id":"abc"}"#.data(using: .utf8)!
        let row = try SupabaseDecoding.decoder.decode(Row.self, from: json)
        XCTAssertEqual(row.userId, "abc")
        XCTAssertEqual(row.startedAt.timeIntervalSince1970, 1780560000.123456, accuracy: 0.01)
    }
}
```

- [ ] **Step 2: Run (fails).** `xcodebuild ... -only-testing:PulseTests/SupabaseDecodingTests test`. Expected: FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation

enum SupabaseDecoding {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let date = postgrest.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath,
                debugDescription: "Unparseable timestamptz: \(s)"))
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    /// Postgres timestamptz with fractional seconds + timezone.
    private static let postgrest: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
```

- [ ] **Step 4: Run (passes).** Expected: PASS. (If fractional-seconds parsing fails for some rows, add a fallback formatter without `.withFractionalSeconds`.)

- [ ] **Step 5: Commit** `git add -A && git commit -m "feat(data): shared Supabase decoder/encoder [BAK-27]"`

---

## Phase 2 — Read paths

> Each Supabase repo gets its own file replacing the stub in `SupabaseRepositories.swift`. Delete the
> stub for a repo as you implement its real file. Inject the shared `SupabaseClient` + `userID` provider.

### Task 6: Row DTOs + model mapping (unit-testable)

**Files:** Create `Pulse/Core/Data/Supabase/Rows/Rows.swift`, `PulseTests/Data/RowMappingTests.swift`

The embedded-select JSON shapes don't match the domain models 1:1 (FKs, nesting). Define `Codable` row
DTOs that mirror the table columns + embeds, plus `toModel()` mappers.

- [ ] **Step 1: Write the failing test** — decode an embedded `exercises?select=*,variations(*)` payload into `ExerciseRow` and map to `Exercise`:

```swift
import XCTest
@testable import Pulse

final class RowMappingTests: XCTestCase {
    func testExerciseRowMapsToModel() throws {
        let json = #"""
        {"id":"11111111-1111-1111-1111-111111111111","name":"Bench Press","muscle_group":"Chest",
         "default_variation_id":null,
         "variations":[{"id":"22222222-2222-2222-2222-222222222222","name":"Barbell","equipment":"Barbell"}]}
        """#.data(using: .utf8)!
        let row = try SupabaseDecoding.decoder.decode(ExerciseRow.self, from: json)
        let model = row.toModel()
        XCTAssertEqual(model.name, "Bench Press")
        XCTAssertEqual(model.muscleGroup, "Chest")
        XCTAssertEqual(model.variations.first?.name, "Barbell")
    }
}
```

- [ ] **Step 2: Run (fails).** Expected: FAIL (no `ExerciseRow`).

- [ ] **Step 3: Implement `ExerciseRow`** (and stub the other rows you'll flesh out per repo). Example:

```swift
import Foundation

struct ExerciseRow: Codable {
    let id: UUID
    let name: String
    let muscleGroup: String
    let defaultVariationId: UUID?
    let variations: [VariationRow]?

    func toModel() -> Exercise {
        Exercise(id: id, name: name, muscleGroup: muscleGroup,
                 variations: (variations ?? []).map { $0.toModel() },
                 defaultVariationID: defaultVariationId)
    }
}

struct VariationRow: Codable {
    let id: UUID
    let name: String
    let equipment: String?
    func toModel() -> Variation { Variation(id: id, name: name, equipment: equipment) }
}
```

> Repeat the same Row+toModel pattern for: `WorkoutRow` (embeds `workout_exercises(*,set_specs(*))`),
> `WorkoutExerciseRow`, `SetSpecRow`, `ProgramRow` (embeds `workouts(...)`), `SessionRow`
> (embeds `session_sets(*)`), `SessionSetRow`, `PlanEntryRow`, `UserSettingsRow`. Match each to the
> columns in `supabase/migrations/0001`/`0002` and the structs in `Pulse/Core/Models/`. Verify exact
> property names against `WorkoutModels.swift` before writing each mapper.

- [ ] **Step 4: Run (passes).** Expected: PASS.

- [ ] **Step 5: Commit** `git add -A && git commit -m "feat(data): Supabase row DTOs + model mappers [BAK-27]"`

### Task 7: SupabaseExerciseRepository (pattern-setter)

**Files:** Create `Pulse/Core/Data/Supabase/SupabaseExerciseRepository.swift`; remove the Exercise stub from `SupabaseRepositories.swift`.

- [ ] **Step 1: Implement** the protocol using embedded selects:

```swift
import Foundation
import Supabase

struct SupabaseExerciseRepository: ExerciseRepository {
    let client: SupabaseClient

    func fetchCatalog() async throws -> [Exercise] {
        let rows: [ExerciseRow] = try await client
            .from("exercises").select("*,variations(*)").order("name")
            .execute(decoder: SupabaseDecoding.decoder).value
        return rows.map { $0.toModel() }
    }
    func fetchExercises(muscleGroup: String) async throws -> [Exercise] {
        let rows: [ExerciseRow] = try await client
            .from("exercises").select("*,variations(*)").eq("muscle_group", value: muscleGroup)
            .execute(decoder: SupabaseDecoding.decoder).value
        return rows.map { $0.toModel() }
    }
    func fetchExercise(id: Exercise.ID) async throws -> Exercise? {
        let rows: [ExerciseRow] = try await client
            .from("exercises").select("*,variations(*)").eq("id", value: id.uuidString)
            .execute(decoder: SupabaseDecoding.decoder).value
        return rows.first?.toModel()
    }
    func alternatives(for exercise: Exercise) async throws -> [Exercise] {
        try await fetchExercises(muscleGroup: exercise.muscleGroup).filter { $0.id != exercise.id }
    }
    func saveExercise(_ exercise: Exercise) async throws -> Exercise {
        // catalog is admin-curated for v1; round-trip insert returning representation
        // (implement if Builders need it; otherwise throw .notImplemented with a TODO)
        exercise
    }
}
```

> Confirm the exact `ExerciseRepository` method signatures in
> `Pulse/Core/Data/Repositories/ExerciseRepository.swift` and match them precisely.

- [ ] **Step 2: Build.** Expected: success.

- [ ] **Step 3: Commit** `git add -A && git commit -m "feat(data): SupabaseExerciseRepository [BAK-27]"`

### Task 8: Program + Workout read repositories

**Files:** Create `SupabaseProgramRepository.swift`, `SupabaseWorkoutRepository.swift`.

- [ ] **Step 1: Implement** following Task 7's pattern, with nested embeds:
  - Workouts: `.select("*,workout_exercises(*,set_specs(*))")`, map `WorkoutRow.toModel()`.
  - `todaysWorkout(on:)` → filter `weekday` server-side (`.eq("weekday", value: n)`), return first.
  - Programs: `.select("*,workouts(*,workout_exercises(*,set_specs(*)))")`; `activeProgram()` → `.eq("is_active", value: true)` (column added in Task 16).
  - All user-scoped queries rely on RLS (no explicit user filter needed once signed in).
- [ ] **Step 2: Build.** Expected: success.
- [ ] **Step 3: Commit** `git add -A && git commit -m "feat(data): Supabase program + workout reads [BAK-27]"`

### Task 9: Session + Schedule read repositories

**Files:** Create `SupabaseSessionRepository.swift` (reads), `SupabaseScheduleRepository.swift` (reads).

- [ ] **Step 1: Implement reads:**
  - Sessions: `.from("sessions").select("*,session_sets(*)").order("started_at", ascending: false)`; `fetchSessions(limit:)` applies `.limit(n)` when non-nil; `lastSessions(forExercise:limit:)` filters sessions whose `session_sets.exercise_id` matches (use an inner-join filter `session_sets!inner(exercise_id=eq.<id>)` or fetch+filter client-side).
  - Schedule: `.from("plan_entries").select("*")`; map `state`+`workout_id`/`session_id` → `DayPlan`; `plan(for:)` filters `.eq("date", ...)`; `upcoming(from:days:)` ranges on `date`.
- [ ] **Step 2: Build.** Expected: success.
- [ ] **Step 3: Commit** `git add -A && git commit -m "feat(data): Supabase session + schedule reads [BAK-27]"`

---

## Phase 3 — Write paths + derived + remaining repos

### Task 10: Session writes

**Files:** Extend `SupabaseSessionRepository.swift`.

- [ ] **Step 1: Implement** `startSession` (insert into `sessions`, returning representation → model), `appendSet` (insert into `session_sets`), `finishSession` (update `ended_at`), `deleteSession` (delete by id). Use `SupabaseDecoding.encoder` for inserts; rely on RLS for `user_id` default (set `user_id` server-side via a column default of `auth.uid()` if the schema supports it — otherwise include `user_id` from `AuthGateway`'s session). Verify the `0001` schema's `user_id` default; if none, thread the session user id in.
- [ ] **Step 2: Build.** Expected: success.
- [ ] **Step 3: Commit** `git add -A && git commit -m "feat(data): Supabase session writes [BAK-27]"`

### Task 11: Program/Workout writes + Schedule mutations

**Files:** Extend `SupabaseProgramRepository.swift`, `SupabaseWorkoutRepository.swift`, `SupabaseScheduleRepository.swift`.

- [ ] **Step 1: Implement** `saveProgram`/`deleteProgram`, `saveWorkout`/`deleteWorkout` (upsert parent then children: workout_exercises, set_specs), and `setPlan(_:on:)` (upsert/delete a `plan_entries` row). Saving a workout graph: insert workout → insert its workout_exercises → insert each set_specs, in order; return the hydrated model via a follow-up read.
- [ ] **Step 2: Build.** Expected: success.
- [ ] **Step 3: Commit** `git add -A && git commit -m "feat(data): Supabase program/workout/schedule writes [BAK-27]"`

### Task 12: Settings + User + Stats + PR repositories

**Files:** Create `SupabaseSettingsRepository.swift`, `SupabaseUserRepository.swift`, `SupabaseStatsRepository.swift`, `SupabasePRRepository.swift`.

- [ ] **Step 1: Decide `user_settings` storage** — add a `user_settings` table (single row per user, RLS on `user_id`) in migration `0003` (Task 16) OR store on a `profiles` row. Plan choice: **add `user_settings` to `0003`** (simplest, matches `SettingsRepository.load/save`).
- [ ] **Step 2: Implement:**
  - `SettingsRepository.load/save` → read/upsert the `user_settings` row.
  - `UserRepository.currentProfile()` → derive from the auth session (email → display name) + `profileSummary()` computed from sessions; or a `profiles` row if seeded. For v1, build `UserProfile` from the dev session + a seeded `profiles` row.
  - `StatsRepository` + `PRRepository` → fetch the user's `sessions(*,session_sets(*))` for the range and compute via the existing `WorkoutAnalytics` (mirror the `InMemory*` implementations exactly — reuse their derivation code paths).
- [ ] **Step 3: Build.** Expected: success.
- [ ] **Step 4: Commit** `git add -A && git commit -m "feat(data): Supabase settings/user/stats/PR [BAK-27]"`

---

## Phase 4 — Migration + seed

### Task 13: Migration 0003 (is_active + user_settings)

**Files:** Create `supabase/migrations/0003_program_is_active_and_settings.sql`

- [ ] **Step 1: Write the migration**

```sql
alter table programs add column if not exists is_active boolean not null default false;

create table if not exists user_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  units text not null default 'kg',
  default_rest_seconds int not null default 90,
  auto_progress_weight boolean not null default false,
  sound_on_rest_end boolean not null default true
);
alter table user_settings enable row level security;
create policy "own settings" on user_settings
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

- [ ] **Step 2: Apply** `supabase db push`. Expected: migration applies.
- [ ] **Step 3: Commit** `git add supabase/migrations/0003_program_is_active_and_settings.sql && git commit -m "feat(db): is_active + user_settings (0003) [BAK-27]"`

### Task 14: Seed the dev project

**Files:** Create `supabase/seed_dev.sql`

- [ ] **Step 1: Write the seed** — global exercise catalog + variations (the 20 exercises from `Pulse/Core/Data/Mock/SampleData.swift`), a starter PPL program (`is_active = true`) with workouts/workout_exercises/set_specs, and 3–5 `sessions` + `session_sets` for the dev user. Hardcode `user_id = '7816633c-c06f-476a-a8c5-08323c043d38'` for user-scoped rows; catalog rows are global.

```sql
-- catalog (global)
insert into exercises (id, name, muscle_group) values
  ('...uuid...', 'Bench Press', 'Chest') on conflict do nothing;
-- ... (mirror SampleData) ...
-- dev user program/sessions reference '7816633c-c06f-476a-a8c5-08323c043d38'
```

- [ ] **Step 2: Apply** `supabase db execute --file supabase/seed_dev.sql` (or via the SQL editor). Verify rows exist: `curl .../rest/v1/exercises?limit=1 -H "apikey: <anon>"` returns data.
- [ ] **Step 3: Commit** `git add supabase/seed_dev.sql && git commit -m "feat(db): dev seed data [BAK-27]"`

---

## Phase 5 — Wiring + tests + verification

### Task 15: RepositoryContainer Supabase path + launch sign-in

**Files:** Modify `Pulse/App/AppEnvironment.swift`, `Pulse/App/PulseApp.swift` (and/or `AppShell.swift`).

- [ ] **Step 1: Build the Supabase branch** in `RepositoryContainer.init(useMock:)` — when not mock, build `AppConfig.fromBundle()`, the client, sign in via `AuthGateway.ensureSignedIn()` (await before first use — do this in an async `bootstrap()` the app calls in `.task` at launch), and construct the `Supabase*Repository`s sharing the client.
- [ ] **Step 2: Build + run** the app against the dev project; confirm sign-in succeeds (log the session user id once).
- [ ] **Step 3: Commit** `git add -A && git commit -m "feat(app): wire Supabase repositories + dev sign-in [BAK-27]"`

### Task 16: Flip default to Supabase; keep tests on mocks

**Files:** Modify `Pulse/App/PulseApp.swift` (DEBUG default), `Pulse/App/AppEnvironment.swift` (`useMock` honors `-uiMock` even in DEBUG), and the UI tests that relied on the DEBUG-mock default.

- [ ] **Step 1:** Change DEBUG construction so the app uses Supabase by default, but `RepositoryContainer.useMock(arguments:)` returns `true` whenever `-uiMock` is present (regardless of build config).
- [ ] **Step 2:** Add `app.launchArguments += ["-uiMock"]` to the UI tests that currently rely on the DEBUG default: `BuildersTests`, `HistorySessionDetailUITests`, `PlanTabTests` (still skipped), `YouScreenTests`, `TodayTabTests`, `StatsTests`, `PersonalRecordsUITests`, `LibraryTabTests`, `DesignSystemUITests`, `ActiveWorkoutFlowTests` — any that don't already pass it. (`ExerciseDetailUITests` already passes `-uiMock`.)
- [ ] **Step 3: Run the full unit suite** `xcodebuild ... -only-testing:PulseTests test` (iPhone 17). Expected: `** TEST SUCCEEDED **`, 328 tests.
- [ ] **Step 4: Commit** `git add -A && git commit -m "feat(app): default to Supabase; tests pinned to mock via -uiMock [BAK-27]"`

### Task 17: End-to-end verification against the seeded project

**Files:** none (manual + optional local integration test)

- [ ] **Step 1:** Build + launch the app (no `-uiMock`) on iPhone 17 against the dev project. Walk each screen and confirm **real seeded data** renders: Today (today's workout), Library catalog + program, Plan calendar, Stats, PRs, History. Screenshot each.
- [ ] **Step 2:** Log a workout via the active flow → confirm it persists (re-launch, see it in History; Stats/PRs update).
- [ ] **Step 3:** Create a workout via the Builders → confirm it appears in Library after relaunch.
- [ ] **Step 4 (optional):** Add a `PulseIntegrationTests` target (local-only, not in CI) that signs in the dev user and asserts `fetchCatalog()` is non-empty, gated behind an env flag so CI skips it.
- [ ] **Step 5:** Document results in the PR description; note any repo that failed and fix before opening the PR.

---

## Self-review notes

- **Spec coverage:** client/auth (T3–4), decoding (T5), all 9 repos read+write (T6–12), Secrets+seed (T2,T14), is_active+settings migration (T13), wiring + test pinning (T15–16), verification + coverage-gap acknowledgement (T17). Folders/offline/real-auth explicitly deferred per spec.
- **Testing reality** is honored: pure pieces are TDD-unit-tested; network repos verified by running the app (T17). CI gate stays the 328-test mock suite.
- **Open plan-time confirmations** for the implementer: exact protocol signatures in `Core/Data/Repositories/*`, exact model property names in `Core/Models/*`, and whether `0001` sets a `user_id` default of `auth.uid()` (affects whether inserts must include `user_id`).
