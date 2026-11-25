-- On-site verification before a task reaches 100% (2026-11-25).
--
-- A task marked verify_required (the stage checklists set it) can be marked
-- done, or taken to 100%, only after someone has recorded a check for it:
-- the position the phone had when they said it was done. The owner and a
-- site's project managers are exempt. Whoever is not a manager also cannot
-- switch the requirement off again.
--
-- The server cannot see where a phone really is; what it keeps is that a
-- check exists, is entered as yourself, and is never rewritten, so
-- "marked done without being on site" leaves a visible trail.

alter table tasks add column if not exists verify_required boolean not null default false;

create table if not exists site_task_checks (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  task_id uuid not null references tasks(id) on delete cascade,
  lat double precision not null check (lat between -90 and 90),
  lng double precision not null check (lng between -180 and 180),
  accuracy_m double precision check (accuracy_m >= 0),
  distance_m double precision check (distance_m >= 0),
  note text check (char_length(note) <= 300),
  checked_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  synced_at timestamptz not null default now()
);
create index if not exists site_task_checks_task_idx on site_task_checks (task_id);
create index if not exists site_task_checks_project_idx on site_task_checks (project_id);

create or replace function site_task_checks_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op <> 'INSERT' then
    raise exception 'A site check is never changed.' using errcode = '42501';
  end if;
  if new.checked_by is distinct from (select auth.uid()) then
    raise exception 'Site checks are recorded as yourself.' using errcode = '42501';
  end if;
  if not exists (select 1 from tasks t where t.id = new.task_id and t.project_id = new.project_id) then
    raise exception 'That task is not on this site.' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function site_task_checks_guard() from public, anon, authenticated;

create or replace function tasks_verify_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  manager boolean := coalesce(is_project_owner_or_pm(new.project_id), false);
  finishing boolean;
begin
  if (select auth.uid()) is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.verify_required and not new.verify_required and not manager then
    new.verify_required := true;
  end if;
  if new.verify_required and not manager then
    finishing := (new.status = 'done' or coalesce(new.progress, 0) >= 100)
                 and (tg_op = 'INSERT' or (old.status <> 'done' and coalesce(old.progress, 0) < 100));
    if finishing and not exists (select 1 from site_task_checks c where c.task_id = new.id) then
      raise exception 'Verify this task on site before marking it done.' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
revoke all on function tasks_verify_guard() from public, anon, authenticated;

drop trigger if exists tasks_verify_guard on tasks;
create trigger tasks_verify_guard before insert or update on tasks
  for each row execute function tasks_verify_guard();

drop trigger if exists site_task_checks_stamp on site_task_checks;
create trigger site_task_checks_stamp before insert or update on site_task_checks
  for each row execute function site_execution_stamp();
drop trigger if exists site_task_checks_guard on site_task_checks;
create trigger site_task_checks_guard before insert or update on site_task_checks
  for each row execute function site_task_checks_guard();
drop trigger if exists site_task_checks_log_sync_change on site_task_checks;
create trigger site_task_checks_log_sync_change after insert or update or delete on site_task_checks
  for each row execute function log_sync_change();
drop trigger if exists site_task_checks_site_viewer_read_only on site_task_checks;
create trigger site_task_checks_site_viewer_read_only before insert or update or delete on site_task_checks
  for each row execute function site_viewer_read_only();

alter table site_task_checks enable row level security;
revoke all on table site_task_checks from anon, authenticated;
grant select, insert on table site_task_checks to authenticated;
drop policy if exists "site reads task checks" on site_task_checks;
create policy "site reads task checks" on site_task_checks for select
  to authenticated using ((select has_project_access(project_id)));
drop policy if exists "site adds task checks" on site_task_checks;
create policy "site adds task checks" on site_task_checks for insert
  to authenticated with check ((select has_project_access(project_id)));
