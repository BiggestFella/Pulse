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
