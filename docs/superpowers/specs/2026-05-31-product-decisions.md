# Pulse — Product Decisions (authoritative)

**Date:** 2026-05-31
**Purpose:** Resolves open questions raised across the backlog specs. Where a spec's "Open questions" conflicts with this doc, **this doc wins**. Plan authors and implementers must follow these.

## Confirmed by product owner

1. **Personal Record = estimated 1RM via Epley.** `1RM = weight × (1 + reps/30)`, computed per logged working/AMRAP set (warmups excluded). PRs are *derived* (no stored table). A PR is the max est-1RM per exercise (and per variation where shown). `isNew` = a record set within the queried range. Applies to PRs (BAK-16), Exercise Detail (BAK-11), Stats (BAK-15), analytics helper (BAK-6).
2. **Streak = consecutive *honored scheduled days*.** A scheduled training day counts when a session was completed that day; **rest days neither break nor extend** the streak; a scheduled training day with no session breaks it. Applies to Today (BAK-9), Stats (BAK-15), analytics (BAK-6).
3. **Units: kilograms only for v1.** All weights display/store in kg (prototype's "LBS" copy is replaced with "KG"). A units preference + conversion is a **later feature** — do not build the toggle now, but keep weight formatting in one helper so adding it later is localized. Applies to all weight displays + You/Preferences (BAK-13).
4. **Auth/onboarding (BAK-8) and Widgets (BAK-19) are parked** pending their own brainstorm. They are **excluded from the plans batch**; their draft specs remain "Draft — needs brainstorm."

## Default resolutions for recurring screen-level questions

Chosen by the team to unblock planning; revisit any during spec review.

- **Calendar/timezone:** all day-bucketing (streak, today's workout, schedule, stats ranges) uses `Calendar.current` in the device-local timezone. Centralize in the analytics helper.
- **Week starts Monday** everywhere (Today week strip + Plan calendar), matching the design's Mon-start grid.
- **StatRange bucketing:** 7D & 30D bucket by **day**; 3M by **week**; YR & ALL by **month**.
- **`activeProgram` selection:** a single `isActive: Bool` on `Program` (mock seeds the PPL program active). Real "follow a program" semantics arrive with auth (BAK-8).
- **`default_variation_id`:** add a real `default_variation_id` column to `exercises` in the BAK-6 migration (explicit, not convention). The variation switcher hides when an exercise has ≤1 variation.
- **`SessionSet`:** add `exerciseID: Exercise.ID` **and** an explicit `order: Int` to the Swift struct (mirror the SQL `"order"`); arrays stay authoritative for `SetSpec`/`WorkoutExercise` ordering but repos persist `"order"` on write.
- **Scheduling table (`plan_entries`):** `user_id, date, workout_id (nullable), state ∈ {planned, rest, done}, session_id (nullable)`. A day is "done" when `session_id` is set; "rest" carries no workout; "planned" has a `workout_id`.
- **Sheets/drawers:** use native `.sheet` + `.presentationDetents` with custom styled content (26pt top radius, scrim, drag handle). Accept minor native-chrome differences rather than a fully custom overlay for v1.
- **Fonts:** vendor the three OFL-licensed Google fonts (Hanken Grotesk, Oswald, Geist Mono) into `Pulse/Resources/Fonts/` and declare `UIAppFonts` in `project.yml`. The design-system plan includes obtaining the font files. No system-font fallback for the hero look.
- **Hero numerals:** fixed poster point-sizes for v1 (no Dynamic Type scaling on Oswald hero numerals); Dynamic Type support is a later accessibility pass. Body text uses standard scaling.
- **Grain overlay:** deferred (optional flourish).
- **`⋯` overflow menus & decorative search fields:** render as inert placeholders in v1 (no actions wired) unless a spec says otherwise; note them as follow-ups.
- **PR badge source:** derived from the PR data set (est-1RM), not an ad-hoc flag on `Exercise`.

## Build strategy reminder
UI-first against the BAK-6 repository protocols + in-memory mocks. Real Supabase wiring and child-table RLS land with BAK-6's live implementation, behind the same protocols.
