-- Checks 20261128130000_portal_code_reset.sql. Run after `supabase start`:
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/portal_code_reset_test.sql
-- Everything runs in one transaction that is rolled back.
begin;

insert into auth.users (id, email, aud, role) values
  ('7ce00000-0000-4000-8000-0000000000a1', 'pr-owner@example.test', 'authenticated', 'authenticated'),
  ('7ce00000-0000-4000-8000-0000000000a2', 'pr-eng@example.test', 'authenticated', 'authenticated'),
  ('7ce00000-0000-4000-8000-0000000000a3', 'pr-client@example.test', 'authenticated', 'authenticated'),
  ('7ce00000-0000-4000-8000-0000000000a4', 'pr-supplier@example.test', 'authenticated', 'authenticated'),
  ('7ce00000-0000-4000-8000-0000000000a5', 'pr-sub@example.test', 'authenticated', 'authenticated'),
  ('7ce00000-0000-4000-8000-0000000000a6', 'pr-newclient@example.test', 'authenticated', 'authenticated'),
  ('7ce00000-0000-4000-8000-0000000000a7', 'pr-other-owner@example.test', 'authenticated', 'authenticated');
insert into companies (id, name, join_code, created_by) values
  ('7ce00000-0000-4000-8000-00000000c0a0', 'Reset Co', 'RESETAAA11', '7ce00000-0000-4000-8000-0000000000a1'),
  ('7ce00000-0000-4000-8000-00000000c0a1', 'Other Co', 'RESETBBB11', '7ce00000-0000-4000-8000-0000000000a7');
insert into company_members (company_id, user_id, role) values
  ('7ce00000-0000-4000-8000-00000000c0a0', '7ce00000-0000-4000-8000-0000000000a1', 'owner'),
  ('7ce00000-0000-4000-8000-00000000c0a0', '7ce00000-0000-4000-8000-0000000000a2', 'site_engineer'),
  ('7ce00000-0000-4000-8000-00000000c0a1', '7ce00000-0000-4000-8000-0000000000a7', 'owner');
insert into projects (id, company_id, name) values
  ('7ce00000-0000-4000-8000-0000000000f1', '7ce00000-0000-4000-8000-00000000c0a0', 'Villa');
insert into vendors (id, company_id, name) values
  ('7ce00000-0000-4000-8000-0000000006a1', '7ce00000-0000-4000-8000-00000000c0a0', 'Steel Traders');
insert into subcontractors (id, company_id, name) values
  ('7ce00000-0000-4000-8000-0000000007a1', '7ce00000-0000-4000-8000-00000000c0a0', 'Raju Gang');

create or replace function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;

-- The owner shares codes; three people join with them.
select pg_temp.act_as('7ce00000-0000-4000-8000-0000000000a1');
create temp table codes as select
  client_access_code('7ce00000-0000-4000-8000-0000000000f1') as client,
  supplier_access_code('7ce00000-0000-4000-8000-0000000006a1') as supplier,
  subcontractor_access_code('7ce00000-0000-4000-8000-0000000007a1') as sub;
grant select on codes to authenticated;
select pg_temp.act_as('7ce00000-0000-4000-8000-0000000000a3');
select join_portal((select client from codes));
select pg_temp.act_as('7ce00000-0000-4000-8000-0000000000a4');
select join_portal((select supplier from codes));
select pg_temp.act_as('7ce00000-0000-4000-8000-0000000000a5');
select join_as_subcontractor((select sub from codes));

-- An engineer, and another company's owner, cannot change any of them.
create or replace function pg_temp.refused(p_sql text, p_what text) returns void language plpgsql as $$
begin
  begin execute p_sql; exception when sqlstate '42501' then return; end;
  raise exception 'should have been refused (42501): %', p_what;
end $$;
select pg_temp.act_as('7ce00000-0000-4000-8000-0000000000a2');
select pg_temp.refused($$select reset_client_code('7ce00000-0000-4000-8000-0000000000f1', true)$$, 'engineer, client');
select pg_temp.refused($$select reset_supplier_code('7ce00000-0000-4000-8000-0000000006a1', true)$$, 'engineer, supplier');
select pg_temp.refused($$select reset_subcontractor_code('7ce00000-0000-4000-8000-0000000007a1', true)$$, 'engineer, sub');
select pg_temp.act_as('7ce00000-0000-4000-8000-0000000000a7');
select pg_temp.refused($$select reset_client_code('7ce00000-0000-4000-8000-0000000000f1', true)$$, 'another company, client');
select pg_temp.refused($$select reset_supplier_code('7ce00000-0000-4000-8000-0000000006a1', false)$$, 'another company, supplier');
select pg_temp.refused($$select reset_subcontractor_code('7ce00000-0000-4000-8000-0000000007a1', false)$$, 'another company, sub');
do $$ begin
  if (select count(*) from client_users) <> 0 then raise exception 'a stranger saw client links'; end if;
end $$;

-- Changing the code without removing anyone: the old code stops working for new
-- people, the new one works, and the people already in stay in.
select pg_temp.act_as('7ce00000-0000-4000-8000-0000000000a1');
create temp table new_codes as select reset_client_code('7ce00000-0000-4000-8000-0000000000f1', false) as client;
grant select on new_codes to authenticated;
do $$ begin
  if (select client from new_codes) = (select client from codes) then raise exception 'the code did not change'; end if;
  if client_access_code('7ce00000-0000-4000-8000-0000000000f1') <> (select client from new_codes) then
    raise exception 'the code handed out is not the new one';
  end if;
  if (select count(*) from client_users where project_id = '7ce00000-0000-4000-8000-0000000000f1') <> 1 then
    raise exception 'resetting without removal removed someone';
  end if;
end $$;
select pg_temp.act_as('7ce00000-0000-4000-8000-0000000000a6');
do $$ declare r json; begin
  r := join_portal((select client from codes));
  if r ->> 'error' is distinct from 'invalid_join_code' then raise exception 'the old client code still works: %', r; end if;
  r := join_portal((select client from new_codes));
  if r ->> 'kind' is distinct from 'client' then raise exception 'the new client code does not work: %', r; end if;
end $$;

-- Changing it and removing everyone: the client who had joined sees nothing.
-- (First, that they did see it, so the "nothing" below means something.)
select pg_temp.act_as('7ce00000-0000-4000-8000-0000000000a3');
do $$ begin
  if json_array_length(client_portal()) <> 1 then raise exception 'the client could not see the site before removal'; end if;
end $$;
select pg_temp.act_as('7ce00000-0000-4000-8000-0000000000a4');
do $$ begin
  if json_array_length(supplier_portal() -> 'suppliers') <> 1 then raise exception 'the supplier could not see the portal before removal'; end if;
end $$;
select pg_temp.act_as('7ce00000-0000-4000-8000-0000000000a5');
do $$ begin
  if not is_my_subcontractor('7ce00000-0000-4000-8000-0000000007a1') then raise exception 'the sub-contractor had no access before removal'; end if;
end $$;
select pg_temp.act_as('7ce00000-0000-4000-8000-0000000000a1');
select reset_client_code('7ce00000-0000-4000-8000-0000000000f1', true);
do $$ begin
  if (select count(*) from client_users where project_id = '7ce00000-0000-4000-8000-0000000000f1') <> 0 then
    raise exception 'removal left a client on the site';
  end if;
end $$;
select pg_temp.act_as('7ce00000-0000-4000-8000-0000000000a3');
do $$ begin
  if json_array_length(client_portal()) <> 0 then raise exception 'a removed client still sees the site'; end if;
  if is_client_on_project('7ce00000-0000-4000-8000-0000000000f1') then raise exception 'a removed client is still on the project'; end if;
end $$;

-- Supplier: remove everyone.
select pg_temp.act_as('7ce00000-0000-4000-8000-0000000000a1');
select reset_supplier_code('7ce00000-0000-4000-8000-0000000006a1', true);
do $$ begin
  if (select count(*) from supplier_users where vendor_id = '7ce00000-0000-4000-8000-0000000006a1') <> 0 then
    raise exception 'removal left a supplier user';
  end if;
  if supplier_access_code('7ce00000-0000-4000-8000-0000000006a1') = (select supplier from codes) then
    raise exception 'the supplier code did not change';
  end if;
end $$;
select pg_temp.act_as('7ce00000-0000-4000-8000-0000000000a4');
do $$ begin
  if json_array_length(supplier_portal() -> 'suppliers') <> 0 then raise exception 'a removed supplier still sees the portal'; end if;
end $$;

-- Sub-contractor: remove everyone; the old code is dead.
select pg_temp.act_as('7ce00000-0000-4000-8000-0000000000a1');
select reset_subcontractor_code('7ce00000-0000-4000-8000-0000000007a1', true);
do $$ begin
  if (select count(*) from subcontractor_users where subcontractor_id = '7ce00000-0000-4000-8000-0000000007a1') <> 0 then
    raise exception 'removal left a subcontractor user';
  end if;
end $$;
select pg_temp.act_as('7ce00000-0000-4000-8000-0000000000a5');
do $$ declare r json; begin
  if is_my_subcontractor('7ce00000-0000-4000-8000-0000000007a1') then raise exception 'a removed sub-contractor still has access'; end if;
  r := join_as_subcontractor((select sub from codes));
  if r ->> 'error' is distinct from 'invalid_join_code' then raise exception 'the old sub-contractor code still works: %', r; end if;
end $$;

-- A code that has never been handed out can still be set (first reset creates it).
reset role;
delete from client_codes where project_id = '7ce00000-0000-4000-8000-0000000000f1';
set local role authenticated;
select pg_temp.act_as('7ce00000-0000-4000-8000-0000000000a1');
do $$ begin
  if length(reset_client_code('7ce00000-0000-4000-8000-0000000000f1', false)) < 6 then raise exception 'no code made'; end if;
end $$;

reset role;
do $$ begin raise notice 'portal_code_reset_test: OK'; end $$;
rollback;
