# Pulse — Specs & Plans Index

Every backlog feature has a **spec** (what to build) and, unless parked, a
**plan** (how to build it). Authoritative cross-cutting answers live in
[`specs/2026-05-31-product-decisions.md`](specs/2026-05-31-product-decisions.md)
— it overrides any "open question" in an individual spec.

**Build order:** dependencies first. `BAK-7` and `BAK-6` are the only tickets with
no blockers; build them first (in parallel is fine). Everything else is blocked by
both, plus the extra blockers noted below. See `AGENTS.md` for the working process.

| Ticket | Feature | Blocked by | Spec | Plan |
|--------|---------|-----------|------|------|
| **BAK-7** | Design System (fonts, buttons, theme) | — (ready) | [spec](specs/2026-05-31-design-system-spec.md) | [plan](plans/2026-05-31-design-system-plan.md) |
| **BAK-6** | Data layer (repos, mocks, Supabase map) | — (ready) | [spec](specs/2026-05-31-data-layer-spec.md) | [plan](plans/2026-05-31-data-layer-plan.md) |
| BAK-9 | Today tab | 7, 6 | [spec](specs/2026-05-31-today-tab-spec.md) | [plan](plans/2026-05-31-today-tab-plan.md) |
| BAK-10 | Library tab | 7, 6 | [spec](specs/2026-05-31-library-tab-spec.md) | [plan](plans/2026-05-31-library-tab-plan.md) |
| BAK-11 | Exercise detail | 7, 6 | [spec](specs/2026-05-31-exercise-detail-spec.md) | [plan](plans/2026-05-31-exercise-detail-plan.md) |
| BAK-12 | Plan / Calendar | 7, 6 | [spec](specs/2026-05-31-plan-calendar-spec.md) | [plan](plans/2026-05-31-plan-calendar-plan.md) |
| BAK-13 | You / Settings | 7, 6 | [spec](specs/2026-05-31-you-settings-spec.md) | [plan](plans/2026-05-31-you-settings-plan.md) |
| BAK-14 | Workout active flow | 7, 6 | [spec](specs/2026-05-31-workout-active-flow-spec.md) | [plan](plans/2026-05-31-workout-active-flow-plan.md) |
| BAK-15 | Stats | 7, 6 | [spec](specs/2026-05-31-stats-spec.md) | [plan](plans/2026-05-31-stats-plan.md) |
| BAK-16 | Personal records | 7, 6, 15 | [spec](specs/2026-05-31-personal-records-spec.md) | [plan](plans/2026-05-31-personal-records-plan.md) |
| BAK-17 | History + session detail | 7, 6 | [spec](specs/2026-05-31-history-session-detail-spec.md) | [plan](plans/2026-05-31-history-session-detail-plan.md) |
| BAK-18 | Builders (workout/routine/folder) | 7, 6, 10 | [spec](specs/2026-05-31-builders-spec.md) | [plan](plans/2026-05-31-builders-plan.md) |
| BAK-20 | Live Activity (lock screen / Dynamic Island) | 7, 6, 14 | [spec](specs/2026-05-31-live-activity-spec.md) | [plan](plans/2026-05-31-live-activity-plan.md) |
| BAK-8 | Auth & onboarding | — | [spec](specs/2026-05-31-auth-onboarding-spec.md) | **PARKED — needs brainstorm** |
| BAK-19 | Widgets (WidgetKit) | 7, 6 | [spec](specs/2026-05-31-widgets-spec.md) | **PARKED — needs brainstorm** |

**Foundation** (already merged): [spec](specs/2026-05-31-pulse-foundation-design.md) · [plan](plans/2026-05-31-pulse-foundation.md).

> **Parked** = not in the original prototype; the draft spec is assumption-heavy
> and needs its own brainstorm before a plan is written. Don't auto-implement.
