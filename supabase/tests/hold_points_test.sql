-- Checks 20261128100000_hold_points_block_progress.sql. Run after `supabase start`:
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/hold_points_test.sql
-- Everything runs in one transaction that is rolled back.
begin;

insert into auth.users (id, email, aud, role) values
  ('78e00000-0000-4000-8000-0000000000a1', 'hp-owner@example.test', 'authenticated', 'authenticated'),
  ('78e00000-0000-4000-8000-0000000000a2', 'hp-pm@example.test', 'authenticated', 'authenticated'),
  ('78e00000-0000-4000-8000-0000000000a3', 'hp-engineer@example.test', 'authenticated', 'authenticated'),
  ('78e00000-0000-4000-8000-0000000000a4', 'hp-quality@example.test', 'authenticated', 'authenticated');
insert into companies (id, name, join_code, created_by) values
  ('78e00000-0000-4000-8000-00000000c0a0', 'Hold Co', 'HOLDAAAAA1', '78e00000-0000-4000-8000-0000000000a1');
insert into company_members (company_id, user_id, role) values
  ('78e00000-0000-4000-8000-00000000c0a0', '78e00000-0000-4000-8000-0000000000a1', 'owner'),
  ('78e00000-0000-4000-8000-00000000c0a0', '78e00000-0000-4000-8000-0000000000a2', 'project_manager'),
  ('78e00000-0000-4000-8000-00000000c0a0', '78e00000-0000-4000-8000-0000000000a3', 'site_engineer'),
  ('78e00000-0000-4000-8000-00000000c0a0', '78e00000-0000-4000-8000-0000000000a4', 'site_engineer');
insert into projects (id, company_id, name) values
  ('78e00000-0000-4000-8000-0000000000fa', '78e00000-0000-4000-8000-00000000c0a0', 'Held site');
insert into project_members (project_id, user_id, role) values
  ('78e00000-0000-4000-8000-0000000000fa', '78e00000-0000-4000-8000-0000000000a3', 'site_engineer'),
  ('78e00000-0000-4000-8000-0000000000fa', '78e00000-0000-4000-8000-0000000000a4', 'quality_officer');

-- T1 held by a pending hold point; T2 free; T3 already 40% when a hold is raised;
-- T4 waits on a hold through a constraint; T5 held by a rejected hold point.
insert into tasks (id, project_id, title, progress, status) values
  ('78e00000-0000-4000-8000-0000000001a1', '78e00000-0000-4000-8000-0000000000fa', 'Slab concreting', 0, 'todo'),
  ('78e00000-0000-4000-8000-0000000001a2', '78e00000-0000-4000-8000-0000000000fa', 'Free task', 0, 'todo'),
  ('78e00000-0000-4000-8000-0000000001a3', '78e00000-0000-4000-8000-0000000000fa', 'Column pour', 40, 'in_progress'),
  ('78e00000-0000-4000-8000-0000000001a4', '78e00000-0000-4000-8000-0000000000fa', 'Waits via constraint', 0, 'todo'),
  ('78e00000-0000-4000-8000-0000000001a5', '78e00000-0000-4000-8000-0000000000fa', 'Rejected inspection', 0, 'todo');

create or replace function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create or replace function pg_temp.expect(p_sql text, p_state text, p_what text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlstate = p_state then return; end if;
    raise exception 'wrong error for %: % %', p_what, sqlstate, sqlerrm;
  end;
  raise exception 'should have been refused: %', p_what;
end $$;

-- The hold points, raised by the engineer.
select pg_temp.act_as('78e00000-0000-4000-8000-0000000000a3');
insert into site_hold_points (id, project_id, title, task_id, raised_by) values
  ('78e00000-0000-4000-8000-0000000002a1', '78e00000-0000-4000-8000-0000000000fa', 'Rebar check before concreting', '78e00000-0000-4000-8000-0000000001a1', '78e00000-0000-4000-8000-0000000000a3'),
  ('78e00000-0000-4000-8000-0000000002a3', '78e00000-0000-4000-8000-0000000000fa', 'Column cage check', '78e00000-0000-4000-8000-0000000001a3', '78e00000-0000-4000-8000-0000000000a3'),
  ('78e00000-0000-4000-8000-0000000002a4', '78e00000-0000-4000-8000-0000000000fa', 'Shuttering check', null, '78e00000-0000-4000-8000-0000000000a3'),
  ('78e00000-0000-4000-8000-0000000002a5', '78e00000-0000-4000-8000-0000000000fa', 'Cover check', '78e00000-0000-4000-8000-0000000001a5', '78e00000-0000-4000-8000-0000000000a3');
insert into site_task_constraints (id, project_id, task_id, kind, description, link_id, raised_by) values
  ('78e00000-0000-4000-8000-0000000003a4', '78e00000-0000-4000-8000-0000000000fa', '78e00000-0000-4000-8000-0000000001a4',
   'hold_point', 'Waiting on the shuttering check', '78e00000-0000-4000-8000-0000000002a4', '78e00000-0000-4000-8000-0000000000a3');

select pg_temp.act_as('78e00000-0000-4000-8000-0000000000a2');
set local role authenticated;
update site_hold_points set status = 'rejected', decided_by = '78e00000-0000-4000-8000-0000000000a2', decided_at = now()
 where id = '78e00000-0000-4000-8000-0000000002a5';
reset role;

set local role authenticated;
select pg_temp.act_as('78e00000-0000-4000-8000-0000000000a3');

-- Held: no progress, and not started, while the hold point is pending.
select pg_temp.expect($$update tasks set progress = 10 where id = '78e00000-0000-4000-8000-0000000001a1'$$, '23514', 'progress past a pending hold point');
select pg_temp.expect($$update tasks set status = 'in_progress' where id = '78e00000-0000-4000-8000-0000000001a1'$$, '23514', 'starting a task behind a pending hold point');
select pg_temp.expect($$update tasks set status = 'done', progress = 100 where id = '78e00000-0000-4000-8000-0000000001a1'$$, '23514', 'finishing a task behind a pending hold point');
-- A hold raised when work was already 40% stops further progress, not less.
select pg_temp.expect($$update tasks set progress = 60 where id = '78e00000-0000-4000-8000-0000000001a3'$$, '23514', 'progress on a task with a new hold point');
update tasks set progress = 30 where id = '78e00000-0000-4000-8000-0000000001a3';
-- A hold point linked through a constraint, and a rejected one, hold too.
select pg_temp.expect($$update tasks set progress = 5 where id = '78e00000-0000-4000-8000-0000000001a4'$$, '23514', 'progress behind a constraint on a pending hold point');
select pg_temp.expect($$update tasks set progress = 5 where id = '78e00000-0000-4000-8000-0000000001a5'$$, '23514', 'progress behind a rejected hold point');
-- Everything else still works: a free task, and changes that are not progress.
update tasks set progress = 50, status = 'in_progress' where id = '78e00000-0000-4000-8000-0000000001a2';
update tasks set title = 'Slab concreting (level 2)' where id = '78e00000-0000-4000-8000-0000000001a1';

-- The engineer cannot release their own hold point.
select pg_temp.expect($$update site_hold_points set status = 'released', decided_by = '78e00000-0000-4000-8000-0000000000a3', decided_at = now()
  where id = '78e00000-0000-4000-8000-0000000002a1'$$, '42501', 'an engineer releasing a hold point');

-- The quality officer, who inspects, can.
select pg_temp.act_as('78e00000-0000-4000-8000-0000000000a4');
update site_hold_points set status = 'released', decided_by = '78e00000-0000-4000-8000-0000000000a4', decided_at = now()
 where id = '78e00000-0000-4000-8000-0000000002a1';
do $$ begin
  if (select status from site_hold_points where id = '78e00000-0000-4000-8000-0000000002a1') <> 'released' then
    raise exception 'the quality officer could not release a hold point';
  end if;
end $$;

-- Released: the task moves.
select pg_temp.act_as('78e00000-0000-4000-8000-0000000000a3');
update tasks set progress = 10, status = 'in_progress' where id = '78e00000-0000-4000-8000-0000000001a1';

-- The constraint's hold point released by the manager clears the task.
select pg_temp.act_as('78e00000-0000-4000-8000-0000000000a2');
update site_hold_points set status = 'released', decided_by = '78e00000-0000-4000-8000-0000000000a2', decided_at = now()
 where id = '78e00000-0000-4000-8000-0000000002a4';
select pg_temp.act_as('78e00000-0000-4000-8000-0000000000a3');
update tasks set progress = 5 where id = '78e00000-0000-4000-8000-0000000001a4';

-- Admin tools (not the API) are not held to it.
reset role;
update tasks set progress = 20 where id = '78e00000-0000-4000-8000-0000000001a5';

do $$ begin raise notice 'hold_points_test: OK'; end $$;
rollback;
