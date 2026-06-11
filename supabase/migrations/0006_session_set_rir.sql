-- Add optional Reps-In-Reserve to logged sets (BAK-36).
-- Nullable: legacy rows and fast-logged sets carry NULL = "not recorded".
-- `smallint` is ample (RIR is 0..~5); CHECK keeps it non-negative.
-- Mirrors `SessionSet.rir: Int?` in Pulse/Core/Models/WorkoutModels.swift and
-- the existing `set_specs.rir` (planned-side) column from 0001_initial_schema.sql.
alter table session_sets
  add column rir smallint null check (rir is null or rir >= 0);

comment on column session_sets.rir is
  'Reps In Reserve at set completion; NULL = not recorded. Maps to SessionSet.rir.';
