-- BAK-63: per-workout settings — a rest-timer override and freeform notes.
alter table workouts add column rest_seconds int
  check (rest_seconds is null or rest_seconds between 15 and 600);
alter table workouts add column notes text not null default '';
