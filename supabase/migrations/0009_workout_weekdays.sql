-- BAK-57: a workout recurs on multiple weekdays. Replace single `weekday` with
-- `weekdays int[]`, backfilling existing single-day workouts.
alter table workouts add column weekdays int[] not null default '{}';
update workouts set weekdays = array[weekday] where weekday is not null;
alter table workouts drop column weekday;
