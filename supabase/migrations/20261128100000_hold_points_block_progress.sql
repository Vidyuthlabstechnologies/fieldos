-- Hold points hold: a task cannot move on while one on it is not released.
--
-- A hold point (an inspection that must be passed before work goes on, such
-- as rebar checked before concreting) only ever added a "waiting on" label to
-- the lookahead. Nothing stopped the task being marked in progress or done, so
-- the record a client's project-management consultant audits could show
-- concrete poured over a pending inspection.
--
-- Now, for people working through the API (the phone), a task cannot gain any
-- progress or become in progress / done while a hold point on it, or one that
-- a hold-point constraint on it waits for, is pending or rejected. Lowering
-- progress or reopening a task is not blocked. Admin tools and the server's
-- own functions are not held to it.
--
-- Also: the site's quality officer, the person who actually inspects, may
-- release a hold point, as well as the owner and project managers (before,
-- only they could, so the inspector could not sign off their own inspection).
--
-- Additive; the second function is the live one with that single rule changed.
-- Idempotent. Tested in supabase/tests/hold_points_test.sql.

create or replace function tasks_hold_point_guard()
returns trigger language plpgsql set search_path = public as $$
begin
  -- SECURITY INVOKER on purpose: in a definer function current_user is the
  -- function's owner, and this would never see an API caller. The caller reads
  -- the hold points of their own site through the normal policies.
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;
  if not (new.progress > old.progress
          or (new.status in ('in_progress', 'done') and new.status is distinct from old.status)) then
    return new;
  end if;
  if exists (select 1 from site_hold_points h where h.task_id = new.id and h.status <> 'released')
     or exists (select 1 from site_task_constraints c join site_hold_points h on h.id = c.link_id
                 where c.task_id = new.id and c.kind = 'hold_point' and c.cleared_at is null
                   and h.status <> 'released') then
    raise exception 'A hold point on this task is not released yet.' using errcode = '23514';
  end if;
  return new;
end $$;
revoke all on function tasks_hold_point_guard() from public, anon, authenticated;
drop trigger if exists tasks_hold_point_guard on tasks;
create trigger tasks_hold_point_guard before update on tasks
  for each row execute function tasks_hold_point_guard();

create or replace function public.site_execution_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      -- The person who inspects (the site's quality officer) decides a hold
      -- point as well as the owner and project managers.
      if not (manager or coalesce(my_site_role(new.project_id), '') = 'quality_officer')
         or new.decided_by is distinct from me then
        raise exception 'Only the owner, a project manager or the quality officer releases a hold point.' using errcode = '42501';
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
end $function$;
