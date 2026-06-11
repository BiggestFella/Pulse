-- Pulse folders (BAK-27): a generic container tree for the Library. Folders hold
-- workouts, programs, and sub-folders to arbitrary depth (adjacency list).
-- Deleting a folder cascade-deletes its sub-folders, workouts, and programs.

create table folders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  parent_folder_id uuid references folders(id) on delete cascade,  -- null = top level
  name text not null,
  color_token text not null,           -- FolderColor raw value: blue|orange|teal|yellow|pink|purple
  "order" int not null default 0,
  created_at timestamptz not null default now()
);

-- Organizing axis, orthogonal to workouts.program_id (which stays NOT NULL).
alter table workouts add column folder_id uuid references folders(id) on delete cascade;
alter table programs add column folder_id uuid references folders(id) on delete cascade;

-- RLS: owner-scoped, same pattern as programs/sessions/plan_entries.
alter table folders enable row level security;
create policy "own_folders" on folders
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
