-- Workers' permits, IDs and site cards with an expiry date (the Malaysia,
-- UAE and UK apps): passport, PLKS, FOMEMA, CIDB Green Card, Emirates ID,
-- work permit, CSCS card. Same columns as the phone's worker_permits
-- table, in snake_case, so the site-execution sync mapper covers it.
--
-- Health results are never stored (a FOMEMA row holds its date only).
-- Numbers are optional; the app shows them in full only to the owner and
-- project managers.

create table if not exists worker_permits (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  worker_id uuid not null references workers(id) on delete cascade,
  kind text not null check (kind in ('passport', 'plks', 'fomema', 'green_card', 'emirates_id',
                                     'work_permit', 'cscs', 'other')),
  number text check (char_length(number) <= 40),
  expires_on timestamptz not null,
  note text check (char_length(note) <= 200),
  created_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  synced_at timestamptz not null default now(),
  unique (worker_id, kind)
);
create index if not exists worker_permits_project_idx on worker_permits (project_id);

-- The worker belongs to the same site as the permit; rows are added as
-- yourself.
create or replace function worker_permits_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' and new.created_by is distinct from (select auth.uid()) then
    raise exception 'Permits are added as yourself.' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and (new.created_by <> old.created_by or new.worker_id <> old.worker_id
                           or new.kind <> old.kind or new.project_id <> old.project_id) then
    raise exception 'A permit''s worker and kind cannot change.' using errcode = '42501';
  end if;
  if new.project_id <> (select w.project_id from workers w where w.id = new.worker_id) then
    raise exception 'The worker belongs to another site.' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function worker_permits_guard() from public, anon, authenticated;

drop trigger if exists worker_permits_stamp on worker_permits;
create trigger worker_permits_stamp before insert or update on worker_permits
  for each row execute function site_execution_stamp();
drop trigger if exists worker_permits_guard on worker_permits;
create trigger worker_permits_guard before insert or update on worker_permits
  for each row execute function worker_permits_guard();
drop trigger if exists worker_permits_log_sync_change on worker_permits;
create trigger worker_permits_log_sync_change after insert or update or delete on worker_permits
  for each row execute function log_sync_change();

alter table worker_permits enable row level security;
revoke all on table worker_permits from anon, authenticated;
grant select, insert, update on table worker_permits to authenticated;

drop policy if exists "site reads worker permits" on worker_permits;
create policy "site reads worker permits" on worker_permits for select
  to authenticated using ((select has_project_access(project_id)));
drop policy if exists "site adds worker permits" on worker_permits;
create policy "site adds worker permits" on worker_permits for insert
  to authenticated with check ((select has_project_access(project_id)));
drop policy if exists "site updates worker permits" on worker_permits;
create policy "site updates worker permits" on worker_permits for update
  to authenticated using ((select has_project_access(project_id)))
  with check ((select has_project_access(project_id)));
