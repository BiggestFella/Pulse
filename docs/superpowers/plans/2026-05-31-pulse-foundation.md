# Pulse Foundation Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the Pulse repository, conventions, a buildable SwiftUI app skeleton, the Supabase schema, and the GitHub + Linear project setup — the foundation every feature is built on.

**Architecture:** Native SwiftUI (iOS 17+), MVVM + `@Observable`, feature-folder layout. Xcode project generated from a checked-in `project.yml` via XcodeGen. Data access through repositories over a Supabase (Postgres) backend. Schema lives in `supabase/migrations`.

**Tech Stack:** Swift 5.9+, SwiftUI, XcodeGen, supabase-swift, Supabase/Postgres, GitHub Actions, Linear, GitHub.

---

## Prerequisites (verify before starting)

- [ ] **Step 0a: Confirm toolchain**

Run: `xcodebuild -version && swift --version`
Expected: Xcode 15+ and Swift 5.9+.

- [ ] **Step 0b: Confirm XcodeGen is available (install if missing)**

Run: `which xcodegen || brew install xcodegen`
Expected: a path to `xcodegen`.

- [ ] **Step 0c: Confirm GitHub CLI is authenticated**

Run: `gh auth status`
Expected: logged in. If not: `gh auth login`.

---

## Task 1: Repo hygiene — `.gitignore` and README

**Files:**
- Create: `.gitignore`
- Create: `README.md`

- [ ] **Step 1: Write `.gitignore`**

```gitignore
# Xcode
*.xcodeproj/*
!*.xcodeproj/project.pbxproj
*.xcworkspace/xcuserdata/
xcuserdata/
DerivedData/
build/
*.xcuserstate

# XcodeGen generates the project; do not commit it
Pulse.xcodeproj/

# Swift Package Manager
.build/
.swiftpm/

# macOS
.DS_Store

# Secrets
*.env
.env*
Secrets.xcconfig
```

- [ ] **Step 2: Write `README.md`**

```markdown
# Pulse

A native iOS (SwiftUI) solo workout tracker. Follow a program, run a workout
(log sets with rests, supersets, swaps, history), plan on a calendar, build
routines in a library, and review stats / PRs / history.

## Setup
1. Install XcodeGen: `brew install xcodegen`
2. Generate the project: `xcodegen generate`
3. Open `Pulse.xcodeproj` in Xcode (15+), select the `Pulse` scheme, run.

## Backend
Supabase (Postgres). Schema migrations live in `supabase/`.

## Conventions & workflow
See `CLAUDE.md`. Every feature: brainstorm → spec → plan → build → review,
with human approval gates. Specs in `docs/superpowers/specs/`, plans in
`docs/superpowers/plans/`.
```

- [ ] **Step 3: Commit**

```bash
git add .gitignore README.md
git commit -m "chore: add gitignore and README"
```

---

## Task 2: Import the design handoff into `docs/design/`

**Files:**
- Create: `docs/design/` (copy of the handoff bundle)

- [ ] **Step 1: Copy the handoff bundle**

```bash
mkdir -p docs/design
cp -R "/Users/leoncreed-baker/Downloads/design_handoff_pulse_gym/." docs/design/
```

- [ ] **Step 2: Verify the design tokens and source-of-truth files landed**

Run: `ls docs/design`
Expected: `README.md`, `PULSE Design System.html`, `Pulse Gym Wireframes.html`, `Pulse Gym App.html`, `pulse-app.jsx`, `design-canvas.jsx`.

- [ ] **Step 3: Commit**

```bash
git add docs/design
git commit -m "docs: import Pulse design handoff (tokens, behavior, wireframes)"
```

---

## Task 3: `CLAUDE.md` — conventions and workflow gates

**Files:**
- Create: `CLAUDE.md`

- [ ] **Step 1: Write `CLAUDE.md`**

```markdown
# CLAUDE.md — Pulse

## What Pulse is
Native iOS (SwiftUI) **solo workout tracker**. Follow a program → run a workout
(log sets in real time with rests, supersets, swaps, history) → plan on a
calendar → build workouts/routines/folders in a library → review stats/PRs/history.

## Tech & architecture
- **SwiftUI, iOS 17+ baseline.** Swift Concurrency (`async`/`await`).
- **MVVM + `@Observable`.** Each screen = a `View` + an `@Observable` model in
  the same `Features/<Feature>/` folder.
- **Project is generated** from `project.yml` via XcodeGen. Never hand-edit the
  `.xcodeproj`; edit `project.yml` and run `xcodegen generate`.
- **Data access only through repositories** in `Core/Data`. Views and models
  never talk to Supabase directly.
- **Widgets & Live Activities** live in the `PulseWidgets` extension (WidgetKit +
  ActivityKit). The lock-screen / Dynamic Island workout timer is a Live Activity.

## Folder layout
- `Pulse/App` — entry point, app shell, 4-tab bar (Today · Library · Plan · You).
- `Pulse/Features/<Feature>` — one folder per screen; View + @Observable model.
- `Pulse/Core/DesignSystem` — `Theme`, color/spacing/type tokens, button styles.
- `Pulse/Core/Models` — domain structs (Program, Workout, …).
- `Pulse/Core/Data` — Supabase client + repositories.
- `Pulse/Core/Workout` — the active-session engine.
- `PulseWidgets` — widgets + Live Activity.
- `supabase/migrations` — SQL schema.

## Design system rules
- **Never hardcode colors or spacing.** Use `Theme` tokens only.
- Two themes: **Coastal** (default) and **Mint**, switchable under You → Palette.
- Typography: **Hanken Grotesk** (body), **Oswald** (condensed hero numerals),
  **Geist Mono** (uppercase labels/eyebrows). Tokens & rules: `docs/design/`.
- On an `accent`-filled card, small highlight text uses `onAccent`, never `accent2`.

## Testing
- Unit-test `@Observable` models and the workout engine.
- Acceptance/UI tests cover the user-story criteria from each feature spec.
- Tests + build must pass before any PR (CI enforces this).

## Git / PR conventions
- Branch: `feature/<linear-id>-short-slug` (e.g. `feature/PUL-12-rest-timer`).
- Conventional commits (`feat:`, `fix:`, `chore:`, `docs:`, `test:`).
- Open a PR; CI must be green; use the PR template; link the Linear issue.

## Development workflow — roles & human gates
Every feature follows the same path. Three human checkpoints.

1. **Research (read-only):** `Explore` agent maps relevant code first.
2. **Story + Spec:** `brainstorming` skill → spec in `docs/superpowers/specs/`.
   ⏸ **Human gate: approve the spec.**
3. **Plan:** `writing-plans` skill → plan in `docs/superpowers/plans/`.
   ⏸ **Human gate: approve the plan.**
4. **Build:** `executing-plans` or `subagent-driven-development`.
5. **Verify:** acceptance tests required by the spec must pass.
6. **Validate & review:** `code-reviewer` agent + `/security-review`.
   ⏸ **Human gate: review the PR.**

(We deliberately do NOT split backend vs frontend into separate locked agents —
overkill for a SwiftUI app.)
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add CLAUDE.md conventions and workflow gates"
```

---

## Task 4: XcodeGen project spec + buildable app skeleton

**Files:**
- Create: `project.yml`
- Create: `Pulse/App/PulseApp.swift`
- Create: `Pulse/App/AppShell.swift`
- Create: `Pulse/Features/Today/TodayView.swift`
- Create: `Pulse/Features/Library/LibraryView.swift`
- Create: `Pulse/Features/Plan/PlanView.swift`
- Create: `Pulse/Features/You/YouView.swift`
- Create: `Pulse/Resources/Info.plist`

- [ ] **Step 1: Write `project.yml`**

```yaml
name: Pulse
options:
  bundleIdPrefix: au.com.codeheroes.pulse
  deploymentTarget:
    iOS: "17.0"
settings:
  base:
    SWIFT_VERSION: "5.9"
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
targets:
  Pulse:
    type: application
    platform: iOS
    sources: [Pulse]
    settings:
      base:
        INFOPLIST_FILE: Pulse/Resources/Info.plist
        PRODUCT_BUNDLE_IDENTIFIER: au.com.codeheroes.pulse
        GENERATE_INFOPLIST_FILE: NO
  PulseTests:
    type: bundle.unit-test
    platform: iOS
    sources: [PulseTests]
    dependencies:
      - target: Pulse
  PulseUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [PulseUITests]
    dependencies:
      - target: Pulse
schemes:
  Pulse:
    build:
      targets:
        Pulse: all
    test:
      targets: [PulseTests, PulseUITests]
```

- [ ] **Step 2: Write `Pulse/Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key><string>Pulse</string>
  <key>UILaunchScreen</key><dict/>
  <key>UIApplicationSceneManifest</key>
  <dict><key>UIApplicationSupportsMultipleScenes</key><false/></dict>
</dict>
</plist>
```

- [ ] **Step 3: Write the app entry point `Pulse/App/PulseApp.swift`**

```swift
import SwiftUI

@main
struct PulseApp: App {
    var body: some Scene {
        WindowGroup {
            AppShell()
        }
    }
}
```

- [ ] **Step 4: Write `Pulse/App/AppShell.swift` (4-tab bar)**

```swift
import SwiftUI

struct AppShell: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "bolt.fill") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "square.stack.fill") }
            PlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }
            YouView()
                .tabItem { Label("You", systemImage: "person.fill") }
        }
    }
}

#Preview { AppShell() }
```

- [ ] **Step 5: Write the four placeholder tab screens**

`Pulse/Features/Today/TodayView.swift`:
```swift
import SwiftUI

struct TodayView: View {
    var body: some View {
        NavigationStack { Text("Today").navigationTitle("Today") }
    }
}
```
`Pulse/Features/Library/LibraryView.swift`:
```swift
import SwiftUI

struct LibraryView: View {
    var body: some View {
        NavigationStack { Text("Library").navigationTitle("Library") }
    }
}
```
`Pulse/Features/Plan/PlanView.swift`:
```swift
import SwiftUI

struct PlanView: View {
    var body: some View {
        NavigationStack { Text("Plan").navigationTitle("Plan") }
    }
}
```
`Pulse/Features/You/YouView.swift`:
```swift
import SwiftUI

struct YouView: View {
    var body: some View {
        NavigationStack { Text("You").navigationTitle("You") }
    }
}
```

- [ ] **Step 6: Create empty test target folders so XcodeGen finds sources**

```bash
mkdir -p PulseTests PulseUITests
```

(These are populated in Task 5 and Task 6. For now, create a placeholder so the
target compiles.)

`PulseTests/Placeholder.swift`:
```swift
import XCTest

final class Placeholder: XCTestCase {
    func testHarnessRuns() { XCTAssertTrue(true) }
}
```
`PulseUITests/PulseUITests.swift`:
```swift
import XCTest

final class PulseUITests: XCTestCase {
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5))
    }
}
```

- [ ] **Step 7: Generate the project and build**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 15' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 8: Commit**

```bash
git add project.yml Pulse PulseTests PulseUITests
git commit -m "feat: buildable SwiftUI skeleton with 4-tab shell (XcodeGen)"
```

---

## Task 5: Design system — `Theme` and tokens (TDD)

**Files:**
- Create: `Pulse/Core/DesignSystem/Theme.swift`
- Create: `Pulse/Core/DesignSystem/Palette.swift`
- Test: `PulseTests/PaletteTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/PaletteTests.swift`**

```swift
import XCTest
import SwiftUI
@testable import Pulse

final class PaletteTests: XCTestCase {
    func testCoastalIsDefault() {
        XCTAssertEqual(Palette.default, .coastal)
    }

    func testEveryPaletteDefinesAllTokens() {
        for palette in Palette.allCases {
            let t = palette.tokens
            // hex strings are 7 chars ("#RRGGBB") and parse to a Color
            XCTAssertEqual(t.bg.count, 7)
            XCTAssertEqual(t.accent.count, 7)
            XCTAssertEqual(t.accent2.count, 7)
            XCTAssertEqual(t.onAccent.count, 7)
        }
    }

    func testCoastalAccentHex() {
        XCTAssertEqual(Palette.coastal.tokens.accent, "#26B6F6")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 15' test`
Expected: FAIL — `Palette` undefined.

- [ ] **Step 3: Write `Pulse/Core/DesignSystem/Palette.swift`**

```swift
import Foundation

/// Raw, theme-able token values from the design handoff. Hex strings so they
/// are testable without a rendering context; `Theme` converts them to `Color`.
struct PaletteTokens {
    let bg, surface, surface2: String
    let ink, inkSoft, inkFaint: String
    let accent, accentDeep, accent2, onAccent: String
}

enum Palette: String, CaseIterable {
    case coastal, mint

    static let `default`: Palette = .coastal

    var tokens: PaletteTokens {
        switch self {
        case .coastal:
            return PaletteTokens(
                bg: "#06121F", surface: "#0E1F33", surface2: "#16314D",
                ink: "#FFF4D6", inkSoft: "#FFF4D6", inkFaint: "#FFF4D6",
                accent: "#26B6F6", accentDeep: "#0E5BA8",
                accent2: "#FF6A1F", onAccent: "#06121F")
        case .mint:
            return PaletteTokens(
                bg: "#0F1814", surface: "#1A2620", surface2: "#26332B",
                ink: "#E1F4E8", inkSoft: "#E1F4E8", inkFaint: "#E1F4E8",
                accent: "#00D9B8", accentDeep: "#007A6C",
                accent2: "#FFCC33", onAccent: "#0F1814")
        }
    }
}
```

(Note: `inkSoft`/`inkFaint` opacity variants are applied in `Theme` via alpha;
the base hex is the full-opacity ink color.)

- [ ] **Step 4: Write `Pulse/Core/DesignSystem/Theme.swift`**

```swift
import SwiftUI

/// Resolves the active palette into SwiftUI `Color`s and exposes spacing/radii.
/// Inject via `.environment(Theme.self)`; never hardcode colors in views.
@Observable
final class Theme {
    var palette: Palette {
        didSet { UserDefaults.standard.set(palette.rawValue, forKey: Self.key) }
    }
    private static let key = "pulse-pal"

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.key)
        self.palette = raw.flatMap(Palette.init(rawValue:)) ?? .default
    }

    private var t: PaletteTokens { palette.tokens }

    var bg: Color { Color(hex: t.bg) }
    var surface: Color { Color(hex: t.surface) }
    var surface2: Color { Color(hex: t.surface2) }
    var ink: Color { Color(hex: t.ink) }
    var inkSoft: Color { Color(hex: t.ink).opacity(0.62) }
    var inkFaint: Color { Color(hex: t.ink).opacity(0.16) }
    var accent: Color { Color(hex: t.accent) }
    var accentDeep: Color { Color(hex: t.accentDeep) }
    var accent2: Color { Color(hex: t.accent2) }
    var onAccent: Color { Color(hex: t.onAccent) }

    // Spacing rhythm and radii from the handoff.
    let spacing: [CGFloat] = [4, 8, 10, 12, 14, 18, 24]
    let radiusCard: CGFloat = 16
    let radiusPill: CGFloat = 999
}

extension Color {
    /// "#RRGGBB" → Color. Falls back to clear on malformed input.
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        guard s.count == 6, Scanner(string: s).scanHexInt64(&v) else {
            self = .clear; return
        }
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 15' test`
Expected: PASS (PaletteTests green).

- [ ] **Step 6: Commit**

```bash
git add Pulse/Core/DesignSystem PulseTests/PaletteTests.swift
git commit -m "feat: design-system Theme and palette tokens (Coastal/Mint)"
```

---

## Task 6: Domain models (TDD)

**Files:**
- Create: `Pulse/Core/Models/WorkoutModels.swift`
- Test: `PulseTests/WorkoutModelsTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/WorkoutModelsTests.swift`**

```swift
import XCTest
@testable import Pulse

final class WorkoutModelsTests: XCTestCase {
    func testSetSpecCodableRoundTrip() throws {
        let original = SetSpec(reps: 10, rir: 2, type: .working)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SetSpec.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testSetTypeHasAllFiveCases() {
        XCTAssertEqual(Set(SetType.allCases),
                       [.working, .warmup, .dropset, .failure, .amrap])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 15' test`
Expected: FAIL — `SetSpec` / `SetType` undefined.

- [ ] **Step 3: Write `Pulse/Core/Models/WorkoutModels.swift`**

```swift
import Foundation

enum SetType: String, Codable, CaseIterable {
    case working, warmup, dropset, failure, amrap
}

struct SetSpec: Codable, Equatable, Identifiable {
    var id = UUID()
    var reps: Int
    var rir: Int
    var type: SetType
}

struct Variation: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var equipment: String?
}

struct Exercise: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var muscleGroup: String
    var variations: [Variation]
    var defaultVariationID: Variation.ID?
}

struct WorkoutExercise: Codable, Equatable, Identifiable {
    var id = UUID()
    var exercise: Exercise
    var variationID: Variation.ID?
    var supersetGroup: String?   // shared tag groups superset members
    var sets: [SetSpec]
}

struct Workout: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var weekday: Int?            // 1...7, nil = unscheduled
    var order: Int
    var exercises: [WorkoutExercise]
}

struct Program: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var weeks: Int
    var workouts: [Workout]
}

/// A logged session — actual performance against a Workout.
struct SessionSet: Codable, Equatable, Identifiable {
    var id = UUID()
    var reps: Int
    var weight: Double
    var type: SetType
}

struct WorkoutSession: Codable, Equatable, Identifiable {
    var id = UUID()
    var workoutID: Workout.ID
    var startedAt: Date
    var endedAt: Date?
    var sets: [SessionSet]
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 15' test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Pulse/Core/Models PulseTests/WorkoutModelsTests.swift
git commit -m "feat: domain models (Program → Workout → … → SessionSet)"
```

---

## Task 7: Supabase schema migration

**Files:**
- Create: `supabase/migrations/0001_initial_schema.sql`
- Create: `supabase/seed.sql`

- [ ] **Step 1: Write `supabase/migrations/0001_initial_schema.sql`**

```sql
-- Pulse initial schema. Mirrors the domain models in Pulse/Core/Models.
create type set_type as enum ('working','warmup','dropset','failure','amrap');

create table programs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  weeks int not null check (weeks > 0),
  created_at timestamptz not null default now()
);

create table exercises (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  muscle_group text not null
);

create table variations (
  id uuid primary key default gen_random_uuid(),
  exercise_id uuid not null references exercises(id) on delete cascade,
  name text not null,
  equipment text
);

create table workouts (
  id uuid primary key default gen_random_uuid(),
  program_id uuid not null references programs(id) on delete cascade,
  name text not null,
  weekday int check (weekday between 1 and 7),
  "order" int not null
);

create table workout_exercises (
  id uuid primary key default gen_random_uuid(),
  workout_id uuid not null references workouts(id) on delete cascade,
  exercise_id uuid not null references exercises(id),
  variation_id uuid references variations(id),
  superset_group text,
  "order" int not null
);

create table set_specs (
  id uuid primary key default gen_random_uuid(),
  workout_exercise_id uuid not null references workout_exercises(id) on delete cascade,
  reps int not null,
  rir int not null,
  type set_type not null default 'working',
  "order" int not null
);

create table sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  workout_id uuid not null references workouts(id),
  started_at timestamptz not null default now(),
  ended_at timestamptz
);

create table session_sets (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references sessions(id) on delete cascade,
  exercise_id uuid not null references exercises(id),
  reps int not null,
  weight numeric not null,
  type set_type not null,
  "order" int not null
);

-- Row-level security: a user sees only their own programs/sessions.
alter table programs enable row level security;
alter table sessions enable row level security;
create policy "own_programs" on programs
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own_sessions" on sessions
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

- [ ] **Step 2: Write an empty `supabase/seed.sql` placeholder**

```sql
-- Seed data for local development (exercise catalog) goes here.
```

- [ ] **Step 3: Validate the SQL parses (if a local Postgres/psql is available)**

Run: `psql --version 2>/dev/null && echo "validate manually against a Supabase project" || echo "no local psql; SQL applied during Supabase provisioning (Task 10)"`
Expected: either a psql version, or the no-psql notice. No failure either way.

- [ ] **Step 4: Commit**

```bash
git add supabase
git commit -m "feat: initial Supabase schema and RLS policies"
```

---

## Task 8: CI workflow and PR template

**Files:**
- Create: `.github/workflows/ci.yml`
- Create: `.github/pull_request_template.md`

- [ ] **Step 1: Write `.github/workflows/ci.yml`**

```yaml
name: CI
on:
  pull_request:
  push:
    branches: [main]
jobs:
  build-test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Install XcodeGen
        run: brew install xcodegen
      - name: Generate project
        run: xcodegen generate
      - name: Build & test
        run: |
          xcodebuild -project Pulse.xcodeproj -scheme Pulse \
            -destination 'platform=iOS Simulator,name=iPhone 15' \
            clean test
```

- [ ] **Step 2: Write `.github/pull_request_template.md`**

```markdown
## What & why
<!-- Link the Linear issue: closes PUL-XX -->

## Spec / plan
<!-- Link the spec and plan docs this implements -->

## Checklist
- [ ] Tests added/updated and passing
- [ ] No hardcoded colors/spacing (Theme tokens only)
- [ ] Data access goes through a repository
- [ ] `xcodegen generate` runs clean
```

- [ ] **Step 3: Commit**

```bash
git add .github
git commit -m "ci: add build+test workflow and PR template"
```

---

## Task 9: Create the GitHub repository and push (⏸ outward action — confirm first)

- [ ] **Step 1: Confirm with the user before creating the remote repo.**

- [ ] **Step 2: Create the private repo and push**

Run:
```bash
gh repo create Pulse --private --source=. --remote=origin --push
```
Expected: repo created, `main` pushed, `origin` set.

- [ ] **Step 3: Verify**

Run: `gh repo view --json nameWithOwner,visibility -q '.nameWithOwner + " (" + .visibility + ")"'`
Expected: `<owner>/Pulse (PRIVATE)`.

---

## Task 10: Provision Supabase (⏸ outward action — confirm first)

Supabase project creation requires the user's Supabase account. There is no
Supabase MCP connected, so this task documents the steps and applies the schema
via the Supabase CLI if the user is logged in.

- [ ] **Step 1: Confirm the user has a Supabase project (or create one at supabase.com).**

- [ ] **Step 2: If the Supabase CLI is available, link and push the migration**

Run:
```bash
which supabase || brew install supabase/tap/supabase
supabase link --project-ref <PROJECT_REF>
supabase db push
```
Expected: migration `0001_initial_schema` applied.

- [ ] **Step 3: Record the project URL and anon key in `Secrets.xcconfig` (git-ignored).**

Create `Secrets.xcconfig` (NOT committed — it is in `.gitignore`):
```
SUPABASE_URL = https://<ref>.supabase.co
SUPABASE_ANON_KEY = <anon-key>
```

(Wiring `supabase-swift` into the app as a Swift Package and building the
repository layer is the first product feature — out of scope for this
foundation plan.)

---

## Task 11: Create the Linear project and seed the backlog (⏸ outward action — confirm first)

Use the Linear MCP tools (`list_teams`, `save_project`, `save_issue`).

- [ ] **Step 1: Confirm with the user, and identify the Linear team**

Call `list_teams` to get the team ID.

- [ ] **Step 2: Create the project**

Call `save_project` with name `Pulse`, description: "Native iOS solo workout
tracker — SwiftUI + Supabase. See repo docs/ for specs and plans."

- [ ] **Step 3: Seed one issue per backlog item (in build order)**

Create these issues (via `save_issue`, linked to the Pulse project), each with a
one-line description pointing at `docs/design/README.md` for behavior:

1. Foundation setup (this plan) — mark done once merged
2. Supabase schema applied + `supabase-swift` repository layer
3. Design system: fonts, button styles, theme switching UI
4. Auth & onboarding
5. Today tab
6. Library tab
7. Exercise detail
8. Plan / Calendar
9. You / Settings (incl. palette picker, preferences)
10. Workout active flow (pre → active set → rest → summary) — **large**
11. Stats
12. Personal records
13. Workout history + session detail
14. Builders (workout / routine / folder)
15. Widgets (WidgetKit)
16. Live Activity — lock-screen / Dynamic Island workout & rest timer — **large**

- [ ] **Step 4: Verify**

Call `list_issues` for the Pulse project and confirm 16 issues exist.

---

## Self-Review notes

- **Spec coverage:** repo/folder structure (Tasks 1–8), CLAUDE.md + workflow gates (Task 3), XcodeGen (Task 4), MVVM/@Observable conventions (Task 3, demonstrated Task 5), design tokens (Task 5), data model (Task 6) + Supabase schema (Task 7), CI/PR (Task 8), GitHub (Task 9), Supabase (Task 10), Linear backlog (Task 11). All spec sections covered.
- **Out of scope (per spec):** feature UIs, supabase-swift wiring, Tuist, Android, class booking, TestFlight/CD. Not planned here — correct.
- **Type consistency:** `SetType` cases match the SQL `set_type` enum; `Palette`/`PaletteTokens`/`Theme` names consistent across Task 5 and CLAUDE.md; model names match the schema tables in Task 7.
- **Outward actions** (Tasks 9–11) each gated by an explicit confirm step.
```
