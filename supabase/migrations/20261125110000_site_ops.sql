-- Quality tests, safety breaches and the security gate (2026-11-25), with
-- two new site roles: security (the gate guard) and quality_officer.
-- Same columns as the phone's quality_tests, safety_breaches and
-- gate_checks tables, in snake_case, so the site-execution sync mapper
-- covers them.
--
-- Rules the server keeps, whatever the phone does:
--  - everything is entered as yourself, and a row's site and author never
--    change;
--  - a test's result follows from its required and actual values (a limit
--    is "at most", otherwise "at least") and is recorded once;
--  - a gate guard writes only gate records, and only gate guards and
--    managers write them; quality tests are not written by the gate;
--  - a breach is closed only by the owner or a project manager, with what
--    was done about it.

alter table project_members drop constraint if exists project_members_role_check;
alter table project_members add constraint project_members_role_check
  check (role in ('owner', 'project_manager', 'site_engineer', 'accounts', 'storekeeper', 'security', 'quality_officer', 'viewer'));

-- The caller's role on a site's roster, or null.
create or replace function my_site_role(p_project_id uuid)
returns text language sql security definer set search_path = public stable as $$
  select pm.role from project_members pm
   where pm.project_id = p_project_id and pm.user_id = (select auth.uid()) limit 1;
$$;
revoke all on function my_site_role(uuid) from public, anon;
grant execute on function my_site_role(uuid) to authenticated;

create table if not exists site_quality_tests (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  kind text not null check (kind in ('cube', 'plaster', 'paint', 'bitumen', 'other')),
  batch_no text check (char_length(batch_no) <= 60),
  element text check (char_length(element) <= 200),
  parameter text not null check (char_length(parameter) between 1 and 100),
  unit text check (char_length(unit) <= 20),
  rule text not null default 'min' check (rule in ('min', 'max')),
  required_value numeric(14, 3) not null check (required_value > 0),
  actual_value numeric(14, 3) check (actual_value >= 0),
  age_days int check (age_days between 1 and 365),
  sampled_on date not null,
  due_on date not null,
  tested_on date,
  result text not null default 'pending' check (result in ('pending', 'pass', 'fail')),
  officer text check (char_length(officer) <= 120),
  note text check (char_length(note) <= 300),
  raised_by uuid not null,
  tested_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  synced_at timestamptz not null default now()
);
create index if not exists site_quality_tests_project_idx on site_quality_tests (project_id);

create table if not exists site_safety_breaches (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  department text not null check (department in ('civil', 'electrical', 'plumbing', 'finishing', 'mep', 'security', 'other')),
  severity text not null default 'minor' check (severity in ('minor', 'major', 'critical')),
  description text not null check (char_length(description) between 1 and 500),
  who text check (char_length(who) <= 120),
  on_day date not null,
  action_taken text check (char_length(action_taken) <= 500),
  closed_at timestamptz,
  closed_by uuid,
  raised_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  synced_at timestamptz not null default now()
);
create index if not exists site_safety_breaches_project_idx on site_safety_breaches (project_id);

create table if not exists site_gate_checks (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  kind text not null check (kind in ('punch_in', 'punch_out', 'frisk', 'breath')),
  person_name text not null check (char_length(person_name) between 1 and 120),
  worker_id uuid,
  result text not null default 'ok' check (result in ('ok', 'flagged')),
  item text check (char_length(item) <= 120),
  reading numeric(6, 2) check (reading >= 0),
  note text check (char_length(note) <= 300),
  checked_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  synced_at timestamptz not null default now()
);
create index if not exists site_gate_checks_project_idx on site_gate_checks (project_id, created_at desc);

create or replace function site_quality_tests_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  me uuid := (select auth.uid());
  expected text;
begin
  if my_site_role(new.project_id) = 'security' then
    raise exception 'The gate does not record quality tests.' using errcode = '42501';
  end if;
  if tg_op = 'INSERT' then
    if new.raised_by is distinct from me then
      raise exception 'Tests are logged as yourself.' using errcode = '42501';
    end if;
    if new.result <> 'pending' or new.actual_value is not null or new.tested_by is not null then
      raise exception 'A new test waits for its result.' using errcode = '42501';
    end if;
  else
    if (new.project_id, new.raised_by, new.kind, new.required_value, new.rule, new.sampled_on)
       is distinct from (old.project_id, old.raised_by, old.kind, old.required_value, old.rule, old.sampled_on) then
      raise exception 'A test''s site, author and requirement cannot change.' using errcode = '42501';
    end if;
    if old.result <> 'pending' and (new.actual_value, new.result, new.tested_by) is distinct from (old.actual_value, old.result, old.tested_by) then
      raise exception 'A test result is recorded once.' using errcode = '42501';
    end if;
    if old.result = 'pending' and new.result <> 'pending' then
      if new.actual_value is null then
        raise exception 'A result needs the actual value.' using errcode = '42501';
      end if;
      if new.tested_by is distinct from me then
        raise exception 'Results are recorded as yourself.' using errcode = '42501';
      end if;
      expected := case when new.rule = 'max'
                       then case when new.actual_value <= new.required_value then 'pass' else 'fail' end
                       else case when new.actual_value >= new.required_value then 'pass' else 'fail' end end;
      if new.result <> expected then
        raise exception 'That result does not follow from the values.' using errcode = '42501';
      end if;
    end if;
  end if;
  return new;
end $$;
revoke all on function site_quality_tests_guard() from public, anon, authenticated;

create or replace function site_safety_breaches_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  me uuid := (select auth.uid());
begin
  if tg_op = 'INSERT' then
    if new.raised_by is distinct from me then
      raise exception 'Breaches are logged as yourself.' using errcode = '42501';
    end if;
    if new.closed_at is not null or new.closed_by is not null then
      raise exception 'A new breach is open.' using errcode = '42501';
    end if;
  else
    if new.project_id <> old.project_id or new.raised_by is distinct from old.raised_by
       or new.department <> old.department or new.on_day <> old.on_day or new.description <> old.description then
      raise exception 'What was logged cannot be rewritten.' using errcode = '42501';
    end if;
    if old.closed_at is not null and (new.closed_at, new.closed_by, new.action_taken) is distinct from (old.closed_at, old.closed_by, old.action_taken) then
      raise exception 'A closed breach stays closed.' using errcode = '42501';
    end if;
    if old.closed_at is null and new.closed_at is not null then
      if not coalesce(is_project_owner_or_pm(new.project_id), false) then
        raise exception 'Only the owner or a project manager closes a breach.' using errcode = '42501';
      end if;
      if new.closed_by is distinct from me or coalesce(new.action_taken, '') = '' then
        raise exception 'Close it as yourself, with what was done.' using errcode = '42501';
      end if;
    end if;
  end if;
  return new;
end $$;
revoke all on function site_safety_breaches_guard() from public, anon, authenticated;

create or replace function site_gate_checks_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  me uuid := (select auth.uid());
  r text := my_site_role(new.project_id);
  expected text;
begin
  if tg_op <> 'INSERT' then
    raise exception 'Gate records are never changed.' using errcode = '42501';
  end if;
  if r is not null and r not in ('security', 'owner', 'project_manager') and not coalesce(is_project_owner_or_pm(new.project_id), false) then
    raise exception 'Only the gate and the site''s managers keep the gate log.' using errcode = '42501';
  end if;
  if new.checked_by is distinct from me then
    raise exception 'Gate checks are logged as yourself.' using errcode = '42501';
  end if;
  expected := case
    when new.kind = 'frisk' and coalesce(new.item, '') <> '' then 'flagged'
    when new.kind = 'breath' and coalesce(new.reading, 0) > 0 then 'flagged'
    else 'ok' end;
  if new.kind = 'breath' and new.reading is null then
    raise exception 'A breath check needs its reading.' using errcode = '42501';
  end if;
  if new.result <> expected then
    raise exception 'That result does not follow from the check.' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function site_gate_checks_guard() from public, anon, authenticated;

do $$
declare
  t text;
begin
  foreach t in array array['site_quality_tests', 'site_safety_breaches', 'site_gate_checks'] loop
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
    execute format('drop policy if exists %I on %I', t || '_read', t);
    execute format('create policy %I on %I for select to authenticated using ((select has_project_access(project_id)))', t || '_read', t);
    execute format('drop policy if exists %I on %I', t || '_add', t);
    execute format('create policy %I on %I for insert to authenticated with check ((select has_project_access(project_id)))', t || '_add', t);
    execute format('drop policy if exists %I on %I', t || '_change', t);
    execute format('create policy %I on %I for update to authenticated using ((select has_project_access(project_id))) with check ((select has_project_access(project_id)))', t || '_change', t);
  end loop;
end $$;
