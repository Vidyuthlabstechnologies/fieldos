-- The company plan's site limit, enforced by the server across ALL of the
-- company's sites (supabase/migrations/20261111130000_company_plans.sql set
-- the limit, but only the phone checked it, and only against the sites that
-- phone knew of; two phones, or one phone that had not pulled yet, could go
-- past it).
--
-- "Active site" is the same as company_active_sites(): a project whose
-- status is not 'completed' (planning, active and on hold all count). The
-- limit is the one company_plan_now() picks for today (several rows: the
-- biggest limit wins, null = no limit). No plan covering today = no limit
-- (the store subscription has no site limit).
--
-- Refused: a new active project, or a project moving INTO active (reopened
-- from completed, or moved to this company) when the company already has
-- that many active sites. Never refused: a change to a project that was
-- already active in the company, so a company that is over its limit
-- (the team lowered it, or older rows) can still edit, pause or finish its
-- sites; completing a site always works.
--
-- The error is SQLSTATE P0001 with a message starting 'site_limit_reached'
-- and the numbers, e.g. 'site_limit_reached: limit 3, active 3'. The phone's
-- sync engine (lib/sync/sync_engine.dart) parks such a write at once with
-- the plain site-limit message instead of retrying it.
--
-- Test: supabase/tests/company_plans_test.sql.

create or replace function public.enforce_company_site_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limit integer;
  v_active integer;
begin
  -- Not becoming an active site: nothing to check.
  if new.company_id is null or new.status is null or new.status = 'completed' then
    return new;
  end if;
  if tg_op = 'UPDATE' then
    -- Already an active site of this company: not a new one.
    if old.company_id = new.company_id and old.status <> 'completed' then
      return new;
    end if;
  elsif exists (select 1 from projects p where p.id = new.id) then
    -- An upsert, or a replayed insert, of a row that is already there: the
    -- insert itself will not happen (ON CONFLICT DO UPDATE runs the update
    -- check above; a plain insert fails on the duplicate id).
    return new;
  end if;

  select n.site_limit into v_limit from public.company_plan_now(new.company_id) n;
  if v_limit is null then
    return new;
  end if;

  -- One check at a time per company, so two phones can't both take the last
  -- site.
  perform pg_advisory_xact_lock(hashtextextended('site_limit:' || new.company_id::text, 0));
  v_active := public.company_active_sites(new.company_id);
  if v_active >= v_limit then
    raise exception 'site_limit_reached: limit %, active %', v_limit, v_active
      using errcode = 'P0001',
            hint = 'Mark a finished site Completed, or add sites to the company plan.';
  end if;
  return new;
end;
$$;

revoke all on function public.enforce_company_site_limit() from public, anon, authenticated;

drop trigger if exists projects_site_limit on public.projects;
create trigger projects_site_limit
  before insert or update of status, company_id on public.projects
  for each row execute function public.enforce_company_site_limit();
