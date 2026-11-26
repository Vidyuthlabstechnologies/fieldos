-- Checks 20261127140000_supplier_approved_orders_only.sql. Run after `supabase start`:
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/supplier_approved_orders_test.sql
-- Everything runs in one transaction that is rolled back.
begin;

insert into auth.users (id, email, aud, role) values
  ('76e00000-0000-4000-8000-0000000000a1', 'so-owner@example.test', 'authenticated', 'authenticated'),
  ('76e00000-0000-4000-8000-0000000000a2', 'so-manager@example.test', 'authenticated', 'authenticated'),
  ('76e00000-0000-4000-8000-0000000000a3', 'so-supplier@example.test', 'authenticated', 'authenticated'),
  ('76e00000-0000-4000-8000-0000000000a4', 'so-supplier2@example.test', 'authenticated', 'authenticated');
insert into companies (id, name, join_code, created_by) values
  ('76e00000-0000-4000-8000-00000000c0a0', 'Order Co', 'ORDERAAAA1', '76e00000-0000-4000-8000-0000000000a1');
insert into company_members (company_id, user_id, role) values
  ('76e00000-0000-4000-8000-00000000c0a0', '76e00000-0000-4000-8000-0000000000a1', 'owner'),
  ('76e00000-0000-4000-8000-00000000c0a0', '76e00000-0000-4000-8000-0000000000a2', 'project_manager');
insert into projects (id, company_id, name) values
  ('76e00000-0000-4000-8000-0000000000fa', '76e00000-0000-4000-8000-00000000c0a0', 'Ordered site');
insert into vendors (id, company_id, name) values
  ('76e00000-0000-4000-8000-0000000000b1', '76e00000-0000-4000-8000-00000000c0a0', 'Steel Co'),
  ('76e00000-0000-4000-8000-0000000000b2', '76e00000-0000-4000-8000-00000000c0a0', 'Cement Co');
insert into supplier_users (vendor_id, user_id) values
  ('76e00000-0000-4000-8000-0000000000b1', '76e00000-0000-4000-8000-0000000000a3'),
  ('76e00000-0000-4000-8000-0000000000b2', '76e00000-0000-4000-8000-0000000000a4');

-- A manager must approve any order over 1,000.
insert into site_approval_rules (company_id, kind, role, above_amount, created_by) values
  ('76e00000-0000-4000-8000-00000000c0a0', 'purchase_order', 'project_manager', 1000, '76e00000-0000-4000-8000-0000000000a1');

-- big: waits for approval. small: under the rule. rejected: turned down.
insert into purchase_orders (id, project_id, vendor_id, total_amount, created_by, po_number) values
  ('76e00000-0000-4000-8000-0000000004a1', '76e00000-0000-4000-8000-0000000000fa', '76e00000-0000-4000-8000-0000000000b1', 5000, '76e00000-0000-4000-8000-0000000000a1', 'BIG'),
  ('76e00000-0000-4000-8000-0000000004a2', '76e00000-0000-4000-8000-0000000000fa', '76e00000-0000-4000-8000-0000000000b1', 500,  '76e00000-0000-4000-8000-0000000000a1', 'SMALL'),
  ('76e00000-0000-4000-8000-0000000004a3', '76e00000-0000-4000-8000-0000000000fa', '76e00000-0000-4000-8000-0000000000b1', 7000, '76e00000-0000-4000-8000-0000000000a1', 'REJECTED'),
  ('76e00000-0000-4000-8000-0000000004a4', '76e00000-0000-4000-8000-0000000000fa', '76e00000-0000-4000-8000-0000000000b2', 9000, '76e00000-0000-4000-8000-0000000000a1', 'OTHERS');
insert into site_approval_steps (project_id, kind, item_id, level, decision, decided_by) values
  ('76e00000-0000-4000-8000-0000000000fa', 'purchase_order', '76e00000-0000-4000-8000-0000000004a3', 'project_manager', 'rejected', '76e00000-0000-4000-8000-0000000000a2');

create or replace function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  select set_config('request.jwt.claim.sub', p_user::text, true);
$$;

create or replace function pg_temp.numbers() returns text language sql as $$
  select coalesce(string_agg(o->>'po_number', ',' order by o->>'po_number'), '')
    from json_array_elements((select supplier_portal() -> 'orders')) o;
$$;

set local role authenticated;
select pg_temp.act_as('76e00000-0000-4000-8000-0000000000a3');

-- The supplier sees the small order only: not the one waiting for approval,
-- not the rejected one, and never another supplier's.
do $$ begin
  if pg_temp.numbers() <> 'SMALL' then
    raise exception 'the supplier should see only SMALL, saw %', pg_temp.numbers();
  end if;
end $$;

-- ... and cannot send a truck against the one waiting for approval.
do $$
begin
  begin
    perform supplier_dispatch('76e00000-0000-4000-8000-0000000004a1', 'TS09 AB 1234', 'on the way');
    raise exception 'dispatched against an order still waiting for approval';
  exception when sqlstate '22023' then
    if sqlerrm not like '%waiting%' then raise; end if;
  end;
  begin
    perform supplier_dispatch('76e00000-0000-4000-8000-0000000004a3', null, null);
    raise exception 'dispatched against a rejected order';
  exception when sqlstate '22023' then null;
  end;
end $$;

-- An order the rules do not hold can be dispatched, as before.
select supplier_dispatch('76e00000-0000-4000-8000-0000000004a2', 'TS09 CD 5678', 'loaded');
do $$ begin
  if (select status from purchase_orders where id = '76e00000-0000-4000-8000-0000000004a2') <> 'acknowledged' then
    raise exception 'a small order could not be dispatched';
  end if;
end $$;

-- Someone else's order is still "not your order".
do $$
begin
  begin
    perform supplier_dispatch('76e00000-0000-4000-8000-0000000004a4', null, null);
    raise exception 'dispatched against another supplier''s order';
  exception when sqlstate '42501' then null;
  end;
end $$;

-- The manager approves the big one: it appears and can be dispatched.
reset role;
insert into site_approval_steps (project_id, kind, item_id, level, decision, decided_by) values
  ('76e00000-0000-4000-8000-0000000000fa', 'purchase_order', '76e00000-0000-4000-8000-0000000004a1', 'project_manager', 'approved', '76e00000-0000-4000-8000-0000000000a2');
set local role authenticated;
select pg_temp.act_as('76e00000-0000-4000-8000-0000000000a3');
do $$ begin
  if pg_temp.numbers() <> 'BIG,SMALL' then
    raise exception 'after approval the supplier should see BIG and SMALL, saw %', pg_temp.numbers();
  end if;
end $$;
select supplier_dispatch('76e00000-0000-4000-8000-0000000004a1', 'TS09 EF 9999', 'approved, sent');
do $$ begin
  if (select status from purchase_orders where id = '76e00000-0000-4000-8000-0000000004a1') <> 'acknowledged' then
    raise exception 'an approved order could not be dispatched';
  end if;
end $$;

-- The other supplier still sees only their own.
select pg_temp.act_as('76e00000-0000-4000-8000-0000000000a4');
do $$ begin
  if pg_temp.numbers() <> '' then
    raise exception 'the second supplier should see nothing yet (their 9,000 order is waiting), saw %', pg_temp.numbers();
  end if;
end $$;

reset role;
do $$ begin raise notice 'supplier_approved_orders_test: OK'; end $$;
rollback;
