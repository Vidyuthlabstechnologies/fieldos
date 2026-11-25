-- Step 1 of hiding workers.daily_wage from site members who may not see it
-- (2026-11-25). Additive and safe for every build in the field.
--
-- worker_wage_rates() returns the rate of every worker the caller may see
-- money for (site owner, project manager, accounts: can_see_site_money).
-- Builds from 1.8.1 pull workers WITHOUT the daily_wage column and read
-- the rates from here instead, so they keep working after step 2
-- (supabase/deferred/20261125150001_revoke_workers_wage_read.sql), which
-- takes the column's read privilege away. See docs/SUPABASE_PRODUCTION_RUNBOOK.md
-- "Wage rates: the two-step cut-over".

create or replace function worker_wage_rates()
returns table (worker_id uuid, daily_wage numeric)
language sql security definer set search_path = public stable as $$
  select w.id, w.daily_wage
    from workers w
   where has_project_access(w.project_id)
     and coalesce(can_see_site_money(w.project_id), false);
$$;
revoke all on function worker_wage_rates() from public, anon;
grant execute on function worker_wage_rates() to authenticated;
