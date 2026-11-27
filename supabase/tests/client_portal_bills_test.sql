-- Checks 20261128110000_client_portal_bill_detail.sql. Run after `supabase start`:
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/client_portal_bills_test.sql
-- Everything runs in one transaction that is rolled back.
begin;

insert into auth.users (id, email, aud, role) values
  ('79e00000-0000-4000-8000-0000000000a1', 'cp-owner@example.test', 'authenticated', 'authenticated'),
  ('79e00000-0000-4000-8000-0000000000a2', 'cp-client@example.test', 'authenticated', 'authenticated'),
  ('79e00000-0000-4000-8000-0000000000a3', 'cp-other@example.test', 'authenticated', 'authenticated');
insert into companies (id, name, join_code, created_by) values
  ('79e00000-0000-4000-8000-00000000c0a0', 'Portal Co', 'PORTALAAA1', '79e00000-0000-4000-8000-0000000000a1');
insert into company_members (company_id, user_id, role) values
  ('79e00000-0000-4000-8000-00000000c0a0', '79e00000-0000-4000-8000-0000000000a1', 'owner');
insert into projects (id, company_id, name) values
  ('79e00000-0000-4000-8000-0000000000f1', '79e00000-0000-4000-8000-00000000c0a0', 'Client villa'),
  ('79e00000-0000-4000-8000-0000000000f2', '79e00000-0000-4000-8000-00000000c0a0', 'Someone else''s villa');
insert into client_users (project_id, user_id) values
  ('79e00000-0000-4000-8000-0000000000f1', '79e00000-0000-4000-8000-0000000000a2');
insert into site_client_bills (id, project_id, kind, bill_number, bill_date, client_name, sac, lines, gst_rate, inter_state,
                               retention_pct, tds_pct, gross, net_payable, status, recorded_by) values
  ('79e00000-0000-4000-8000-0000000004a1', '79e00000-0000-4000-8000-0000000000f1', 'ra', 'RA-1', '2026-11-01', 'Priya', '995411', '[]',
   18, false, 5, 1, 118000, 106200, 'issued', '79e00000-0000-4000-8000-0000000000a1'),
  ('79e00000-0000-4000-8000-0000000004a2', '79e00000-0000-4000-8000-0000000000f2', 'ra', 'RA-X', '2026-11-01', 'Other', '995411', '[]',
   18, false, 0, 0, 5000, 5900, 'issued', '79e00000-0000-4000-8000-0000000000a1');

create or replace function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;
select pg_temp.act_as('79e00000-0000-4000-8000-0000000000a2');
do $$
declare site json; bill json;
begin
  select (client_portal() -> 0) into site;
  bill := site -> 'bills' -> 0;
  -- is distinct from, not <>: a missing key is NULL, and NULL <> 1 is NULL, which would pass.
  if bill ->> 'number' is distinct from 'RA-1' then raise exception 'the client should see their bill: %', bill; end if;
  if (bill ->> 'amount')::numeric is distinct from 106200 then raise exception 'net payable changed: %', bill; end if;
  if (bill ->> 'gross')::numeric is distinct from 118000 or (bill ->> 'gst_rate')::numeric is distinct from 18
     or (bill ->> 'retention_pct')::numeric is distinct from 5 or (bill ->> 'tds_pct')::numeric is distinct from 1 then
    raise exception 'the breakdown is missing or wrong: %', bill;
  end if;
  if json_array_length(client_portal()) <> 1 or json_array_length(site -> 'bills') <> 1 then
    raise exception 'a client saw another site or another site''s bill';
  end if;
  -- nothing about the builder's side leaks into a bill
  if bill::text like '%recorded_by%' or bill::text like '%client_name%' or bill::text like '%client_gstin%' then
    raise exception 'a bill carried more than the client was meant to see: %', bill;
  end if;
end $$;

-- Someone who is not this site's client sees nothing.
select pg_temp.act_as('79e00000-0000-4000-8000-0000000000a3');
do $$ begin
  if json_array_length(client_portal()) <> 0 then raise exception 'a stranger saw a site'; end if;
end $$;

reset role;
do $$ begin raise notice 'client_portal_bills_test: OK'; end $$;
rollback;
