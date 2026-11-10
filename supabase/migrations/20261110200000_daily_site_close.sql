-- Daily site close (app schema v19, 2026-11-10).
--
-- If a supervisor forgets to update FieldOS, the manager must see "report
-- missing", never "zero activity": an empty attendance register could mean
-- nobody worked, or nobody submitted it.
--
-- 1. site_day_events: everything said about one site's day, insert-only
--    (no update or delete grant), so the record of who sent what, and when,
--    can't be rewritten from a phone. Kinds:
--      submitted    the supervisor sends the day, with the explicit
--                   "nothing" marks (no deliveries, no expenses, site closed)
--      reopened     taken back to add or correct something
--      miss_reason  why it was missed (forgot, poor signal, too much work)
--      follow_up    the manager followed up on a missing day
--      partial      an approver let the verified part of a weekly item go
--      override     an approver paid an item without its day reports, and why
--    work_date is the day the work happened; created_at is when it was
--    entered on the phone (it may sync hours later), synced_at when the
--    server got it.
--
-- 2. site_close_settings: one row per site (id = project id): the cutoff
--    time, the supervisor, and a backup supervisor with an end date. Only
--    the owner or a project manager changes it.
--
-- 3. member_sync_status: when each member's phone last reached the server,
--    stamped by the server. A report saved offline and a report never
--    written look the same until the phone reconnects; "last synced at
--    2:10 pm" is what lets the manager tell them apart. Not in the change
--    log (it changes every few minutes); phones read it directly.

create table if not exists site_day_events (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  work_date date not null,
  kind text not null check (kind in ('submitted', 'reopened', 'miss_reason', 'follow_up', 'partial', 'override')),
  site_closed boolean not null default false,
  no_deliveries boolean not null default false,
  no_expenses boolean not null default false,
  reason text check (reason in ('forgot', 'poor_signal', 'too_much_work', 'other')),
  note text check (char_length(note) <= 300),
  fingerprint text check (char_length(fingerprint) <= 200),
  amount numeric(14, 2),
  item_ref text check (char_length(item_ref) <= 160),
  recorded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  synced_at timestamptz not null default now(),
  check ((kind = 'miss_reason') = (reason is not null)),
  check (kind <> 'miss_reason' or reason <> 'other' or char_length(coalesce(note, '')) > 0),
  check (kind not in ('follow_up', 'override') or char_length(coalesce(note, '')) > 0),
  check ((kind in ('partial', 'override')) = (item_ref is not null)),
  -- A site can't be sent for a day more than a day ahead.
  check (work_date <= (created_at at time zone 'Asia/Kolkata')::date + 1)
);
create index if not exists site_day_events_day_idx on site_day_events (project_id, work_date, created_at);

alter table site_day_events enable row level security;
revoke all on table site_day_events from anon, authenticated;
grant select, insert on table site_day_events to authenticated;

drop policy if exists "site members read the daily close" on site_day_events;
create policy "site members read the daily close" on site_day_events for select
  to authenticated using ((select has_project_access(project_id)));

-- Anyone on the site sends, reopens and explains a day, as themselves;
-- following up, releasing and overriding are the owner's or a PM's.
drop policy if exists "day events are recorded as yourself, by the right role" on site_day_events;
create policy "day events are recorded as yourself, by the right role" on site_day_events for insert
  to authenticated with check (
    recorded_by = (select auth.uid())
    and (select has_project_access(project_id))
    and (kind in ('submitted', 'reopened', 'miss_reason') or (select is_project_owner_or_pm(project_id))));

-- Same rule as the weekly close: an event keeps the time it was made on
-- the phone (a report sent offline at 6 pm still reads 6 pm), but a phone
-- clock running ahead can't date it in the future.
create or replace function site_day_events_stamp()
returns trigger language plpgsql as $$
begin
  new.synced_at := now();
  if new.created_at is null or new.created_at > now() + interval '5 minutes' then
    new.created_at := now();
  end if;
  return new;
end $$;

drop trigger if exists site_day_events_stamp on site_day_events;
create trigger site_day_events_stamp before insert on site_day_events
  for each row execute function site_day_events_stamp();

create table if not exists site_close_settings (
  id uuid primary key references projects(id) on delete cascade,
  project_id uuid not null references projects(id) on delete cascade,
  cutoff_minutes integer not null default 1140 check (cutoff_minutes between 0 and 1439),
  supervisor_id uuid references auth.users(id),
  backup_id uuid references auth.users(id),
  backup_until date,
  updated_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  check (id = project_id),
  check (backup_id is not null or backup_until is null)
);

alter table site_close_settings enable row level security;
revoke all on table site_close_settings from anon, authenticated;
grant select, insert, update on table site_close_settings to authenticated;

drop policy if exists "site members read the close setup" on site_close_settings;
create policy "site members read the close setup" on site_close_settings for select
  to authenticated using ((select has_project_access(project_id)));
drop policy if exists "owner/pm set the close setup" on site_close_settings;
create policy "owner/pm set the close setup" on site_close_settings for insert
  to authenticated with check (updated_by = (select auth.uid()) and (select is_project_owner_or_pm(project_id)));
drop policy if exists "owner/pm change the close setup" on site_close_settings;
create policy "owner/pm change the close setup" on site_close_settings for update
  to authenticated using ((select is_project_owner_or_pm(project_id)))
  with check (updated_by = (select auth.uid()) and (select is_project_owner_or_pm(project_id)));

-- The supervisor and backup must belong to the site's company.
create or replace function site_close_settings_check()
returns trigger language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  select company_id into cid from projects where id = new.project_id;
  if new.supervisor_id is not null and not exists (
       select 1 from company_members where company_id = cid and user_id = new.supervisor_id) then
    raise exception 'The supervisor is not on this company';
  end if;
  if new.backup_id is not null and not exists (
       select 1 from company_members where company_id = cid and user_id = new.backup_id) then
    raise exception 'The backup supervisor is not on this company';
  end if;
  new.updated_at := now();
  return new;
end $$;
revoke all on function site_close_settings_check() from public, anon, authenticated;

drop trigger if exists site_close_settings_check on site_close_settings;
create trigger site_close_settings_check before insert or update on site_close_settings
  for each row execute function site_close_settings_check();

-- Both tables join the change log (20261110020000_incremental_sync.sql);
-- each carries project_id, so log_sync_change needs no new case.
drop trigger if exists site_day_events_log_sync_change on site_day_events;
create trigger site_day_events_log_sync_change after insert or update or delete on site_day_events
  for each row execute function log_sync_change();
drop trigger if exists site_close_settings_log_sync_change on site_close_settings;
create trigger site_close_settings_log_sync_change after insert or update or delete on site_close_settings
  for each row execute function log_sync_change();

create table if not exists member_sync_status (
  company_id uuid not null references companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  last_synced_at timestamptz not null default now(),
  pending_count integer not null default 0 check (pending_count >= 0),
  primary key (company_id, user_id)
);

alter table member_sync_status enable row level security;
revoke all on table member_sync_status from anon, authenticated;
grant select on table member_sync_status to authenticated;

drop policy if exists "members read when the team last synced" on member_sync_status;
create policy "members read when the team last synced" on member_sync_status for select
  to authenticated using ((select is_company_member(company_id)));

-- The only way in: the caller's own row, stamped with the server's clock.
create or replace function report_sync_status(p_company_id uuid, p_pending integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_company_member(p_company_id) then
    raise exception 'Not a member of this company' using errcode = '42501';
  end if;
  insert into member_sync_status (company_id, user_id, last_synced_at, pending_count)
  values (p_company_id, auth.uid(), now(), greatest(coalesce(p_pending, 0), 0))
  on conflict (company_id, user_id)
    do update set last_synced_at = now(), pending_count = greatest(coalesce(p_pending, 0), 0);
end $$;
revoke all on function report_sync_status(uuid, integer) from public, anon;
grant execute on function report_sync_status(uuid, integer) to authenticated;
