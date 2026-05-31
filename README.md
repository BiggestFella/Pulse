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
