-- Site notes (app schema v14). Onsite's reviews ask for a place to keep
-- notes per project: what was agreed with the client, measurements to
-- check, numbers to call. Everyone on the site can read and write them;
-- a note is changed or removed only by whoever wrote it or an owner/PM.
-- Removing sets deleted (pulls don't carry deletes), so no delete grant.

create table if not exists site_notes (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  body text not null check (length(btrim(body)) between 1 and 4000),
  pinned boolean not null default false,
  deleted boolean not null default false,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists site_notes_project_idx on site_notes (project_id, updated_at desc);

alter table site_notes enable row level security;
grant select, insert, update on site_notes to authenticated;

drop policy if exists "project members read site notes" on site_notes;
create policy "project members read site notes" on site_notes for select
  to authenticated using ((select has_project_access(project_id)));

drop policy if exists "project members write site notes as themselves" on site_notes;
create policy "project members write site notes as themselves" on site_notes for insert
  to authenticated with check (created_by = (select auth.uid()) and (select has_project_access(project_id)));

drop policy if exists "authors and owners change site notes" on site_notes;
create policy "authors and owners change site notes" on site_notes for update
  to authenticated
  using ((select has_project_access(project_id))
         and (created_by = (select auth.uid()) or (select is_project_owner_or_pm(project_id))))
  with check ((select has_project_access(project_id)));

-- A changed note stays on its site with its author and first date.
create or replace function site_notes_keep_origin()
returns trigger language plpgsql as $$
begin
  new.id := old.id;
  new.project_id := old.project_id;
  new.created_by := old.created_by;
  new.created_at := old.created_at;
  return new;
end $$;

drop trigger if exists site_notes_keep_origin on site_notes;
create trigger site_notes_keep_origin before update on site_notes
  for each row execute function site_notes_keep_origin();
