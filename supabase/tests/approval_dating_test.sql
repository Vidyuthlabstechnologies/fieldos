-- Checks 20261127120000_approval_server_dating.sql. Run after `supabase start`:
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/approval_dating_test.sql
-- Everything runs in one transaction that is rolled back.
begin;

insert into auth.users (id, email, aud, role) values
  ('73e00000-0000-4000-8000-0000000000a1', 'ad-owner@example.test', 'authenticated', 'authenticated'),
  ('73e00000-0000-4000-8000-0000000000a2', 'ad-engineer@example.test', 'authenticated', 'authenticated');
insert into companies (id, name, join_code, created_by) values
  ('73e00000-0000-4000-8000-00000000c0a0', 'Dating Co', 'DATEAAAAA1', '73e00000-0000-4000-8000-0000000000a1');
insert into company_members (company_id, user_id, role) values
  ('73e00000-0000-4000-8000-00000000c0a0', '73e00000-0000-4000-8000-0000000000a1', 'owner'),
  ('73e00000-0000-4000-8000-00000000c0a0', '73e00000-0000-4000-8000-0000000000a2', 'site_engineer');
insert into projects (id, company_id, name) values
  ('73e00000-0000-4000-8000-0000000000fa', '73e00000-0000-4000-8000-00000000c0a0', 'Dated site');
insert into project_members (project_id, user_id, role) values
  ('73e00000-0000-4000-8000-0000000000fa', '73e00000-0000-4000-8000-0000000000a2', 'site_engineer');
insert into vendors (id, company_id, name) values
  ('73e00000-0000-4000-8000-0000000000b1', '73e00000-0000-4000-8000-00000000c0a0', 'Steel Co');

-- The company sets rules: a manager must approve any request or expense over 1,000.
insert into site_approval_rules (company_id, kind, role, above_amount, created_by) values
  ('73e00000-0000-4000-8000-00000000c0a0', 'purchase_request', 'project_manager', 1000, '73e00000-0000-4000-8000-0000000000a1'),
  ('73e00000-0000-4000-8000-00000000c0a0', 'expense', 'project_manager', 1000, '73e00000-0000-4000-8000-0000000000a1');

create or replace function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  select set_config('request.jwt.claim.sub', p_user::text, true);
$$;

create or replace function pg_temp.expect_chain_refusal(p_sql text, p_what text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm like '%still needs its approvals%' then return; end if;
    raise;
  end;
  raise exception 'the approval rule did not stop it: %', p_what;
end $$;

set local role authenticated;
select pg_temp.act_as('73e00000-0000-4000-8000-0000000000a2');

-- The engineer back-dates a 50,000 request to 2020, before the rule existed.
insert into purchase_requisitions (id, project_id, item_name, quantity, unit, estimated_cost, requested_by, created_at)
values ('73e00000-0000-4000-8000-0000000003a1', '73e00000-0000-4000-8000-0000000000fa', 'TMT 12mm', 10, 'tonne', 50000,
        '73e00000-0000-4000-8000-0000000000a2', '2020-01-01');

do $$
begin
  if (select received_at from purchase_requisitions where id = '73e00000-0000-4000-8000-0000000003a1') < now() - interval '1 minute' then
    raise exception 'received_at took the phone''s date';
  end if;
end $$;

-- A PO cannot be raised from it without the manager's approval.
select pg_temp.expect_chain_refusal($$insert into purchase_orders (id, project_id, vendor_id, requisition_id, total_amount, created_by)
  values ('73e00000-0000-4000-8000-0000000004a1', '73e00000-0000-4000-8000-0000000000fa', '73e00000-0000-4000-8000-0000000000b1',
          '73e00000-0000-4000-8000-0000000003a1', 50000, '73e00000-0000-4000-8000-0000000000a2')$$,
  'a back-dated request raised into a PO');

-- received_at cannot be set on insert or changed afterwards.
insert into purchase_requisitions (id, project_id, item_name, quantity, unit, estimated_cost, requested_by, received_at)
values ('73e00000-0000-4000-8000-0000000003a2', '73e00000-0000-4000-8000-0000000000fa', 'Sand', 5, 'load', 500,
        '73e00000-0000-4000-8000-0000000000a2', '2019-01-01');
update purchase_requisitions set received_at = '2019-01-01', status = 'ordered' where id = '73e00000-0000-4000-8000-0000000003a2';
do $$
begin
  if (select received_at from purchase_requisitions where id = '73e00000-0000-4000-8000-0000000003a2') < now() - interval '1 minute' then
    raise exception 'received_at could be set through the API';
  end if;
end $$;

-- A small request is under the rule and goes through.
insert into purchase_orders (id, project_id, vendor_id, requisition_id, total_amount, created_by)
values ('73e00000-0000-4000-8000-0000000004a2', '73e00000-0000-4000-8000-0000000000fa', '73e00000-0000-4000-8000-0000000000b1',
        '73e00000-0000-4000-8000-0000000003a2', 500, '73e00000-0000-4000-8000-0000000000a2');

-- The same for an expense: back-dated to 2020, 20,000, approved at the weekly close.
insert into site_expenses (id, project_id, category, amount, incurred_on, recorded_by, created_at)
values ('73e00000-0000-4000-8000-0000000005a1', '73e00000-0000-4000-8000-0000000000fa', 'Material', 20000, current_date,
        '73e00000-0000-4000-8000-0000000000a2', '2020-01-01');
reset role;
select pg_temp.act_as('73e00000-0000-4000-8000-0000000000a1');
select pg_temp.expect_chain_refusal($$insert into site_close_reviews (project_id, week_start, item_kind, item_id, decision, decided_by)
  values ('73e00000-0000-4000-8000-0000000000fa', date_trunc('week', current_date)::date, 'expense',
          '73e00000-0000-4000-8000-0000000005a1', 'approved', '73e00000-0000-4000-8000-0000000000a1')$$,
  'a back-dated expense approved without its chain');

do $$ begin raise notice 'approval_dating_test: OK'; end $$;
rollback;
