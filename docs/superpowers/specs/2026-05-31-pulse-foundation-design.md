# Pulse — Foundation Layer Design

**Date:** 2026-05-31
**Status:** Approved (design) — pending spec review
**Scope:** Project foundation only. Product features are built later, each through its own brainstorm → spec → plan → build cycle.

## Overview

Pulse is a native **SwiftUI** iOS app: a **solo workout tracker** for lifters. A user follows a multi-week program, runs a workout (logging sets in real time with rests, supersets, swaps, history lookups), plans sessions on a calendar, builds workouts/routines/folders in a library, and reviews stats / PRs / history.

This document designs the **foundation layer**: the repository, folder structure, `CLAUDE.md` conventions, the development workflow with human gates, and the initial provisioning of GitHub, Linear, and Supabase. It does **not** design product features — those follow per-feature.

### Key decisions

| Decision | Choice | Rationale |
|---|---|---|
| Platform | Native iOS, SwiftUI | Standout features (widgets, Live Activities on lock screen / Dynamic Island) are iOS-native frameworks with no cross-platform equivalent. |
| iOS baseline | iOS 17+ | Enables `@Observable`. Live Activities need 16.1+; 17+ baseline is acceptable. |
| Architecture | MVVM + `@Observable` | Modern, idiomatic SwiftUI, low ceremony. |
| Backend | Supabase (Postgres) | Workout data is highly relational (program → workouts → exercises → sets); SQL fits. Auth + realtime included. |
| Project generation | XcodeGen (`project.yml`) | Avoids `.xcodeproj` merge conflicts in a PR + AI-editing workflow. |
| Tasks | Linear | Per user preference. |
| Source control / PRs | GitHub (private repo) | Per user preference. |
| v1 scope | The designed solo tracker | Class booking / gym-staff side parked as a future epic — not in the handoff. |

## Repository & folder structure

```
Pulse/
├── CLAUDE.md                  # conventions + the workflow gates
├── README.md
├── .gitignore                 # Swift/Xcode
├── project.yml                # XcodeGen — generates the .xcodeproj
├── .github/
│   ├── workflows/ci.yml       # build + test on every PR
│   └── pull_request_template.md
├── docs/
│   ├── design/                # the handoff: tokens, behavior, wireframes
│   ├── architecture/          # ADRs (one decision per file)
│   └── superpowers/specs/     # brainstorm specs (this doc lives here)
├── Pulse/                     # main app target
│   ├── App/                   # entry point, app shell, 4-tab bar
│   ├── Features/              # one folder per screen: Today, Library, Plan,
│   │   └── <Feature>/         #   You, Workout (active flow), Stats, PRs, History
│   │       ├── <Feature>View.swift
│   │       └── <Feature>Model.swift   # @Observable view model
│   ├── Core/
│   │   ├── DesignSystem/      # tokens, Theme (Coastal/Mint), Button styles, type
│   │   ├── Models/            # Program, Workout, WorkoutExercise, SetSpec, Session…
│   │   ├── Data/              # Supabase client + repositories
│   │   └── Workout/           # the session engine (STEPS, supersets, rest)
│   └── Resources/             # fonts (Hanken/Oswald/Geist Mono), assets
├── PulseWidgets/              # WidgetKit + ActivityKit (widgets + Live Activity)
├── PulseTests/                # unit tests (view models + workout engine)
├── PulseUITests/              # acceptance / UI tests
└── supabase/
    ├── migrations/            # SQL schema (Program → … → SessionSets)
    └── seed.sql
```

## `CLAUDE.md` contents

- **Project overview:** Pulse, solo workout tracker, SwiftUI, iOS 17+, Supabase.
- **Architecture:** MVVM + `@Observable`; feature-folder layout; Swift Concurrency; data access **only** through repositories in `Core/Data`.
- **Design system rules:** never hardcode colors/spacing — always use `Theme` tokens; Coastal (default) / Mint themes; typography stack (Hanken Grotesk body, Oswald condensed numerals, Geist Mono labels). Tokens copied from the handoff into `docs/design/`.
- **Testing:** unit-test view models and the workout engine; acceptance tests cover user-story criteria; tests + lint must pass before a PR.
- **Git/PR conventions:** branch naming (`feature/<linear-id>-slug`), conventional commits, PR template, green CI required.
- **Workflow gates** (see below).

## Development workflow — roles & human gates

Adapted from the "7 agents" concept, mapped onto existing Claude Code tools rather than building bespoke agents. The rigid backend-cannot-touch-frontend split is **deliberately omitted** as overkill for a SwiftUI app.

| Role | How we do it here | Gate |
|---|---|---|
| Codebase Researcher (read-only) | `Explore` agent / read-only research first | — |
| Story + Spec Writer | `brainstorming` skill → spec in `docs/superpowers/specs/` | ⏸ **user approves spec** |
| Planner | `writing-plans` skill → reviewable plan | ⏸ **user approves plan** |
| Builder | `executing-plans` / `subagent-driven-development` | — |
| Test Verifier | acceptance tests required by the spec | — |
| Implementation Validator | `code-reviewer` agent + `/security-review` (sees only disk) | ⏸ **user reviews PR** |

Three human checkpoints preserved: approve spec → approve plan → review PR.

## Provisioning plan (each gated by user confirmation)

1. **Git + GitHub:** `git init` → initial commit → create **private** repo `Pulse` → push. Includes `.gitignore`, CI (build + test), PR template.
2. **Linear:** create a **Pulse** project; seed a backlog as epics → issues mirroring build order:
   *Foundation setup · Supabase schema · Design system · Auth & onboarding · Today · Library · Exercise detail · Plan/Calendar · You/Settings · Workout active flow · Stats · PRs · History · Widgets · Live Activity.*
3. **Supabase:** schema migration from the handoff data model — `programs`, `workouts`, `workout_exercises`, `set_specs`, `exercises`, `variations`, `sessions`, `session_sets`; `set_type` enum `{working, warmup, dropset, failure, amrap}`.

## Out of scope (YAGNI)

No bespoke 7-agent definitions; no Tuist modularization yet; no Android; no class booking; no TestFlight/CD pipeline until there is something to ship.

## Data model reference (from handoff)

`Program` has many ordered `Workout`s (per weekday) → has many `WorkoutExercise` `(Exercise, Variation, ssGroup?)` → has many `SetSpec` `{reps, rir, type}`. A logged `Session` references the `Workout` and stores `SessionSet`s (actual reps/weight/type). `Exercise` has a default `Variation`; the variation switcher hides when only one exists.
