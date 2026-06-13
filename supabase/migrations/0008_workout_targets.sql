-- BAK-52: muscle Targets on a workout. Stored as a text[] of MuscleGroup raw
-- values ("Chest","Legs",…). Existing rows default to no targets.
alter table workouts add column targets text[] not null default '{}';
