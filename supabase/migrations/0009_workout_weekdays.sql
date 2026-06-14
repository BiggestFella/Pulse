-- BAK-57: a workout recurs on multiple weekdays. Replace single `weekday` with
-- `weekdays int[]`, backfilling existing single-day workouts.
alter table workouts add column weekdays int[] not null default '{}';
update workouts set weekdays = array[weekday] where weekday is not null;
-- Restore the range constraint the old `weekday int check (weekday between 1 and 7)`
-- carried: every element must be a valid app weekday (1=Mon … 7=Sun). Empty = unscheduled.
alter table workouts add constraint weekdays_valid check (weekdays <@ array[1,2,3,4,5,6,7]);
alter table workouts drop column weekday;
