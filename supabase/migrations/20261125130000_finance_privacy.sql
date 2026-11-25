-- Who sees the site's money (2026-11-25).
--
-- Before this, every member of a site read every expense. Now a site's
-- owner, project managers and accounts read all of them; anyone else
-- (engineers, storekeeper, security, quality, viewers) reads only the
-- entries they recorded themselves, so they still see their own petty
-- cash but not what was paid to vendors or what labour was paid. Money
-- received was already limited to owners and project managers.
--
-- Wage rates: only owners, project managers and accounts may set or change
-- workers.daily_wage; anyone else's write leaves the rate as it was (null
-- on a new worker), so a row sent by an older phone still saves.
--
-- Not done here, on purpose: hiding workers.daily_wage from reads. Phones
-- pull whole rows, so a column privilege would stop every phone not yet on
-- the new build from syncing workers. It follows once the old builds are
-- retired; until then the phone hides wages from these roles and the
-- server stops them setting any.

create or replace function can_see_site_money(p_project_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select coalesce(is_project_owner_or_pm(p_project_id), false)
      or coalesce(my_site_role(p_project_id) = 'accounts', false);
$$;
revoke all on function can_see_site_money(uuid) from public, anon;
grant execute on function can_see_site_money(uuid) to authenticated;

drop policy if exists "project members read expenses" on site_expenses;
drop policy if exists "money roles read expenses, others their own" on site_expenses;
create policy "money roles read expenses, others their own" on site_expenses for select
  to authenticated using (
    (select has_project_access(project_id))
    and ((select can_see_site_money(project_id)) or recorded_by = (select auth.uid())));

create or replace function workers_wage_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (select auth.uid()) is null or coalesce(can_see_site_money(new.project_id), false) then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.daily_wage := null;
  else
    new.daily_wage := old.daily_wage;
  end if;
  return new;
end $$;
revoke all on function workers_wage_guard() from public, anon, authenticated;

drop trigger if exists workers_wage_guard on workers;
create trigger workers_wage_guard before insert or update on workers
  for each row execute function workers_wage_guard();
