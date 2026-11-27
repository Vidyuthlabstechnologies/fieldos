-- Checks 20261128150000_client_change_approval.sql. Run after `supabase start`:
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/client_change_approval_test.sql
-- Everything runs in one transaction that is rolled back.
begin;

insert into auth.users (id, email, aud, role) values
  ('7de00000-0000-4000-8000-0000000000a1', 'ca-owner@example.test', 'authenticated', 'authenticated'),
  ('7de00000-0000-4000-8000-0000000000a2', 'ca-eng@example.test', 'authenticated', 'authenticated'),
  ('7de00000-0000-4000-8000-0000000000a3', 'ca-client@example.test', 'authenticated', 'authenticated'),
  ('7de00000-0000-4000-8000-0000000000a4', 'ca-other-client@example.test', 'authenticated', 'authenticated'),
  ('7de00000-0000-4000-8000-0000000000a5', 'ca-stranger@example.test', 'authenticated', 'authenticated');
insert into companies (id, name, join_code, created_by) values
  ('7de00000-0000-4000-8000-00000000c0a0', 'Change Co', 'CHANGEAA11', '7de00000-0000-4000-8000-0000000000a1');
insert into company_members (company_id, user_id, role) values
  ('7de00000-0000-4000-8000-00000000c0a0', '7de00000-0000-4000-8000-0000000000a1', 'owner'),
  ('7de00000-0000-4000-8000-00000000c0a0', '7de00000-0000-4000-8000-0000000000a2', 'site_engineer');
insert into projects (id, company_id, name) values
  ('7de00000-0000-4000-8000-0000000000f1', '7de00000-0000-4000-8000-00000000c0a0', 'Client villa'),
  ('7de00000-0000-4000-8000-0000000000f2', '7de00000-0000-4000-8000-00000000c0a0', 'Other villa');
insert into project_members (project_id, user_id, role) values
  ('7de00000-0000-4000-8000-0000000000f1', '7de00000-0000-4000-8000-0000000000a2', 'site_engineer');
insert into client_users (project_id, user_id) values
  ('7de00000-0000-4000-8000-0000000000f1', '7de00000-0000-4000-8000-0000000000a3'),
  ('7de00000-0000-4000-8000-0000000000f2', '7de00000-0000-4000-8000-0000000000a4');

create or replace function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;
create or replace function pg_temp.refused(p_sql text, p_state text, p_what text) returns void language plpgsql as $$
begin
  begin execute p_sql; exception when others then
    if sqlstate = p_state then return; end if;
    raise exception 'wrong error for %: % %', p_what, sqlstate, sqlerrm;
  end;
  raise exception 'should have been refused (%): %', p_state, p_what;
end $$;

set local role authenticated;

-- --- who may send a change ---------------------------------------------------------
select pg_temp.act_as('7de00000-0000-4000-8000-0000000000a2');
select pg_temp.refused($$select request_change_approval('7de00000-0000-4000-8000-0000000000f1', 'Extra bath', 'x', 50000, 0)$$, '42501', 'an engineer sending');
select pg_temp.refused($$select change_approvals('7de00000-0000-4000-8000-0000000000f1')$$, '42501', 'an engineer listing');
select pg_temp.act_as('7de00000-0000-4000-8000-0000000000a5');
select pg_temp.refused($$select request_change_approval('7de00000-0000-4000-8000-0000000000f1', 'Extra bath', 'x', 50000, 0)$$, '42501', 'a stranger sending');
select pg_temp.act_as('7de00000-0000-4000-8000-0000000000a3');
select pg_temp.refused($$select request_change_approval('7de00000-0000-4000-8000-0000000000f1', 'Free upgrade', 'x', 0, 0)$$, '42501', 'the client sending to herself');

-- --- the owner sends two --------------------------------------------------------------
select pg_temp.act_as('7de00000-0000-4000-8000-0000000000a1');
select pg_temp.refused($$select request_change_approval('7de00000-0000-4000-8000-0000000000f1', '   ', 'x', 100, 0)$$, '23514', 'a blank title');
select pg_temp.refused($$select request_change_approval('7de00000-0000-4000-8000-0000000000f1', 'Extra bath', 'x', null, 0)$$, '23514', 'no price');
create temp table sent as select
  request_change_approval('7de00000-0000-4000-8000-0000000000f1', 'Extra bathroom', 'Attached to bedroom 2', 85000, 6) as one,
  request_change_approval('7de00000-0000-4000-8000-0000000000f1', 'Teak door', null, 32000, 0) as two,
  request_change_approval('7de00000-0000-4000-8000-0000000000f2', 'Other site change', null, 1000, 0) as other;
grant select on sent to authenticated;
do $$ begin
  if (select count(*) from json_array_elements(change_approvals('7de00000-0000-4000-8000-0000000000f1'))) <> 2 then
    raise exception 'the builder should list two changes';
  end if;
  if (select (x ->> 'number')::int from json_array_elements(change_approvals('7de00000-0000-4000-8000-0000000000f1')) x
       where x ->> 'title' = 'Teak door') <> 2 then raise exception 'numbers should run 1, 2 within a site'; end if;
end $$;

-- --- what the client sees ----------------------------------------------------------------
select pg_temp.act_as('7de00000-0000-4000-8000-0000000000a3');
do $$
declare site json; c json;
begin
  site := client_portal() -> 0;
  if json_array_length(client_portal()) <> 1 then raise exception 'the client sees more than her own site'; end if;
  if json_array_length(site -> 'changes') <> 2 then raise exception 'the client should see two changes: %', site -> 'changes'; end if;
  c := site -> 'changes' -> 1;
  if c ->> 'title' is distinct from 'Extra bathroom' or (c ->> 'amount')::numeric is distinct from 85000
     or (c ->> 'extra_days')::int is distinct from 6 or c ->> 'status' is distinct from 'pending' then
    raise exception 'the change reads wrongly: %', c;
  end if;
  if c::text like '%requested_by%' or c::text like '%decided_by%' or c::text like '%project_id%' then
    raise exception 'a change carried more than it should: %', c;
  end if;
end $$;

-- --- the other client cannot touch it -------------------------------------------------------
select pg_temp.act_as('7de00000-0000-4000-8000-0000000000a4');
select pg_temp.refused(format($$select decide_change_approval(%L, true, 'sure')$$, (select one from sent)), '42501', 'another site''s client deciding');
do $$ begin
  if json_array_length((client_portal() -> 0) -> 'changes') <> 1 then raise exception 'the other client should see only her own change'; end if;
end $$;
select pg_temp.act_as('7de00000-0000-4000-8000-0000000000a1');
select pg_temp.refused(format($$select decide_change_approval(%L, true, 'I am the builder')$$, (select one from sent)), '42501', 'the builder deciding for the client');

-- --- the client decides ---------------------------------------------------------------------
select pg_temp.act_as('7de00000-0000-4000-8000-0000000000a3');
select decide_change_approval((select one from sent), true, 'Go ahead, but finish before Diwali');
select decide_change_approval((select two from sent), false, null);
do $$
declare site json;
begin
  site := client_portal() -> 0;
  if (select x ->> 'status' from json_array_elements(site -> 'changes') x where x ->> 'title' = 'Extra bathroom') is distinct from 'approved' then
    raise exception 'the first change should read approved';
  end if;
  if (select x ->> 'note' from json_array_elements(site -> 'changes') x where x ->> 'title' = 'Extra bathroom') is distinct from 'Go ahead, but finish before Diwali' then
    raise exception 'the note was lost';
  end if;
  if (select x ->> 'status' from json_array_elements(site -> 'changes') x where x ->> 'title' = 'Teak door') is distinct from 'declined' then
    raise exception 'the second change should read declined';
  end if;
end $$;
-- final: a second decision, in either direction, is refused
select pg_temp.refused(format($$select decide_change_approval(%L, false, 'changed my mind')$$, (select one from sent)), '55000', 'changing an approval');
select pg_temp.refused(format($$select decide_change_approval(%L, true, 'changed my mind')$$, (select two from sent)), '55000', 'changing a decline');
select pg_temp.act_as('7de00000-0000-4000-8000-0000000000a1');
select pg_temp.refused(format($$select withdraw_change_approval(%L)$$, (select one from sent)), '55000', 'withdrawing a decided change');
do $$ begin
  if (select x ->> 'status' from json_array_elements(change_approvals('7de00000-0000-4000-8000-0000000000f1')) x where x ->> 'title' = 'Extra bathroom') <> 'approved' then
    raise exception 'the builder should see it approved';
  end if;
end $$;

-- --- withdrawing one that is waiting ------------------------------------------------------------
create temp table sent2 as select request_change_approval('7de00000-0000-4000-8000-0000000000f1', 'Granite counter', null, 20000, 0) as three;
grant select on sent2 to authenticated;
select pg_temp.act_as('7de00000-0000-4000-8000-0000000000a2');
select pg_temp.refused(format($$select withdraw_change_approval(%L)$$, (select three from sent2)), '42501', 'an engineer withdrawing');
select pg_temp.act_as('7de00000-0000-4000-8000-0000000000a1');
select withdraw_change_approval((select three from sent2));
select pg_temp.act_as('7de00000-0000-4000-8000-0000000000a3');
do $$ begin
  if json_array_length((client_portal() -> 0) -> 'changes') <> 2 then raise exception 'a withdrawn change should disappear from the client'; end if;
end $$;
select pg_temp.refused(format($$select decide_change_approval(%L, true, null)$$, (select three from sent2)), '42501', 'deciding a withdrawn change');

-- --- the table itself is closed ---------------------------------------------------------------------
select pg_temp.refused($$select * from client_change_orders$$, '42501', 'reading the table');
select pg_temp.refused($$update client_change_orders set status = 'approved'$$, '42501', 'updating the table');
select pg_temp.refused($$insert into client_change_orders (project_id, number, title, amount) values ('7de00000-0000-4000-8000-0000000000f1', 99, 'x', 1)$$, '42501', 'inserting into the table');

-- --- and even the server's own side cannot rewrite a decision or an edit -------------------------------
reset role;
select pg_temp.refused(format($$update client_change_orders set status = 'declined', decided_at = now() where id = %L$$, (select one from sent)), '55000', 'rewriting a decision');
select pg_temp.refused(format($$update client_change_orders set amount = 1 where id = %L$$, (select other from sent)), '55000', 'editing the price after sending');

do $$ begin raise notice 'client_change_approval_test: OK'; end $$;
rollback;
