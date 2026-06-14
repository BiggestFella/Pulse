-- Dev seed for the Pulse dev Supabase project (BAK-27).
-- Seeds the catalog (parents + variations), and the dev user's active program +
-- "Upper" workout, with fixed UUIDs that match TodaysWorkout in the app so the
-- active flow logs against real rows (FKs resolve). Run-once-friendly: workout
-- children are cleared first; catalog/program/workout use ON CONFLICT DO NOTHING.
-- Run as DB owner (bypasses RLS). Dev user: 7816633c-c06f-476a-a8c5-08323c043d38

-- clean the workout's children so re-running re-seeds cleanly
delete from set_specs where workout_exercise_id in
  (select id from workout_exercises where workout_id = '512251d0-5c9d-4018-a24e-87e9b639d2be');
delete from workout_exercises where workout_id = '512251d0-5c9d-4018-a24e-87e9b639d2be';

-- Remove stale variations from the pre-0005 dev seed that aren't in the curated
-- catalog (0005 owns the catalog now). No-ops on a fresh DB. The guards skip any
-- row still referenced by a logged set or another workout, so this never errors.
delete from variations v where v.id in (
  '30939bf4-5f36-4f09-99af-eb2cd259b806', -- Incline Chest Press · Barbell
  'b284cc57-087a-42b4-a490-2622ba8f776a', -- Incline Chest Press · Dumbbell
  'c2a89b80-dd1b-40b1-96c5-3e565be89a72', -- Lat Pulldown · Wide grip
  '6107912e-d807-4211-8128-0b5587dd4d33', -- Lat Pulldown · Close grip
  '60d50886-8c09-4c14-b07d-3832211ae901', -- Shoulder Press · Barbell
  'bfccb882-2481-48c8-bdc9-fde6f5ec6c96', -- Shoulder Press · Machine
  'a41fba6f-120c-49f2-9450-b5382315925b', -- Tricep Extension · Cable
  'c5d10d2f-8f99-428c-9d83-abc01c299fb3', -- Tricep Extension · Dumbbell
  '4d8cdf13-6716-485a-b26e-8d393708361d', -- Preacher Curl · EZ-bar
  '23d891b0-55d1-46d2-a4b6-61f5b4fe0a0a'  -- Push-Up · Standard
)
and not exists (select 1 from session_sets s where s.variation_id = v.id)
and not exists (select 1 from workout_exercises we where we.variation_id = v.id);

-- The exercise catalog (parents + variations + default_variation_id) is now
-- seeded by migration 0005_seed_exercise_catalog.sql for ALL environments. The
-- workout below references the fixed catalog UUIDs that 0005 guarantees:
--   Incline 59d41db7 / Machine ce0e5e04 · Lat ad971ed1 / D-bar cbbb3cff
--   Shoulder ba11b697 / Seated Machine c2229eca · Tricep 30ff4dba / Plate Loaded 89553dae
--   Preacher 908a7e05 / Machine 6342839f · Push-Up d23e3b5d / Deficit d9dae16f

-- ── dev user's active program + "Upper" workout ────────────────────────────
insert into programs (id, user_id, name, weeks, is_active) values
  ('7bc1287f-a0d2-417c-875a-e256c9be5692', '7816633c-c06f-476a-a8c5-08323c043d38', 'My Program', 8, true)
on conflict (id) do nothing;

insert into workouts (id, program_id, name, "order") values
  ('512251d0-5c9d-4018-a24e-87e9b639d2be', '7bc1287f-a0d2-417c-875a-e256c9be5692', 'Upper', 0)
on conflict (id) do nothing;

-- ── workout exercises + set specs (one CTE per exercise) ───────────────────
with we as (insert into workout_exercises (workout_id, exercise_id, variation_id, "order")
  values ('512251d0-5c9d-4018-a24e-87e9b639d2be','59d41db7-85fc-4749-9347-e14d086f18f5','ce0e5e04-94d9-4adb-9b42-635faf5a191d',0) returning id)
insert into set_specs (workout_exercise_id, reps, rir, type, "order")
  select we.id, v.reps, v.rir, v.type::set_type, v.ord from we,
  (values (12,3,'working',0),(10,2,'working',1),(8,1,'working',2),(6,0,'working',3)) as v(reps,rir,type,ord);

with we as (insert into workout_exercises (workout_id, exercise_id, variation_id, "order")
  values ('512251d0-5c9d-4018-a24e-87e9b639d2be','ad971ed1-7ebe-40e9-99bb-47d404020037','cbbb3cff-0ade-4c81-b31c-c74f8530aac9',1) returning id)
insert into set_specs (workout_exercise_id, reps, rir, type, "order")
  select we.id, v.reps, v.rir, v.type::set_type, v.ord from we,
  (values (12,3,'working',0),(10,2,'working',1),(8,1,'working',2),(6,0,'working',3)) as v(reps,rir,type,ord);

with we as (insert into workout_exercises (workout_id, exercise_id, variation_id, "order")
  values ('512251d0-5c9d-4018-a24e-87e9b639d2be','ba11b697-5f0a-4c8c-ab39-37669ec0d154','c2229eca-465f-426e-91b6-af426eef76ba',2) returning id)
insert into set_specs (workout_exercise_id, reps, rir, type, "order")
  select we.id, v.reps, v.rir, v.type::set_type, v.ord from we,
  (values (12,2,'working',0),(10,1,'working',1),(8,0,'working',2)) as v(reps,rir,type,ord);

with we as (insert into workout_exercises (workout_id, exercise_id, variation_id, "order")
  values ('512251d0-5c9d-4018-a24e-87e9b639d2be','30ff4dba-6e0f-4b5d-b9cf-1acd2ed0b755','89553dae-bcaf-4031-9821-a7e4fd5d1e0e',3) returning id)
insert into set_specs (workout_exercise_id, reps, rir, type, "order")
  select we.id, v.reps, v.rir, v.type::set_type, v.ord from we,
  (values (12,2,'working',0),(10,1,'working',1),(8,0,'working',2)) as v(reps,rir,type,ord);

with we as (insert into workout_exercises (workout_id, exercise_id, variation_id, "order")
  values ('512251d0-5c9d-4018-a24e-87e9b639d2be','908a7e05-0635-4aaf-8de7-5a9eed2e91f9','6342839f-3025-405c-977a-da849d1b1083',4) returning id)
insert into set_specs (workout_exercise_id, reps, rir, type, "order")
  select we.id, v.reps, v.rir, v.type::set_type, v.ord from we,
  (values (0,0,'failure',0),(0,0,'failure',1),(0,0,'failure',2)) as v(reps,rir,type,ord);

with we as (insert into workout_exercises (workout_id, exercise_id, variation_id, "order")
  values ('512251d0-5c9d-4018-a24e-87e9b639d2be','d23e3b5d-9c0f-460a-8cad-f28271f26280','d9dae16f-24d2-4c9d-8a92-a710d0a9ae6f',5) returning id)
insert into set_specs (workout_exercise_id, reps, rir, type, "order")
  select we.id, v.reps, v.rir, v.type::set_type, v.ord from we,
  (values (12,1,'working',0),(12,1,'working',1),(12,0,'working',2)) as v(reps,rir,type,ord);
