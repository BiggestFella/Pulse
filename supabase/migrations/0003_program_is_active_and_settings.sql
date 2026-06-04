-- BAK-27: is_active on programs (one active program per user, enforced app-side)
-- and a per-user settings row.
alter table programs add column if not exists is_active boolean not null default false;

create table if not exists user_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  units text not null default 'kg',
  default_rest_seconds int not null default 90,
  auto_progress_weight boolean not null default false,
  sound_on_rest_end boolean not null default true
);
alter table user_settings enable row level security;
create policy "own_settings" on user_settings
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
