-- Checks 20261128160000_supplier_order_breakup.sql. Run after `supabase start`:
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/supplier_order_breakup_test.sql
-- Everything runs in one transaction that is rolled back.
begin;

insert into auth.users (id, email, aud, role) values
  ('7fe00000-0000-4000-8000-0000000000a1', 'sb-owner@example.test', 'authenticated', 'authenticated'),
  ('7fe00000-0000-4000-8000-0000000000a3', 'sb-supplier@example.test', 'authenticated', 'authenticated');
insert into companies (id, name, join_code, created_by) values
  ('7fe00000-0000-4000-8000-00000000c0a0', 'Breakup Co', 'BREAKAAAA1', '7fe00000-0000-4000-8000-0000000000a1');
insert into company_members (company_id, user_id, role) values
  ('7fe00000-0000-4000-8000-00000000c0a0', '7fe00000-0000-4000-8000-0000000000a1', 'owner');
insert into projects (id, company_id, name) values
  ('7fe00000-0000-4000-8000-0000000000fa', '7fe00000-0000-4000-8000-00000000c0a0', 'Breakup site');
insert into vendors (id, company_id, name) values
  ('7fe00000-0000-4000-8000-0000000000b1', '7fe00000-0000-4000-8000-00000000c0a0', 'Steel Co'),
  ('7fe00000-0000-4000-8000-0000000000b2', '7fe00000-0000-4000-8000-00000000c0a0', 'Cement Co');
insert into supplier_users (vendor_id, user_id) values
  ('7fe00000-0000-4000-8000-0000000000b1', '7fe00000-0000-4000-8000-0000000000a3');
insert into purchase_requisitions (id, project_id, item_name, quantity, unit, requested_by) values
  ('7fe00000-0000-4000-8000-0000000003a1', '7fe00000-0000-4000-8000-0000000000fa', 'TMT 12mm', 2.5, 'tonne', '7fe00000-0000-4000-8000-0000000000a1');
insert into purchase_orders (id, project_id, vendor_id, total_amount, created_by, po_number, requisition_id) values
  ('7fe00000-0000-4000-8000-0000000004a1', '7fe00000-0000-4000-8000-0000000000fa', '7fe00000-0000-4000-8000-0000000000b1', 150000, '7fe00000-0000-4000-8000-0000000000a1', 'PO-QUOTED', '7fe00000-0000-4000-8000-0000000003a1'),
  ('7fe00000-0000-4000-8000-0000000004a2', '7fe00000-0000-4000-8000-0000000000fa', '7fe00000-0000-4000-8000-0000000000b1', 900,    '7fe00000-0000-4000-8000-0000000000a1', 'PO-PLAIN', null);
create or replace function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  select set_config('request.jwt.claim.sub', p_user::text, true);
$$;

-- The owner records the quotes (the guard drops an order link set by anyone else).
select pg_temp.act_as('7fe00000-0000-4000-8000-0000000000a1');
-- This supplier's accepted quote, and another supplier's quote pointing at the same order.
insert into site_supplier_quotes (id, project_id, request_id, vendor_id, rate, gst_pct, transport, status, po_id) values
  ('7fe00000-0000-4000-8000-0000000005a1', '7fe00000-0000-4000-8000-0000000000fa', '7fe00000-0000-4000-8000-0000000003a1', '7fe00000-0000-4000-8000-0000000000b1', 52000, 18, 3000, 'accepted', '7fe00000-0000-4000-8000-0000000004a1'),
  ('7fe00000-0000-4000-8000-0000000005a2', '7fe00000-0000-4000-8000-0000000000fa', '7fe00000-0000-4000-8000-0000000003a1', '7fe00000-0000-4000-8000-0000000000b2', 1, 5, 7, 'received', '7fe00000-0000-4000-8000-0000000004a1');

set local role authenticated;
select pg_temp.act_as('7fe00000-0000-4000-8000-0000000000a3');
do $$
declare quoted json; plain json;
begin
  select o into quoted from json_array_elements(supplier_portal() -> 'orders') o where o ->> 'po_number' = 'PO-QUOTED';
  select o into plain from json_array_elements(supplier_portal() -> 'orders') o where o ->> 'po_number' = 'PO-PLAIN';
  -- is distinct from: a missing key is NULL, and NULL <> x would pass an if.
  if (quoted ->> 'quantity')::numeric is distinct from 2.5 or quoted ->> 'unit' is distinct from 'tonne' then
    raise exception 'the order lacks its quantity and unit: %', quoted;
  end if;
  if (quoted ->> 'rate')::numeric is distinct from 52000 or (quoted ->> 'gst_pct')::numeric is distinct from 18
     or (quoted ->> 'transport')::numeric is distinct from 3000 then
    raise exception 'the order lacks this supplier''s rate, GST and transport (or shows another''s): %', quoted;
  end if;
  if (quoted ->> 'total')::numeric is distinct from 150000 or quoted ->> 'item' is distinct from 'TMT 12mm' then
    raise exception 'what was already there changed: %', quoted;
  end if;
  if plain is null or plain ->> 'rate' is not null or plain ->> 'quantity' is not null then
    raise exception 'an order with no quote should carry no rate: %', plain;
  end if;
  if quoted::text like '%created_by%' or quoted::text like '%cost_code%' then
    raise exception 'an order carried more than the supplier should see: %', quoted;
  end if;
end $$;

reset role;
do $$ begin raise notice 'supplier_order_breakup_test: OK'; end $$;
rollback;
