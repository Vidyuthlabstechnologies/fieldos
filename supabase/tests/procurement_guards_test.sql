-- Checks 20261127100000_procurement_update_guards.sql. Run after `supabase start`:
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/procurement_guards_test.sql
-- Everything runs in one transaction that is rolled back.
begin;

insert into auth.users (id, email, aud, role) values
  ('72e00000-0000-4000-8000-0000000000a1', 'pg-owner@example.test', 'authenticated', 'authenticated'),
  ('72e00000-0000-4000-8000-0000000000a2', 'pg-engineer@example.test', 'authenticated', 'authenticated'),
  ('72e00000-0000-4000-8000-0000000000a3', 'pg-pm@example.test', 'authenticated', 'authenticated');
insert into companies (id, name, join_code, created_by) values
  ('72e00000-0000-4000-8000-00000000c0a0', 'Guard Co', 'GUARDAAAA1', '72e00000-0000-4000-8000-0000000000a1');
insert into company_members (company_id, user_id, role) values
  ('72e00000-0000-4000-8000-00000000c0a0', '72e00000-0000-4000-8000-0000000000a1', 'owner'),
  ('72e00000-0000-4000-8000-00000000c0a0', '72e00000-0000-4000-8000-0000000000a2', 'site_engineer'),
  ('72e00000-0000-4000-8000-00000000c0a0', '72e00000-0000-4000-8000-0000000000a3', 'project_manager');
insert into projects (id, company_id, name) values
  ('72e00000-0000-4000-8000-0000000000fa', '72e00000-0000-4000-8000-00000000c0a0', 'Guarded site');
insert into project_members (project_id, user_id, role) values
  ('72e00000-0000-4000-8000-0000000000fa', '72e00000-0000-4000-8000-0000000000a2', 'site_engineer');
insert into vendors (id, company_id, name) values
  ('72e00000-0000-4000-8000-0000000000b1', '72e00000-0000-4000-8000-00000000c0a0', 'Steel Co'),
  ('72e00000-0000-4000-8000-0000000000b2', '72e00000-0000-4000-8000-00000000c0a0', 'Cement Co');
insert into purchase_requisitions (id, project_id, item_name, quantity, unit, estimated_cost, requested_by) values
  ('72e00000-0000-4000-8000-0000000003a1', '72e00000-0000-4000-8000-0000000000fa', 'TMT 12mm', 10, 'tonne', 50000, '72e00000-0000-4000-8000-0000000000a2'),
  ('72e00000-0000-4000-8000-0000000003a2', '72e00000-0000-4000-8000-0000000000fa', 'Cement', 100, 'bag', 30000, '72e00000-0000-4000-8000-0000000000a2'),
  ('72e00000-0000-4000-8000-0000000003a3', '72e00000-0000-4000-8000-0000000000fa', 'Sand', 5, 'load', 9000, '72e00000-0000-4000-8000-0000000000a2');
insert into purchase_orders (id, project_id, vendor_id, requisition_id, total_amount, created_by) values
  ('72e00000-0000-4000-8000-0000000004a1', '72e00000-0000-4000-8000-0000000000fa', '72e00000-0000-4000-8000-0000000000b1',
   '72e00000-0000-4000-8000-0000000003a1', 50000, '72e00000-0000-4000-8000-0000000000a2');

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

create or replace function pg_temp.expect_ok(p_sql text, p_what text) returns void language plpgsql as $$
declare n int;
begin
  execute p_sql;
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'should have changed exactly one row (%): %', n, p_what; end if;
end $$;

-- --- not held to the member rules: the owner of the function, the service role --
-- The test connection is the database owner here, like supplier_dispatch (a
-- SECURITY DEFINER function) or an admin tool. Nothing is refused.
update purchase_orders set total_amount = 51000 where id = '72e00000-0000-4000-8000-0000000004a1';
update purchase_orders set total_amount = 50000 where id = '72e00000-0000-4000-8000-0000000004a1';

set local role authenticated;

-- --- an engineer changes only what the app changes ------------------------------
select pg_temp.act_as('72e00000-0000-4000-8000-0000000000a2');

select pg_temp.expect_refused($$update purchase_orders set total_amount = 1 where id = '72e00000-0000-4000-8000-0000000004a1'$$,
  'an engineer lowering a PO amount');
select pg_temp.expect_refused($$update purchase_orders set vendor_id = '72e00000-0000-4000-8000-0000000000b2' where id = '72e00000-0000-4000-8000-0000000004a1'$$,
  'an engineer moving a PO to another supplier');
select pg_temp.expect_refused($$update purchase_orders set requisition_id = null where id = '72e00000-0000-4000-8000-0000000004a1'$$,
  'an engineer unlinking a PO from its request');
select pg_temp.expect_refused($$update purchase_orders set po_number = 'X' where id = '72e00000-0000-4000-8000-0000000004a1'$$,
  'an engineer renumbering a PO');

-- The phone sends the whole row. Unchanged columns must pass.
select pg_temp.expect_ok($$update purchase_orders set total_amount = 50000, vendor_id = '72e00000-0000-4000-8000-0000000000b1',
  requisition_id = '72e00000-0000-4000-8000-0000000003a1', status = 'delivered', notes = 'received'
  where id = '72e00000-0000-4000-8000-0000000004a1'$$, 'receiving a PO (whole row, same values)');

select pg_temp.expect_ok($$update purchase_orders set status = 'cancelled' where id = '72e00000-0000-4000-8000-0000000004a1'$$,
  'cancelling a PO');
select pg_temp.expect_refused($$update purchase_orders set status = 'issued' where id = '72e00000-0000-4000-8000-0000000004a1'$$,
  'bringing a cancelled PO back');

-- --- requisitions ---------------------------------------------------------------
select pg_temp.expect_refused($$update purchase_requisitions set estimated_cost = 100 where id = '72e00000-0000-4000-8000-0000000003a2'$$,
  'an engineer lowering a request''s cost to slip under an approval limit');
select pg_temp.expect_refused($$update purchase_requisitions set quantity = 1 where id = '72e00000-0000-4000-8000-0000000003a2'$$,
  'an engineer changing a request''s quantity');
select pg_temp.expect_refused($$update purchase_requisitions set status = 'approved' where id = '72e00000-0000-4000-8000-0000000003a2'$$,
  'an engineer approving a request');
select pg_temp.expect_refused($$update purchase_requisitions set approved_by = '72e00000-0000-4000-8000-0000000000a2', approved_at = now()
  where id = '72e00000-0000-4000-8000-0000000003a2'$$, 'an engineer recording themselves as the approver');

select pg_temp.expect_ok($$update purchase_requisitions set status = 'ordered', estimated_cost = 30000, quantity = 100
  where id = '72e00000-0000-4000-8000-0000000003a2'$$, 'ordering a request (whole row, same values)');
select pg_temp.expect_ok($$update purchase_requisitions set status = 'rejected' where id = '72e00000-0000-4000-8000-0000000003a3'$$,
  'rejecting a request');

-- --- a manager approves ---------------------------------------------------------
select pg_temp.act_as('72e00000-0000-4000-8000-0000000000a3');
select pg_temp.expect_ok($$update purchase_requisitions set status = 'approved', approved_by = '72e00000-0000-4000-8000-0000000000a3', approved_at = now()
  where id = '72e00000-0000-4000-8000-0000000003a1'$$, 'a project manager approving');
select pg_temp.expect_refused($$update purchase_requisitions set approved_by = '72e00000-0000-4000-8000-0000000000a1'
  where id = '72e00000-0000-4000-8000-0000000003a1'$$, 'a manager recording someone else as the approver');

-- --- one live PO per request ----------------------------------------------------
reset role;
do $$
begin
  -- The first PO for request a1 is cancelled above, so a new one is fine ...
  insert into purchase_orders (id, project_id, vendor_id, requisition_id, total_amount, created_by) values
    ('72e00000-0000-4000-8000-0000000004a2', '72e00000-0000-4000-8000-0000000000fa', '72e00000-0000-4000-8000-0000000000b1',
     '72e00000-0000-4000-8000-0000000003a1', 50000, '72e00000-0000-4000-8000-0000000000a2');
  -- ... but not a second live one.
  begin
    insert into purchase_orders (id, project_id, vendor_id, requisition_id, total_amount, created_by) values
      ('72e00000-0000-4000-8000-0000000004a3', '72e00000-0000-4000-8000-0000000000fa', '72e00000-0000-4000-8000-0000000000b2',
       '72e00000-0000-4000-8000-0000000003a1', 50000, '72e00000-0000-4000-8000-0000000000a2');
    raise exception 'a second live PO for the same request was allowed';
  exception when unique_violation then
    null;
  end;
  -- A PO with no request is not limited by the index.
  insert into purchase_orders (id, project_id, vendor_id, total_amount, created_by) values
    ('72e00000-0000-4000-8000-0000000004a4', '72e00000-0000-4000-8000-0000000000fa', '72e00000-0000-4000-8000-0000000000b1',
     1000, '72e00000-0000-4000-8000-0000000000a2'),
    ('72e00000-0000-4000-8000-0000000004a5', '72e00000-0000-4000-8000-0000000000fa', '72e00000-0000-4000-8000-0000000000b1',
     1000, '72e00000-0000-4000-8000-0000000000a2');
end $$;

do $$ begin raise notice 'procurement_guards_test: OK'; end $$;
rollback;
