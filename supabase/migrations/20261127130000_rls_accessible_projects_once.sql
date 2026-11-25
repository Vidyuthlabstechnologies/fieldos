-- Row-level security that costs the same however many other companies there are.
--
-- Found on 26 Nov 2026 while testing against a local database holding about
-- 9,800 tasks: a plain `select count(*) from tasks` as the owner of a company
-- with 1,200 of them took 7.7 seconds, almost the 8-second API cap, and the
-- app's paged pull timed out. Cause: 161 policies say
--     (select has_project_access(<table>.project_id))
-- which runs six lookups for EVERY row Postgres scans, including every other
-- company's rows, about 0.7 ms each. A pull therefore costs time in
-- proportion to the whole table, not to the user's own data. Production holds
-- 2 projects today, so nobody has hit it; a few dozen companies would.
--
-- Fix: work out the projects the caller can reach ONCE per query
-- (accessible_project_ids(), same rule as has_project_access), and let each
-- policy test a row against that set (a hashed lookup, about a microsecond).
-- The rule is unchanged: supabase/tests/accessible_projects_test.sql checks
-- that, project by project and person by person, both ways.
--
-- Only the plain shape `has_project_access(<table>.project_id)` is rewritten.
-- Policies that pass a sub-select (photos, items and the like) are left
-- alone. They sit on small tables. The migration stops, and rolls back, if a
-- policy is not what it expected afterwards.
--
-- Additive in effect, idempotent (re-running finds nothing left to rewrite).

create index if not exists company_members_user_idx on company_members (user_id);
create index if not exists project_members_user_idx on project_members (user_id);
create index if not exists projects_company_idx on projects (company_id);

-- Same rule as has_project_access(p): an owner or project manager of the
-- company reaches every site; any other member reaches every site that is not
-- members-only; and anyone on a site's team reaches that site. Written to
-- start from the caller's own memberships, not from every project.
create or replace function accessible_project_ids()
returns setof uuid language sql stable security definer set search_path = public as $$
  select p.id
    from company_members m
    join projects p on p.company_id = m.company_id
   where m.user_id = (select auth.uid())
     and (m.role in ('owner', 'project_manager')
          or not coalesce((select a.members_only from site_access a where a.project_id = p.id), false))
  union
  select pm.project_id
    from project_members pm
   where pm.user_id = (select auth.uid());
$$;
revoke all on function accessible_project_ids() from public, anon;
grant execute on function accessible_project_ids() to authenticated;

do $$
declare
  pol record;
  q text;
  w text;
  rewritten int := 0;
  -- ( SELECT has_project_access(tasks.project_id) AS has_project_access)
  pat text := '\( SELECT has_project_access\(([a-z_]+)\.project_id\) AS has_project_access\)';
begin
  for pol in
    select c.relname, p.polname, p.polcmd,
           pg_get_expr(p.polqual, p.polrelid) as qual,
           pg_get_expr(p.polwithcheck, p.polrelid) as wchk
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and (coalesce(pg_get_expr(p.polqual, p.polrelid), '') ~ pat
            or coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') ~ pat)
  loop
    q := regexp_replace(pol.qual, pat, '(\1.project_id IN ( SELECT accessible_project_ids()))', 'g');
    w := regexp_replace(pol.wchk, pat, '(\1.project_id IN ( SELECT accessible_project_ids()))', 'g');
    if pol.qual is not null and pol.wchk is not null then
      execute format('alter policy %I on public.%I using (%s) with check (%s)', pol.polname, pol.relname, q, w);
    elsif pol.qual is not null then
      execute format('alter policy %I on public.%I using (%s)', pol.polname, pol.relname, q);
    else
      execute format('alter policy %I on public.%I with check (%s)', pol.polname, pol.relname, w);
    end if;
    rewritten := rewritten + 1;
  end loop;

  -- Nothing of the old shape may remain.
  if exists (
    select 1 from pg_policy p join pg_class c on c.oid = p.polrelid join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and (coalesce(pg_get_expr(p.polqual, p.polrelid), '') ~ pat
            or coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') ~ pat)) then
    raise exception 'a policy of the old shape is still there after the rewrite';
  end if;
  raise notice 'rewrote % policies to use accessible_project_ids()', rewritten;
end $$;
