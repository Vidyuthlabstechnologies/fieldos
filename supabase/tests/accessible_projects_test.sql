-- Checks 20261127130000_rls_accessible_projects_once.sql. Run after `supabase start`:
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/accessible_projects_test.sql
-- Everything runs in one transaction that is rolled back.
--
-- The rewrite is only safe if accessible_project_ids() is exactly the set of
-- projects has_project_access() says yes to. This builds the awkward cases and
-- compares the two, person by person and project by project, both ways.
begin;

insert into auth.users (id, email, aud, role) values
  ('74e00000-0000-4000-8000-0000000000a1', 'ap-owner@example.test', 'authenticated', 'authenticated'),
  ('74e00000-0000-4000-8000-0000000000a2', 'ap-pm@example.test', 'authenticated', 'authenticated'),
  ('74e00000-0000-4000-8000-0000000000a3', 'ap-engineer@example.test', 'authenticated', 'authenticated'),
  ('74e00000-0000-4000-8000-0000000000a4', 'ap-teamonly@example.test', 'authenticated', 'authenticated'),
  ('74e00000-0000-4000-8000-0000000000a5', 'ap-outsider@example.test', 'authenticated', 'authenticated'),
  ('74e00000-0000-4000-8000-0000000000a6', 'ap-otherco@example.test', 'authenticated', 'authenticated'),
  ('74e00000-0000-4000-8000-0000000000a7', 'ap-viewer@example.test', 'authenticated', 'authenticated');
insert into companies (id, name, join_code, created_by) values
  ('74e00000-0000-4000-8000-00000000c0a0', 'Access Co', 'ACCESSAAA1', '74e00000-0000-4000-8000-0000000000a1'),
  ('74e00000-0000-4000-8000-00000000c0b0', 'Other Co', 'ACCESSBBB1', '74e00000-0000-4000-8000-0000000000a6');
insert into company_members (company_id, user_id, role) values
  ('74e00000-0000-4000-8000-00000000c0a0', '74e00000-0000-4000-8000-0000000000a1', 'owner'),
  ('74e00000-0000-4000-8000-00000000c0a0', '74e00000-0000-4000-8000-0000000000a2', 'project_manager'),
  ('74e00000-0000-4000-8000-00000000c0a0', '74e00000-0000-4000-8000-0000000000a3', 'site_engineer'),
  ('74e00000-0000-4000-8000-00000000c0a0', '74e00000-0000-4000-8000-0000000000a7', 'site_engineer'),
  ('74e00000-0000-4000-8000-00000000c0b0', '74e00000-0000-4000-8000-0000000000a6', 'owner');
insert into projects (id, company_id, name) values
  ('74e00000-0000-4000-8000-0000000000f1', '74e00000-0000-4000-8000-00000000c0a0', 'Open site'),
  ('74e00000-0000-4000-8000-0000000000f2', '74e00000-0000-4000-8000-00000000c0a0', 'Members-only site'),
  ('74e00000-0000-4000-8000-0000000000f3', '74e00000-0000-4000-8000-00000000c0a0', 'Members-only site, engineer on the team'),
  ('74e00000-0000-4000-8000-0000000000f4', '74e00000-0000-4000-8000-00000000c0b0', 'Other company site');
insert into site_access (id, project_id, members_only) values
  ('74e00000-0000-4000-8000-0000000000f2', '74e00000-0000-4000-8000-0000000000f2', true),
  ('74e00000-0000-4000-8000-0000000000f3', '74e00000-0000-4000-8000-0000000000f3', true);
insert into project_members (project_id, user_id, role) values
  ('74e00000-0000-4000-8000-0000000000f3', '74e00000-0000-4000-8000-0000000000a3', 'site_engineer'),
  ('74e00000-0000-4000-8000-0000000000f1', '74e00000-0000-4000-8000-0000000000a4', 'site_engineer'),
  ('74e00000-0000-4000-8000-0000000000f2', '74e00000-0000-4000-8000-0000000000a7', 'viewer');
insert into tasks (id, project_id, title) values
  ('74e00000-0000-4000-8000-0000000001a1', '74e00000-0000-4000-8000-0000000000f1', 'Open task'),
  ('74e00000-0000-4000-8000-0000000001a2', '74e00000-0000-4000-8000-0000000000f2', 'Members-only task'),
  ('74e00000-0000-4000-8000-0000000001a3', '74e00000-0000-4000-8000-0000000000f3', 'Team task'),
  ('74e00000-0000-4000-8000-0000000001a4', '74e00000-0000-4000-8000-0000000000f4', 'Other company task');

-- No policy of the old, once-per-row shape is left.
do $$
begin
  if exists (select 1 from pg_policy p join pg_class c on c.oid = p.polrelid join pg_namespace n on n.oid = c.relnamespace
              where n.nspname = 'public'
                and coalesce(pg_get_expr(p.polqual, p.polrelid), '') || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '')
                    ~ 'SELECT has_project_access\([a-z_]+\.project_id\)') then
    raise exception 'a policy still calls has_project_access once per row';
  end if;
  if (select count(*) from pg_policy p where pg_get_expr(p.polqual, p.polrelid) like '%accessible_project_ids%') < 50 then
    raise exception 'the policies were not rewritten';
  end if;
end $$;

-- The two rules agree for every person and every project, both ways.
do $$
declare
  u uuid; p uuid; old_says boolean; new_says boolean; checked int := 0; reach int := 0;
begin
  for u in select id from auth.users where id::text like '74e00000%' loop
    perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
    for p in select id from projects where id::text like '74e00000%' loop
      old_says := has_project_access(p);
      new_says := p in (select x from accessible_project_ids() x);
      checked := checked + 1;
      if new_says then reach := reach + 1; end if;
      if old_says is distinct from new_says then
        raise exception 'person % project %: has_project_access says %, accessible_project_ids says %', u, p, old_says, new_says;
      end if;
    end loop;
  end loop;
  -- 7 people x 4 projects; the fixture is built so some of both answers occur.
  if checked <> 28 or reach < 8 or reach > 20 then
    raise exception 'the fixture did not cover both answers (checked %, reach %)', checked, reach;
  end if;
end $$;

-- What each person actually reads through the rewritten policies.
create or replace function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create or replace function pg_temp.sees(p_expected text[]) returns void language plpgsql as $$
declare got text[];
begin
  select coalesce(array_agg(title order by title), '{}') into got from tasks where id::text like '74e00000%';
  if got is distinct from (select array_agg(x order by x) from unnest(p_expected) x) and not (cardinality(p_expected) = 0 and cardinality(got) = 0) then
    raise exception 'expected % got %', p_expected, got;
  end if;
end $$;

set local role authenticated;
select pg_temp.act_as('74e00000-0000-4000-8000-0000000000a1');  -- owner: everything in Access Co
select pg_temp.sees(array['Open task', 'Members-only task', 'Team task']);
select pg_temp.act_as('74e00000-0000-4000-8000-0000000000a2');  -- manager: everything in Access Co
select pg_temp.sees(array['Open task', 'Members-only task', 'Team task']);
select pg_temp.act_as('74e00000-0000-4000-8000-0000000000a3');  -- engineer: open site and the team site, not the members-only one
select pg_temp.sees(array['Open task', 'Team task']);
select pg_temp.act_as('74e00000-0000-4000-8000-0000000000a4');  -- on one site's team only, not in the company
select pg_temp.sees(array['Open task']);
select pg_temp.act_as('74e00000-0000-4000-8000-0000000000a7');  -- engineer who is a viewer on the members-only site
select pg_temp.sees(array['Open task', 'Members-only task']);
select pg_temp.act_as('74e00000-0000-4000-8000-0000000000a5');  -- outsider: nothing
select pg_temp.sees(array[]::text[]);
select pg_temp.act_as('74e00000-0000-4000-8000-0000000000a6');  -- another company: only its own, none of ours
do $$ begin
  if exists (select 1 from tasks where title in ('Open task', 'Members-only task', 'Team task')) then
    raise exception 'another company read this company''s tasks';
  end if;
  if not exists (select 1 from tasks where title = 'Other company task') then
    raise exception 'a company could not read its own task';
  end if;
end $$;

-- A write the person may not make is still refused.
select pg_temp.act_as('74e00000-0000-4000-8000-0000000000a5');
do $$
begin
  begin
    insert into tasks (project_id, title) values ('74e00000-0000-4000-8000-0000000000f1', 'Sneaked in');
    raise exception 'an outsider added a task';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

do $$ begin raise notice 'accessible_projects_test: OK'; end $$;
rollback;
