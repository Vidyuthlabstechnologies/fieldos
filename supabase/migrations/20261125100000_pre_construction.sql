-- Pre-construction tracker (2026-11-25): the approvals and clearances a site
-- waits for (GHMC, Fire NOC and so on), and the time and money spent
-- chasing them. Same columns as the phone's site_approvals and
-- liaison_logs tables, in snake_case, so the site-execution sync mapper
-- covers both.
--
-- Rules the server keeps, whatever the phone does:
--  - an approval is raised as yourself; its site and who raised it never
--    change; its history only grows; a closed (approved or rejected)
--    approval is never reopened;
--  - liaison time and cost are the firm's own, so only the owner and the
--    site's project managers read or write them (the same people who see
--    money received), and a log is entered as yourself.

create table if not exists site_approvals (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  authority text not null default 'other'
    check (authority in ('ghmc', 'hmda', 'municipality', 'fire', 'pollution', 'electricity', 'water', 'rera', 'airport', 'other')),
  title text not null check (char_length(title) between 1 and 200),
  reference_no text check (char_length(reference_no) <= 60),
  status text not null default 'not_started'
    check (status in ('not_started', 'drafting', 'applied', 'query_raised', 'resubmitted', 'approved', 'rejected')),
  waiting_on text not null default 'us' check (waiting_on in ('us', 'consultant', 'authority', 'client')),
  applied_on date,
  expected_by date,
  approved_on date,
  valid_until date,
  liaison_by text check (char_length(liaison_by) <= 120),
  note text check (char_length(note) <= 1000),
  history text not null default '' check (char_length(history) <= 8000),
  raised_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  synced_at timestamptz not null default now()
);
create index if not exists site_approvals_project_idx on site_approvals (project_id);

create table if not exists site_liaison_logs (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  approval_id uuid references site_approvals(id) on delete set null,
  on_day date not null,
  minutes int not null default 0 check (minutes between 0 and 1440),
  person text check (char_length(person) <= 120),
  cost numeric(14, 2) not null default 0 check (cost >= 0),
  note text check (char_length(note) <= 300),
  logged_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  synced_at timestamptz not null default now()
);
create index if not exists site_liaison_logs_project_idx on site_liaison_logs (project_id);

create or replace function site_approvals_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  me uuid := (select auth.uid());
begin
  if tg_op = 'INSERT' then
    if new.raised_by is distinct from me then
      raise exception 'Approvals are raised as yourself.' using errcode = '42501';
    end if;
    if new.status <> 'not_started' or new.history <> '' or new.approved_on is not null then
      raise exception 'A new approval starts as not started.' using errcode = '42501';
    end if;
  else
    if new.project_id <> old.project_id or new.raised_by is distinct from old.raised_by then
      raise exception 'Who raised an approval, and its site, cannot change.' using errcode = '42501';
    end if;
    if left(new.history, char_length(old.history)) <> old.history
       and char_length(old.history) < 7000 then
      raise exception 'An approval''s history is never rewritten.' using errcode = '42501';
    end if;
    if old.status in ('approved', 'rejected') and new.status is distinct from old.status then
      raise exception 'A closed approval is not reopened; raise a new one.' using errcode = '42501';
    end if;
    if new.status = 'approved' and new.approved_on is null then
      raise exception 'An approval needs the day it was granted.' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
revoke all on function site_approvals_guard() from public, anon, authenticated;

create or replace function site_liaison_logs_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  me uuid := (select auth.uid());
begin
  if tg_op = 'INSERT' then
    if new.logged_by is distinct from me then
      raise exception 'Liaison time is logged as yourself.' using errcode = '42501';
    end if;
  elsif new.project_id <> old.project_id or new.logged_by is distinct from old.logged_by then
    raise exception 'Who logged liaison time, and its site, cannot change.' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function site_liaison_logs_guard() from public, anon, authenticated;

do $$
declare
  t text;
begin
  foreach t in array array['site_approvals', 'site_liaison_logs'] loop
    execute format('drop trigger if exists %I on %I', t || '_stamp', t);
    execute format('create trigger %I before insert or update on %I for each row execute function site_execution_stamp()', t || '_stamp', t);
    execute format('drop trigger if exists %I on %I', t || '_guard', t);
    execute format('create trigger %I before insert or update on %I for each row execute function %I()', t || '_guard', t, t || '_guard');
    execute format('drop trigger if exists %I on %I', t || '_log_sync_change', t);
    execute format('create trigger %I after insert or update or delete on %I for each row execute function log_sync_change()', t || '_log_sync_change', t);
    execute format('drop trigger if exists %I on %I', t || '_site_viewer_read_only', t);
    execute format('create trigger %I before insert or update or delete on %I for each row execute function site_viewer_read_only()', t || '_site_viewer_read_only', t);
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on table %I from anon, authenticated', t);
    execute format('grant select, insert, update on table %I to authenticated', t);
  end loop;
end $$;

drop policy if exists "site reads approvals" on site_approvals;
create policy "site reads approvals" on site_approvals for select
  to authenticated using ((select has_project_access(project_id)));
drop policy if exists "site adds approvals" on site_approvals;
create policy "site adds approvals" on site_approvals for insert
  to authenticated with check ((select has_project_access(project_id)));
drop policy if exists "site updates approvals" on site_approvals;
create policy "site updates approvals" on site_approvals for update
  to authenticated using ((select has_project_access(project_id)))
  with check ((select has_project_access(project_id)));

drop policy if exists "managers read liaison logs" on site_liaison_logs;
create policy "managers read liaison logs" on site_liaison_logs for select
  to authenticated using (coalesce((select is_project_owner_or_pm(project_id)), false));
drop policy if exists "managers add liaison logs" on site_liaison_logs;
create policy "managers add liaison logs" on site_liaison_logs for insert
  to authenticated with check (coalesce((select is_project_owner_or_pm(project_id)), false));
drop policy if exists "managers change liaison logs" on site_liaison_logs;
create policy "managers change liaison logs" on site_liaison_logs for update
  to authenticated using (coalesce((select is_project_owner_or_pm(project_id)), false))
  with check (coalesce((select is_project_owner_or_pm(project_id)), false));
