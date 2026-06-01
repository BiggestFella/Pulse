-- Pulse data-layer migration (BAK-6): scheduling table, child/catalog RLS,
-- and an explicit default_variation_id column. Builds on 0001_initial_schema.sql.

-- 1. default_variation_id on exercises (explicit, per product decisions).
alter table exercises
  add column default_variation_id uuid references variations(id);

-- 2. Scheduling table backing ScheduleRepository.DayPlan.
--    state: 'planned' has a workout_id; 'rest' carries no workout; 'done' has session_id.
create type plan_state as enum ('planned','rest','done');

create table plan_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  date date not null,
  workout_id uuid references workouts(id) on delete set null,
  session_id uuid references sessions(id) on delete set null,
  state plan_state not null,
  created_at timestamptz not null default now(),
  unique (user_id, date)
);

-- 3. RLS on the scheduling table (owner-scoped).
alter table plan_entries enable row level security;
create policy "own_plan_entries" on plan_entries
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- 4. FK-walking RLS on the child tables. Each walks up to the owning user_id.
alter table workouts enable row level security;
create policy "own_workouts" on workouts for all using (
  exists (select 1 from programs p where p.id = program_id and p.user_id = auth.uid())
) with check (
  exists (select 1 from programs p where p.id = program_id and p.user_id = auth.uid())
);

alter table workout_exercises enable row level security;
create policy "own_workout_exercises" on workout_exercises for all using (
  exists (
    select 1 from workouts w join programs p on p.id = w.program_id
    where w.id = workout_id and p.user_id = auth.uid())
) with check (
  exists (
    select 1 from workouts w join programs p on p.id = w.program_id
    where w.id = workout_id and p.user_id = auth.uid())
);

alter table set_specs enable row level security;
create policy "own_set_specs" on set_specs for all using (
  exists (
    select 1 from workout_exercises we
      join workouts w on w.id = we.workout_id
      join programs p on p.id = w.program_id
    where we.id = workout_exercise_id and p.user_id = auth.uid())
) with check (
  exists (
    select 1 from workout_exercises we
      join workouts w on w.id = we.workout_id
      join programs p on p.id = w.program_id
    where we.id = workout_exercise_id and p.user_id = auth.uid())
);

alter table session_sets enable row level security;
create policy "own_session_sets" on session_sets for all using (
  exists (select 1 from sessions s where s.id = session_id and s.user_id = auth.uid())
) with check (
  exists (select 1 from sessions s where s.id = session_id and s.user_id = auth.uid())
);

-- 5. Shared catalog readable by any authenticated client; writes locked down.
alter table exercises enable row level security;
create policy "read_exercises" on exercises for select using (true);

alter table variations enable row level security;
create policy "read_variations" on variations for select using (true);
