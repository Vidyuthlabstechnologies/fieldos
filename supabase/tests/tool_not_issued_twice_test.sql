-- Checks 20261128170000_tool_not_issued_twice.sql. Run after `supabase start`:
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/tool_not_issued_twice_test.sql
-- Everything runs in one transaction that is rolled back.
begin;

insert into auth.users (id, email, aud, role) values
  ('7ee00000-0000-4000-8000-0000000000a1', 'tt-owner@example.test', 'authenticated', 'authenticated');
insert into companies (id, name, join_code, created_by) values
  ('7ee00000-0000-4000-8000-00000000c0a0', 'Tool Co', 'TOOLSAAAA1', '7ee00000-0000-4000-8000-0000000000a1');
insert into company_members (company_id, user_id, role) values
  ('7ee00000-0000-4000-8000-00000000c0a0', '7ee00000-0000-4000-8000-0000000000a1', 'owner');
insert into projects (id, company_id, name) values
  ('7ee00000-0000-4000-8000-0000000000f1', '7ee00000-0000-4000-8000-00000000c0a0', 'Site A'),
  ('7ee00000-0000-4000-8000-0000000000f2', '7ee00000-0000-4000-8000-00000000c0a0', 'Site B');
insert into tools (id, company_id, name, condition) values
  ('7ee00000-0000-4000-8000-0000000007a1', '7ee00000-0000-4000-8000-00000000c0a0', 'Hammer drill', 'in_use'),
  ('7ee00000-0000-4000-8000-0000000007a2', '7ee00000-0000-4000-8000-00000000c0a0', 'Broken saw', 'repair'),
  ('7ee00000-0000-4000-8000-0000000007a3', '7ee00000-0000-4000-8000-00000000c0a0', 'Old ladder', 'retired');

create or replace function pg_temp.refused(p_sql text, p_msg text, p_what text) returns void language plpgsql as $$
begin
  begin execute p_sql; exception when sqlstate '23514' then
    if sqlerrm <> p_msg then raise exception 'wrong message for %: %', p_what, sqlerrm; end if;
    return;
  end;
  raise exception 'should have been refused: %', p_what;
end $$;

-- Site A takes the drill.
insert into tool_issues (id, company_id, tool_id, project_id, issued_to, issued_on) values
  ('7ee00000-0000-4000-8000-0000000008a1', '7ee00000-0000-4000-8000-00000000c0a0', '7ee00000-0000-4000-8000-0000000007a1',
   '7ee00000-0000-4000-8000-0000000000f1', 'Raju', now());

-- Site B cannot take it too, however it arrives.
select pg_temp.refused($$insert into tool_issues (id, company_id, tool_id, project_id, issued_to, issued_on) values
  ('7ee00000-0000-4000-8000-0000000008a2', '7ee00000-0000-4000-8000-00000000c0a0', '7ee00000-0000-4000-8000-0000000007a1',
   '7ee00000-0000-4000-8000-0000000000f2', 'Sita', now())$$, 'This tool is already out. Take it back first.', 'a second issue of a tool that is out');
-- Nor the same site again.
select pg_temp.refused($$insert into tool_issues (id, company_id, tool_id, project_id, issued_to, issued_on) values
  ('7ee00000-0000-4000-8000-0000000008a3', '7ee00000-0000-4000-8000-00000000c0a0', '7ee00000-0000-4000-8000-0000000007a1',
   '7ee00000-0000-4000-8000-0000000000f1', 'Ravi', now())$$, 'This tool is already out. Take it back first.', 'the same site twice');

-- A tool in repair or retired is not handed out.
select pg_temp.refused($$insert into tool_issues (id, company_id, tool_id, project_id, issued_to, issued_on) values
  ('7ee00000-0000-4000-8000-0000000008a4', '7ee00000-0000-4000-8000-00000000c0a0', '7ee00000-0000-4000-8000-0000000007a2',
   '7ee00000-0000-4000-8000-0000000000f1', 'Ravi', now())$$, 'This tool is not in use.', 'a tool in repair');
select pg_temp.refused($$insert into tool_issues (id, company_id, tool_id, project_id, issued_to, issued_on) values
  ('7ee00000-0000-4000-8000-0000000008a5', '7ee00000-0000-4000-8000-00000000c0a0', '7ee00000-0000-4000-8000-0000000007a3',
   '7ee00000-0000-4000-8000-0000000000f1', 'Ravi', now())$$, 'This tool is not in use.', 'a retired tool');

-- Once it is back, anyone can take it.
update tool_issues set returned_on = now(), return_condition = 'ok' where id = '7ee00000-0000-4000-8000-0000000008a1';
insert into tool_issues (id, company_id, tool_id, project_id, issued_to, issued_on) values
  ('7ee00000-0000-4000-8000-0000000008a6', '7ee00000-0000-4000-8000-00000000c0a0', '7ee00000-0000-4000-8000-0000000007a1',
   '7ee00000-0000-4000-8000-0000000000f2', 'Sita', now());
do $$ begin
  if (select count(*) from tool_issues where tool_id = '7ee00000-0000-4000-8000-0000000007a1' and returned_on is null) <> 1 then
    raise exception 'exactly one issue of the drill should be open';
  end if;
end $$;

-- The same row arriving again (a phone retrying after the answer was lost) is
-- not "a second issue": it is the open one, under the same id.
insert into tool_issues (id, company_id, tool_id, project_id, issued_to, issued_on) values
  ('7ee00000-0000-4000-8000-0000000008a6', '7ee00000-0000-4000-8000-00000000c0a0', '7ee00000-0000-4000-8000-0000000007a1',
   '7ee00000-0000-4000-8000-0000000000f2', 'Sita', now())
on conflict (id) do nothing;
-- ... but a different row for the same tool while it is out still is.
select pg_temp.refused($$insert into tool_issues (id, company_id, tool_id, project_id, issued_to, issued_on) values
  ('7ee00000-0000-4000-8000-0000000008a7', '7ee00000-0000-4000-8000-00000000c0a0', '7ee00000-0000-4000-8000-0000000007a1',
   '7ee00000-0000-4000-8000-0000000000f1', 'Ravi', now())$$, 'This tool is already out. Take it back first.', 'a third issue while out');

do $$ begin raise notice 'tool_not_issued_twice_test: OK'; end $$;
rollback;
