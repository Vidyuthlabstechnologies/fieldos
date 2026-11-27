-- Checks 20261128120000_revoke_workers_wage_read.sql. Run after `supabase start`:
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/wage_read_closed_test.sql
-- Everything runs in one transaction that is rolled back.
begin;

insert into auth.users (id, email, aud, role) values
  ('7ae00000-0000-4000-8000-0000000000a1', 'wr-owner@example.test', 'authenticated', 'authenticated'),
  ('7ae00000-0000-4000-8000-0000000000a2', 'wr-pm@example.test', 'authenticated', 'authenticated'),
  ('7ae00000-0000-4000-8000-0000000000a3', 'wr-accounts@example.test', 'authenticated', 'authenticated'),
  ('7ae00000-0000-4000-8000-0000000000a4', 'wr-engineer@example.test', 'authenticated', 'authenticated');
insert into companies (id, name, join_code, created_by) values
  ('7ae00000-0000-4000-8000-00000000c0a0', 'Wage Co', 'WAGEAAAAA1', '7ae00000-0000-4000-8000-0000000000a1');
insert into company_members (company_id, user_id, role) values
  ('7ae00000-0000-4000-8000-00000000c0a0', '7ae00000-0000-4000-8000-0000000000a1', 'owner'),
  ('7ae00000-0000-4000-8000-00000000c0a0', '7ae00000-0000-4000-8000-0000000000a2', 'project_manager'),
  ('7ae00000-0000-4000-8000-00000000c0a0', '7ae00000-0000-4000-8000-0000000000a3', 'site_engineer'),
  ('7ae00000-0000-4000-8000-00000000c0a0', '7ae00000-0000-4000-8000-0000000000a4', 'site_engineer');
insert into projects (id, company_id, name) values
  ('7ae00000-0000-4000-8000-0000000000fa', '7ae00000-0000-4000-8000-00000000c0a0', 'Wage site');
insert into project_members (project_id, user_id, role) values
  ('7ae00000-0000-4000-8000-0000000000fa', '7ae00000-0000-4000-8000-0000000000a3', 'accounts'),
  ('7ae00000-0000-4000-8000-0000000000fa', '7ae00000-0000-4000-8000-0000000000a4', 'site_engineer');

create or replace function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create or replace function pg_temp.expect_refused(p_sql text, p_what text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when sqlstate '42501' then
    return;
  end;
  raise exception 'should have been refused (42501): %', p_what;
end $$;

-- The owner records a worker with a rate.
select pg_temp.act_as('7ae00000-0000-4000-8000-0000000000a1');
insert into workers (id, project_id, name, role, daily_wage)
values ('7ae00000-0000-4000-8000-0000000005a1', '7ae00000-0000-4000-8000-0000000000fa', 'Raju', 'Mason', 900);

set local role authenticated;

-- --- a site engineer cannot read the rate by any route ---------------------------
select pg_temp.act_as('7ae00000-0000-4000-8000-0000000000a4');
select pg_temp.expect_refused($$select daily_wage from workers$$, 'select daily_wage');
select pg_temp.expect_refused($$select * from workers$$, 'select * from workers');
select pg_temp.expect_refused($$select w.daily_wage from workers w where w.id = '7ae00000-0000-4000-8000-0000000005a1'$$, 'a rate by id');
select pg_temp.expect_refused($$select count(*) from workers where daily_wage > 0$$, 'a rate used in a filter (it would leak by counting)');
select pg_temp.expect_refused($$select id from workers order by daily_wage$$, 'a rate used to sort');

-- ... but everything else about a worker is still theirs to read, and write.
do $$
begin
  if (select count(*) from (select id, project_id, name, role, phone, status, created_at from workers) x) <> 1 then
    raise exception 'an engineer could not read the worker''s other columns';
  end if;
end $$;
-- (Only owners and project managers edit a worker: no update policy for an
-- engineer, before or after this migration.)
-- They can add a worker, and the guard still gives it no rate.
insert into workers (id, project_id, name, role, daily_wage)
values ('7ae00000-0000-4000-8000-0000000005a2', '7ae00000-0000-4000-8000-0000000000fa', 'Sita', 'Helper', 999);
do $$ begin
  if (select count(*) from worker_wage_rates() where worker_id = '7ae00000-0000-4000-8000-0000000005a2') <> 0 then
    raise exception 'an engineer set a rate';
  end if;
end $$;
-- And the function gives them no rates at all.
do $$ begin
  if (select count(*) from worker_wage_rates()) <> 0 then raise exception 'an engineer read rates through the function'; end if;
end $$;

-- --- the people who may see wages still can, through the function -----------------
select pg_temp.act_as('7ae00000-0000-4000-8000-0000000000a1');
do $$ begin
  if (select daily_wage from worker_wage_rates() where worker_id = '7ae00000-0000-4000-8000-0000000005a1') is distinct from 900 then
    raise exception 'the owner could not read a rate';
  end if;
end $$;
select pg_temp.act_as('7ae00000-0000-4000-8000-0000000000a2');
do $$ begin
  if (select daily_wage from worker_wage_rates() where worker_id = '7ae00000-0000-4000-8000-0000000005a1') is distinct from 900 then
    raise exception 'a project manager could not read a rate';
  end if;
end $$;
select pg_temp.act_as('7ae00000-0000-4000-8000-0000000000a3');
do $$ begin
  if (select daily_wage from worker_wage_rates() where worker_id = '7ae00000-0000-4000-8000-0000000005a1') is distinct from 900 then
    raise exception 'the accounts person could not read a rate';
  end if;
end $$;

-- A manager can still edit a worker and set a rate (writes are not affected).
select pg_temp.act_as('7ae00000-0000-4000-8000-0000000000a2');
update workers set name = 'Raju K', daily_wage = 950 where id = '7ae00000-0000-4000-8000-0000000005a1';
do $$ begin
  if (select count(*) from (select name from workers where name = 'Raju K') x) <> 1 then
    raise exception 'a project manager could not rename a worker';
  end if;
end $$;
do $$ begin
  if (select daily_wage from worker_wage_rates() where worker_id = '7ae00000-0000-4000-8000-0000000005a1') is distinct from 950 then
    raise exception 'a project manager could not change a rate';
  end if;
end $$;

-- The server's own side is not held to it (admin tools, edge functions).
reset role;
do $$ begin
  if (select daily_wage from workers where id = '7ae00000-0000-4000-8000-0000000005a1') is distinct from 950 then
    raise exception 'the owner of the table could not read the column';
  end if;
end $$;

do $$ begin raise notice 'wage_read_closed_test: OK'; end $$;
rollback;
