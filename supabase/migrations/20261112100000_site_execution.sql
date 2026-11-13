-- Site execution (app schema v40, 2026-11-11): FOS-205 to FOS-209.
--
--   FOS-205 two-week lookahead: site_task_constraints, what a task waits
--           for (material, a drawing, an RFI answer, a hold point ...).
--   FOS-206 drawing register: site_drawings and site_drawing_revisions
--           (only the latest approved revision is shown on site), and
--           site_rfis.
--   FOS-207 quality: site_hold_points (inspected and released before work
--           goes on) and site_defects (raised, fixed with a photo, checked
--           and closed by someone else), with site_execution_photos.
--   FOS-208 handover by unit/floor/zone: site_handover_units and
--           site_handover_checks.
--   FOS-209 company standards: company_standards (the hold points and
--           handover checklist every site gets).
--
-- Each column has the same name as on the phone in snake_case
-- (fieldos_mobile/lib/sync/site_execution_sync.dart).
--
-- Rules the server keeps, whatever a phone sends:
--  - Only the owner or a project manager approves a drawing revision,
--    releases a hold point, or hands a unit over.
--  - A revision's file, drawing and number never change after upload.
--  - A defect is marked fixed by the person fixing it, and closed by
--    someone else.
--  - A unit is not handed over while it has an open or unchecked defect,
--    a hold point not released, or a checklist line not done.
--  - Every "who did it" column is the signed-in user.
--  - created_at keeps the phone's time (never in the future); synced_at is
--    the server's clock.

-- --- Tables -------------------------------------------------------------------

create table if not exists site_task_constraints (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  task_id uuid not null,
  kind text not null check (kind in ('material', 'drawing', 'rfi', 'hold_point', 'labour', 'equipment', 'permit',
                                     'predecessor', 'other')),
  description text not null check (char_length(description) between 1 and 300),
  owner_id uuid,
  need_by date,
  link_id uuid,
  cleared_at timestamptz,
  cleared_by uuid,
  clear_note text check (char_length(clear_note) <= 300),
  raised_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  synced_at timestamptz not null default now()
);
create index if not exists site_task_constraints_project_idx on site_task_constraints (project_id);

create table if not exists site_drawings (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  number text not null check (char_length(number) between 1 and 40),
  title text not null check (char_length(title) between 1 and 200),
  discipline text not null default 'architectural'
    check (discipline in ('architectural', 'structural', 'mep', 'landscape', 'other')),
  created_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  synced_at timestamptz not null default now()
);
create unique index if not exists site_drawings_number_idx on site_drawings (project_id, lower(number));

create table if not exists site_drawing_revisions (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  drawing_id uuid not null references site_drawings(id) on delete cascade,
  rev text not null check (char_length(rev) between 1 and 10),
  file_path text not null check (char_length(file_path) <= 300 and split_part(file_path, '/', 1) = project_id::text),
  mime_type text not null check (char_length(mime_type) <= 100),
  note text check (char_length(note) <= 300),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  decided_by uuid,
  decided_at timestamptz,
  decision_note text check (char_length(decision_note) <= 300),
  uploaded_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  synced_at timestamptz not null default now()
);
create unique index if not exists site_drawing_revisions_rev_idx on site_drawing_revisions (drawing_id, lower(rev));
create index if not exists site_drawing_revisions_project_idx on site_drawing_revisions (project_id);

create table if not exists site_rfis (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  question text not null check (char_length(question) between 1 and 1000),
  drawing_id uuid references site_drawings(id) on delete set null,
  task_id uuid,
  assignee_id uuid,
  asked_of text check (char_length(asked_of) <= 120),
  due_on date,
  answer text check (char_length(answer) <= 1000),
  answered_by uuid,
  answered_at timestamptz,
  status text not null default 'open' check (status in ('open', 'answered', 'closed')),
  raised_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  synced_at timestamptz not null default now()
);
create index if not exists site_rfis_project_idx on site_rfis (project_id);

create table if not exists site_handover_units (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  block text check (char_length(block) <= 60),
  floor text check (char_length(floor) <= 30),
  name text not null check (char_length(name) between 1 and 60),
  handed_to text check (char_length(handed_to) <= 120),
  handed_over_at timestamptz,
  handed_over_by uuid,
  handover_note text check (char_length(handover_note) <= 300),
  created_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  synced_at timestamptz not null default now()
);
create index if not exists site_handover_units_project_idx on site_handover_units (project_id);

create table if not exists site_handover_checks (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  unit_id uuid not null references site_handover_units(id) on delete cascade,
  item text not null check (char_length(item) between 1 and 200),
  done boolean not null default false,
  done_by uuid,
  done_at timestamptz,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  synced_at timestamptz not null default now()
);
create index if not exists site_handover_checks_unit_idx on site_handover_checks (unit_id);

create table if not exists site_hold_points (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 200),
  task_id uuid,
  unit_id uuid references site_handover_units(id) on delete set null,
  location text check (char_length(location) <= 120),
  status text not null default 'pending' check (status in ('pending', 'released', 'rejected')),
  decided_by uuid,
  decided_at timestamptz,
  note text check (char_length(note) <= 300),
  raised_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  synced_at timestamptz not null default now()
);
create index if not exists site_hold_points_project_idx on site_hold_points (project_id);

create table if not exists site_defects (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  unit_id uuid references site_handover_units(id) on delete set null,
  location text check (char_length(location) <= 120),
  description text not null check (char_length(description) between 1 and 500),
  severity text not null default 'minor' check (severity in ('minor', 'major', 'critical')),
  assignee_id uuid,
  subcontractor_id uuid references subcontractors(id) on delete set null,
  due_on date,
  status text not null default 'open' check (status in ('open', 'fixed', 'closed')),
  fixed_by uuid,
  fixed_at timestamptz,
  fix_note text check (char_length(fix_note) <= 300),
  closed_by uuid,
  closed_at timestamptz,
  reopen_count int not null default 0 check (reopen_count >= 0),
  raised_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  synced_at timestamptz not null default now()
);
create index if not exists site_defects_project_idx on site_defects (project_id);

create table if not exists site_execution_photos (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  parent_kind text not null check (parent_kind in ('defect', 'defect_fix', 'hold_point', 'rfi')),
  parent_id uuid not null,
  file_path text not null check (char_length(file_path) <= 300 and split_part(file_path, '/', 1) = project_id::text),
  mime_type text not null check (char_length(mime_type) <= 100),
  uploaded_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  synced_at timestamptz not null default now()
);
create index if not exists site_execution_photos_parent_idx on site_execution_photos (parent_id);
create index if not exists site_execution_photos_project_idx on site_execution_photos (project_id);

create table if not exists company_standards (
  id uuid primary key,
  company_id uuid not null references companies(id) on delete cascade,
  kind text not null check (kind in ('hold_point', 'handover_check')),
  item text not null check (char_length(item) between 1 and 200),
  sort_order int not null default 0,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  synced_at timestamptz not null default now()
);
create index if not exists company_standards_company_idx on company_standards (company_id);

-- --- Times -------------------------------------------------------------------

create or replace function site_execution_stamp()
returns trigger language plpgsql as $$
begin
  new.synced_at := now();
  if tg_op = 'UPDATE' then
    new.created_at := old.created_at;
  elsif new.created_at is null or new.created_at > now() + interval '5 minutes' then
    new.created_at := now();
  end if;
  if new.updated_at is null or new.updated_at > now() + interval '5 minutes' then
    new.updated_at := now();
  end if;
  return new;
end $$;

-- --- Rules -------------------------------------------------------------------

create or replace function site_execution_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  manager boolean := false;
  n int;
begin
  -- company_standards has no project_id, and plpgsql does not short-circuit
  -- a field reference, so the project checks sit in their own block.
  if tg_table_name <> 'company_standards' then
    manager := coalesce(is_project_owner_or_pm(new.project_id), false);
    if tg_op = 'UPDATE' then
      if new.project_id <> old.project_id then
        raise exception 'A record cannot move to another site.' using errcode = '42501';
      end if;
    end if;
  end if;

  -- Who raised, added or uploaded a record never changes, so a decision
  -- rule keyed on a person cannot be dodged by rewriting who that was.
  if tg_op = 'UPDATE' and (
       (to_jsonb(new) ->> 'raised_by') is distinct from (to_jsonb(old) ->> 'raised_by')
       or (to_jsonb(new) ->> 'created_by') is distinct from (to_jsonb(old) ->> 'created_by')
       or (to_jsonb(new) ->> 'uploaded_by') is distinct from (to_jsonb(old) ->> 'uploaded_by')) then
    raise exception 'Who raised a record cannot change.' using errcode = '42501';
  end if;

  case tg_table_name
  when 'site_task_constraints' then
    if tg_op = 'INSERT' and new.raised_by is distinct from me then
      raise exception 'Constraints are raised as yourself.' using errcode = '42501';
    end if;
    if new.cleared_at is not null and (tg_op = 'INSERT' or old.cleared_at is null) and new.cleared_by is distinct from me then
      raise exception 'Constraints are cleared as yourself.' using errcode = '42501';
    end if;
    if tg_op = 'UPDATE' and old.cleared_at is not null
       and (new.cleared_at is distinct from old.cleared_at or new.cleared_by is distinct from old.cleared_by) then
      raise exception 'A cleared constraint stays cleared as it was.' using errcode = '42501';
    end if;

  when 'site_drawings' then
    if tg_op = 'INSERT' and new.created_by is distinct from me then
      raise exception 'Drawings are added as yourself.' using errcode = '42501';
    end if;

  when 'site_drawing_revisions' then
    if tg_op = 'INSERT' then
      if new.uploaded_by is distinct from me then
        raise exception 'Revisions are uploaded as yourself.' using errcode = '42501';
      end if;
      if new.status <> 'pending' and not manager then
        raise exception 'Only the owner or a project manager approves a drawing.' using errcode = '42501';
      end if;
      if new.project_id <> (select d.project_id from site_drawings d where d.id = new.drawing_id) then
        raise exception 'The revision belongs to another site''s drawing.' using errcode = '42501';
      end if;
    else
      if new.file_path <> old.file_path or new.drawing_id <> old.drawing_id or new.rev <> old.rev
         or new.uploaded_by <> old.uploaded_by then
        raise exception 'A revision''s file and number cannot change. Upload a new revision.' using errcode = '42501';
      end if;
      if new.status <> old.status then
        if old.status <> 'pending' then
          raise exception 'This revision has already been decided.' using errcode = '42501';
        end if;
        if not manager or new.decided_by is distinct from me then
          raise exception 'Only the owner or a project manager approves a drawing.' using errcode = '42501';
        end if;
      elsif new.decided_by is distinct from old.decided_by or new.decided_at is distinct from old.decided_at then
        raise exception 'This revision has already been decided.' using errcode = '42501';
      end if;
    end if;

  when 'site_rfis' then
    if tg_op = 'INSERT' and new.raised_by is distinct from me then
      raise exception 'RFIs are raised as yourself.' using errcode = '42501';
    end if;
    if new.answer is not null and (tg_op = 'INSERT' or old.answer is distinct from new.answer)
       and new.answered_by is distinct from me then
      raise exception 'RFIs are answered as yourself.' using errcode = '42501';
    end if;
    if tg_op = 'UPDATE' and new.answer is not distinct from old.answer
       and new.answered_by is distinct from old.answered_by then
      raise exception 'RFIs are answered as yourself.' using errcode = '42501';
    end if;

  when 'site_hold_points' then
    if tg_op = 'INSERT' and new.raised_by is distinct from me then
      raise exception 'Hold points are raised as yourself.' using errcode = '42501';
    end if;
    if (tg_op = 'INSERT' and new.status <> 'pending')
       or (tg_op = 'UPDATE' and new.status <> old.status) then
      if tg_op = 'UPDATE' and old.status = 'released' then
        raise exception 'This hold point is already released.' using errcode = '42501';
      end if;
      if not manager or new.decided_by is distinct from me then
        raise exception 'Only the owner or a project manager releases a hold point.' using errcode = '42501';
      end if;
    elsif tg_op = 'UPDATE' and new.decided_by is distinct from old.decided_by then
      raise exception 'Only the owner or a project manager releases a hold point.' using errcode = '42501';
    end if;

  when 'site_defects' then
    if tg_op = 'INSERT' then
      if new.raised_by is distinct from me then
        raise exception 'Defects are raised as yourself.' using errcode = '42501';
      end if;
      if new.status <> 'open' then
        raise exception 'A defect starts open.' using errcode = '42501';
      end if;
    elsif new.status <> old.status then
      if old.status = 'open' and new.status = 'fixed' then
        if new.fixed_by is distinct from me then
          raise exception 'A defect is marked fixed as yourself.' using errcode = '42501';
        end if;
      elsif old.status = 'fixed' and new.status = 'closed' then
        if new.closed_by is distinct from me or new.closed_by = old.fixed_by
           or new.fixed_by is distinct from old.fixed_by then
          raise exception 'Someone other than the person who fixed it checks the fix.' using errcode = '42501';
        end if;
      elsif old.status = 'fixed' and new.status = 'open' then
        if me = old.fixed_by then
          raise exception 'Someone other than the person who fixed it checks the fix.' using errcode = '42501';
        end if;
      else
        raise exception 'A defect goes open, fixed, then closed.' using errcode = '42501';
      end if;
    elsif new.fixed_by is distinct from old.fixed_by or new.closed_by is distinct from old.closed_by then
      -- Otherwise the fixer could name someone else as the fixer and then
      -- close their own fix.
      raise exception 'Someone other than the person who fixed it checks the fix.' using errcode = '42501';
    end if;

  when 'site_handover_checks' then
    if new.done and (tg_op = 'INSERT' or not old.done) and new.done_by is distinct from me then
      raise exception 'Checks are ticked as yourself.' using errcode = '42501';
    end if;
    if tg_op = 'UPDATE' and new.done = old.done and new.done_by is distinct from old.done_by then
      raise exception 'Checks are ticked as yourself.' using errcode = '42501';
    end if;
    if tg_op = 'UPDATE' and old.done is distinct from new.done
       and (select u.handed_over_at from site_handover_units u where u.id = new.unit_id) is not null then
      raise exception 'This unit is already handed over.' using errcode = '42501';
    end if;

  when 'site_handover_units' then
    if tg_op = 'INSERT' and new.created_by is distinct from me then
      raise exception 'Units are added as yourself.' using errcode = '42501';
    end if;
    if tg_op = 'UPDATE' and old.handed_over_at is not null
       and (new.handed_over_at is distinct from old.handed_over_at or new.handed_to is distinct from old.handed_to
            or new.handed_over_by is distinct from old.handed_over_by) then
      raise exception 'This unit is already handed over.' using errcode = '42501';
    end if;
    if new.handed_over_at is not null and (tg_op = 'INSERT' or old.handed_over_at is null) then
      if not manager or new.handed_over_by is distinct from me then
        raise exception 'Only the owner or a project manager hands a unit over.' using errcode = '42501';
      end if;
      select count(*) into n from site_defects d where d.unit_id = new.id and d.status <> 'closed';
      if n > 0 then
        raise exception 'This unit has % defects not closed.', n using errcode = '23514';
      end if;
      select count(*) into n from site_hold_points h where h.unit_id = new.id and h.status <> 'released';
      if n > 0 then
        raise exception 'This unit has % hold points not released.', n using errcode = '23514';
      end if;
      select count(*) into n from site_handover_checks c where c.unit_id = new.id and not c.done;
      if n > 0 then
        raise exception 'This unit has % checklist lines not done.', n using errcode = '23514';
      end if;
    end if;

  when 'site_execution_photos' then
    -- Evidence: added as yourself, never edited afterwards.
    if tg_op = 'INSERT' then
      new.uploaded_by := me;
    else
      raise exception 'A photo cannot be changed. Add a new one.' using errcode = '42501';
    end if;

  when 'company_standards' then
    if not coalesce(is_company_owner_or_pm(new.company_id), false) then
      raise exception 'Only the owner or a project manager sets company standards.' using errcode = '42501';
    end if;
  else
    null;
  end case;
  return new;
end $$;
revoke all on function site_execution_guard() from public, anon, authenticated;

do $$
declare t text;
begin
  foreach t in array array['site_task_constraints', 'site_drawings', 'site_drawing_revisions', 'site_rfis',
                           'site_hold_points', 'site_defects', 'site_execution_photos', 'site_handover_units',
                           'site_handover_checks', 'company_standards'] loop
    execute format('drop trigger if exists %I on %I', t || '_stamp', t);
    execute format('create trigger %I before insert or update on %I for each row execute function site_execution_stamp()',
                   t || '_stamp', t);
    execute format('drop trigger if exists %I on %I', t || '_guard', t);
    execute format('create trigger %I before insert or update on %I for each row execute function site_execution_guard()',
                   t || '_guard', t);
    execute format('drop trigger if exists %I on %I', t || '_log_sync_change', t);
    execute format('create trigger %I after insert or update or delete on %I for each row execute function log_sync_change()',
                   t || '_log_sync_change', t);
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on table %I from anon, authenticated', t);
  end loop;
end $$;

-- --- Access --------------------------------------------------------------------
-- The site team reads and writes its site's records; the guard above keeps
-- the decisions with the owner or a project manager. Nothing is deleted
-- except a company standard (by the owner or a PM) and a photo (by its
-- uploader or the owner or a PM).

do $$
declare t text;
begin
  foreach t in array array['site_task_constraints', 'site_drawings', 'site_drawing_revisions', 'site_rfis',
                           'site_hold_points', 'site_defects', 'site_execution_photos', 'site_handover_units',
                           'site_handover_checks'] loop
    execute format('grant select, insert, update on table %I to authenticated', t);
    execute format('drop policy if exists %I on %I', 'site reads ' || t, t);
    execute format('create policy %I on %I for select to authenticated using ((select has_project_access(project_id)))',
                   'site reads ' || t, t);
    execute format('drop policy if exists %I on %I', 'site adds ' || t, t);
    execute format('create policy %I on %I for insert to authenticated with check ((select has_project_access(project_id)))',
                   'site adds ' || t, t);
    execute format('drop policy if exists %I on %I', 'site updates ' || t, t);
    execute format('create policy %I on %I for update to authenticated using ((select has_project_access(project_id)))'
                   ' with check ((select has_project_access(project_id)))', 'site updates ' || t, t);
  end loop;
end $$;

grant delete on table site_execution_photos to authenticated;
drop policy if exists "uploader or owner/pm removes execution photos" on site_execution_photos;
create policy "uploader or owner/pm removes execution photos" on site_execution_photos for delete
  to authenticated using (uploaded_by = (select auth.uid()) or coalesce((select is_project_owner_or_pm(project_id)), false));

grant select, insert, update, delete on table company_standards to authenticated;
drop policy if exists "company reads its standards" on company_standards;
create policy "company reads its standards" on company_standards for select
  to authenticated using ((select is_company_member(company_id)));
drop policy if exists "owner/pm set standards" on company_standards;
create policy "owner/pm set standards" on company_standards for insert
  to authenticated with check (coalesce((select is_company_owner_or_pm(company_id)), false));
drop policy if exists "owner/pm edit standards" on company_standards;
create policy "owner/pm edit standards" on company_standards for update
  to authenticated using (coalesce((select is_company_owner_or_pm(company_id)), false))
  with check (coalesce((select is_company_owner_or_pm(company_id)), false));
drop policy if exists "owner/pm remove standards" on company_standards;
create policy "owner/pm remove standards" on company_standards for delete
  to authenticated using (coalesce((select is_company_owner_or_pm(company_id)), false));
