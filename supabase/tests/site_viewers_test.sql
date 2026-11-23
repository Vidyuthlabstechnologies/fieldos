-- Checks 20261122150000_site_viewers_read_only.sql. Run after `supabase start`:
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/site_viewers_test.sql
-- Everything runs in one transaction that is rolled back.
begin;

insert into auth.users (id, email, aud, role) values
  ('71e00000-0000-4000-8000-0000000000a1', 'view-owner@example.test', 'authenticated', 'authenticated'),
  ('71e00000-0000-4000-8000-0000000000a2', 'view-viewer@example.test', 'authenticated', 'authenticated'),
  ('71e00000-0000-4000-8000-0000000000a3', 'view-engineer@example.test', 'authenticated', 'authenticated'),
  ('71e00000-0000-4000-8000-0000000000a4', 'view-pm@example.test', 'authenticated', 'authenticated');
insert into companies (id, name, join_code, created_by) values
  ('71e00000-0000-4000-8000-00000000c0a0', 'View Co', 'VIEWAAAAA1', '71e00000-0000-4000-8000-0000000000a1');
insert into company_members (company_id, user_id, role) values
  ('71e00000-0000-4000-8000-00000000c0a0', '71e00000-0000-4000-8000-0000000000a1', 'owner'),
  ('71e00000-0000-4000-8000-00000000c0a0', '71e00000-0000-4000-8000-0000000000a2', 'site_engineer'),
  ('71e00000-0000-4000-8000-00000000c0a0', '71e00000-0000-4000-8000-0000000000a3', 'site_engineer'),
  ('71e00000-0000-4000-8000-00000000c0a0', '71e00000-0000-4000-8000-0000000000a4', 'project_manager');
insert into projects (id, company_id, name) values
  ('71e00000-0000-4000-8000-0000000000fa', '71e00000-0000-4000-8000-00000000c0a0', 'Viewed site'),
  ('71e00000-0000-4000-8000-0000000000fb', '71e00000-0000-4000-8000-00000000c0a0', 'Other site');
insert into project_members (project_id, user_id, role) values
  ('71e00000-0000-4000-8000-0000000000fa', '71e00000-0000-4000-8000-0000000000a2', 'viewer'),
  ('71e00000-0000-4000-8000-0000000000fa', '71e00000-0000-4000-8000-0000000000a3', 'site_engineer'),
  ('71e00000-0000-4000-8000-0000000000fa', '71e00000-0000-4000-8000-0000000000a4', 'viewer');
insert into tasks (id, project_id, title) values
  ('71e00000-0000-4000-8000-0000000001a1', '71e00000-0000-4000-8000-0000000000fa', 'Pour slab'),
  ('71e00000-0000-4000-8000-0000000001b1', '71e00000-0000-4000-8000-0000000000fb', 'Other site task');
insert into issues (id, project_id, description) values
  ('71e00000-0000-4000-8000-0000000002a1', '71e00000-0000-4000-8000-0000000000fa', 'Leak');

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
  raise exception 'should have been refused: %', p_what;
end $$;

-- Refused, or hidden by the table's own policies (no row changed): either
-- way the row must be as it was.
create or replace function pg_temp.expect_unchanged(p_sql text, p_still text, p_what text) returns void language plpgsql as $$
declare
  ok boolean;
begin
  begin
    execute p_sql;
  exception when sqlstate '42501' then
    null;
  end;
  execute p_still into ok;
  if not coalesce(ok, false) then
    raise exception 'should have been refused: %', p_what;
  end if;
end $$;

set local role authenticated;

-- --- the viewer reads, and changes nothing on the site ------------------------
select pg_temp.act_as('71e00000-0000-4000-8000-0000000000a2');
do $$
begin
  if not exists (select 1 from tasks where id = '71e00000-0000-4000-8000-0000000001a1') then
    raise exception 'a viewer could not read the site''s tasks';
  end if;
end $$;
select pg_temp.expect_refused($$
  update tasks set title = 'changed' where id = '71e00000-0000-4000-8000-0000000001a1' $$,
  'a viewer changed a task');
select pg_temp.expect_unchanged($$
  update issues set status = 'resolved' where id = '71e00000-0000-4000-8000-0000000002a1' $$,
  $$ select status <> 'resolved' from issues where id = '71e00000-0000-4000-8000-0000000002a1' $$,
  'a viewer resolved an issue');
select pg_temp.expect_refused($$
  insert into dpr_entries (id, project_id, created_by, entry_date, work_summary)
  values (gen_random_uuid(), '71e00000-0000-4000-8000-0000000000fa', '71e00000-0000-4000-8000-0000000000a2', current_date, 'x') $$,
  'a viewer wrote a daily report');
select pg_temp.expect_unchanged($$
  delete from issues where id = '71e00000-0000-4000-8000-0000000002a1' $$,
  $$ select exists (select 1 from issues where id = '71e00000-0000-4000-8000-0000000002a1') $$,
  'a viewer deleted an issue');

-- ...but still talks in the site chat, and works normally on another site.
insert into project_messages (id, project_id, sender_id, sender_name, body)
values (gen_random_uuid(), '71e00000-0000-4000-8000-0000000000fa', '71e00000-0000-4000-8000-0000000000a2', 'Client consultant', 'Looks good');
update tasks set title = 'Other site task, edited' where id = '71e00000-0000-4000-8000-0000000001b1';

-- --- everyone else is unchanged -----------------------------------------------
select pg_temp.act_as('71e00000-0000-4000-8000-0000000000a3');
update tasks set title = 'Pour slab, level 2' where id = '71e00000-0000-4000-8000-0000000001a1';

-- A company project manager listed as a viewer still manages the site.
select pg_temp.act_as('71e00000-0000-4000-8000-0000000000a4');
update issues set status = 'resolved' where id = '71e00000-0000-4000-8000-0000000002a1';

select pg_temp.act_as('71e00000-0000-4000-8000-0000000000a1');
update tasks set progress = 50 where id = '71e00000-0000-4000-8000-0000000001a1';

do $$
begin
  if (select title from tasks where id = '71e00000-0000-4000-8000-0000000001a1') <> 'Pour slab, level 2' then
    raise exception 'the site engineer''s change did not land';
  end if;
end $$;

-- No signed-in user (the service role): not affected.
reset role;
select set_config('request.jwt.claims', '', true);
update tasks set title = 'Pour slab, by the server' where id = '71e00000-0000-4000-8000-0000000001a1';

select 'site_viewers_test passed';
rollback;
