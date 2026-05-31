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

-- DEFERRED to the data-layer feature (BAK-6): the child tables (workouts,
-- workout_exercises, set_specs, session_sets) own data only via parent FKs and
-- still need RLS + policies that walk the FK up to the owning user_id, e.g.:
--   alter table session_sets enable row level security;
--   create policy "own_session_sets" on session_sets for all using (
--     exists (select 1 from sessions s where s.id = session_id and s.user_id = auth.uid()));
-- The shared catalog (exercises, variations) needs an explicit read policy
-- (e.g. for select using (true)) or it will be unreadable via the API.
-- Until then these tables are deny-all to API clients (RLS disabled = no access).
