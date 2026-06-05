-- BAK-27: record which variation each logged set was performed with.
-- The variation is the unit users log and view; the parent exercise is grouping.
-- Nullable for back-compat, but the app always sets it going forward.
alter table session_sets
  add column if not exists variation_id uuid references variations(id);
