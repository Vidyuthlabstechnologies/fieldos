-- Checks 20261121180000_security_hardening.sql. Run after `supabase start`:
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/security_hardening_test.sql
-- Everything runs in one transaction that is rolled back.
begin;

insert into auth.users (id, email, aud, role) values
  ('5ec00000-0000-4000-8000-0000000000a1', 'sec-owner-a@example.test', 'authenticated', 'authenticated'),
  ('5ec00000-0000-4000-8000-0000000000a2', 'sec-engineer-a@example.test', 'authenticated', 'authenticated'),
  ('5ec00000-0000-4000-8000-0000000000a3', 'sec-sub-one@example.test', 'authenticated', 'authenticated'),
  ('5ec00000-0000-4000-8000-0000000000a4', 'sec-sub-two@example.test', 'authenticated', 'authenticated'),
  ('5ec00000-0000-4000-8000-0000000000b1', 'sec-owner-b@example.test', 'authenticated', 'authenticated');
insert into companies (id, name, join_code, created_by) values
  ('5ec00000-0000-4000-8000-00000000c0a0', 'Sec A', 'SECAAAAAA1', '5ec00000-0000-4000-8000-0000000000a1'),
  ('5ec00000-0000-4000-8000-00000000c0b0', 'Sec B', 'SECBBBBBB1', '5ec00000-0000-4000-8000-0000000000b1');
insert into company_members (company_id, user_id, role) values
  ('5ec00000-0000-4000-8000-00000000c0a0', '5ec00000-0000-4000-8000-0000000000a1', 'owner'),
  ('5ec00000-0000-4000-8000-00000000c0a0', '5ec00000-0000-4000-8000-0000000000a2', 'site_engineer'),
  ('5ec00000-0000-4000-8000-00000000c0b0', '5ec00000-0000-4000-8000-0000000000b1', 'owner');
insert into projects (id, company_id, name) values
  ('5ec00000-0000-4000-8000-0000000000fa', '5ec00000-0000-4000-8000-00000000c0a0', 'Site A'),
  ('5ec00000-0000-4000-8000-0000000000fb', '5ec00000-0000-4000-8000-00000000c0b0', 'Site B');
insert into vendors (id, company_id, name) values
  ('5ec00000-0000-4000-8000-0000000001a0', '5ec00000-0000-4000-8000-00000000c0a0', 'A supplier'),
  ('5ec00000-0000-4000-8000-0000000001b0', '5ec00000-0000-4000-8000-00000000c0b0', 'B supplier');
insert into subcontractors (id, company_id, name) values
  ('5ec00000-0000-4000-8000-0000000002a1', '5ec00000-0000-4000-8000-00000000c0a0', 'A sub one'),
  ('5ec00000-0000-4000-8000-0000000002a2', '5ec00000-0000-4000-8000-00000000c0a0', 'A sub two'),
  ('5ec00000-0000-4000-8000-0000000002b0', '5ec00000-0000-4000-8000-00000000c0b0', 'B sub');
insert into subcontractor_users (subcontractor_id, user_id) values
  ('5ec00000-0000-4000-8000-0000000002a1', '5ec00000-0000-4000-8000-0000000000a3'),
  ('5ec00000-0000-4000-8000-0000000002a2', '5ec00000-0000-4000-8000-0000000000a4');
insert into work_orders (id, project_id, subcontractor_id, description) values
  ('5ec00000-0000-4000-8000-0000000003a1', '5ec00000-0000-4000-8000-0000000000fa', '5ec00000-0000-4000-8000-0000000002a1', 'one'),
  ('5ec00000-0000-4000-8000-0000000003a2', '5ec00000-0000-4000-8000-0000000000fa', '5ec00000-0000-4000-8000-0000000002a2', 'two');
insert into work_claims (id, project_id, work_order_id, qty, submitted_by) values
  ('5ec00000-0000-4000-8000-0000000004a1', '5ec00000-0000-4000-8000-0000000000fa', '5ec00000-0000-4000-8000-0000000003a1', 1, '5ec00000-0000-4000-8000-0000000000a3'),
  ('5ec00000-0000-4000-8000-0000000004a2', '5ec00000-0000-4000-8000-0000000000fa', '5ec00000-0000-4000-8000-0000000003a2', 1, '5ec00000-0000-4000-8000-0000000000a4');
insert into commercial_attachments (id, project_id, parent_kind, parent_id, file_path, mime_type, uploaded_by) values
  ('5ec00000-0000-4000-8000-0000000005a1', '5ec00000-0000-4000-8000-0000000000fa', 'claim', '5ec00000-0000-4000-8000-0000000004a1',
   '5ec00000-0000-4000-8000-0000000000fa/claims/one.jpg', 'image/jpeg', '5ec00000-0000-4000-8000-0000000000a3'),
  ('5ec00000-0000-4000-8000-0000000005a2', '5ec00000-0000-4000-8000-0000000000fa', 'claim', '5ec00000-0000-4000-8000-0000000004a2',
   '5ec00000-0000-4000-8000-0000000000fa/claims/two.jpg', 'image/jpeg', '5ec00000-0000-4000-8000-0000000000a4');
insert into storage.objects (bucket_id, name, owner_id) values
  ('documents', '5ec00000-0000-4000-8000-0000000000fa/claims/one.jpg', '5ec00000-0000-4000-8000-0000000000a3'),
  ('documents', '5ec00000-0000-4000-8000-0000000000fa/claims/two.jpg', '5ec00000-0000-4000-8000-0000000000a4'),
  ('documents', '5ec00000-0000-4000-8000-0000000000fa/expenses/owner-bill.jpg', '5ec00000-0000-4000-8000-0000000000a1'),
  ('documents', '5ec00000-0000-4000-8000-0000000000fa/expenses/engineer-bill.jpg', '5ec00000-0000-4000-8000-0000000000a2');

-- Storage's own trigger refuses SQL deletes unless this is set; the
-- Storage API sets it the same way, so the policies below are what decide.
select set_config('storage.allow_delete_query', 'true', true);

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

set local role authenticated;

-- --- links to another company's records are refused ---------------------------
select pg_temp.act_as('5ec00000-0000-4000-8000-0000000000b1');
select pg_temp.expect_refused($$
  insert into work_orders (project_id, subcontractor_id, description)
  values ('5ec00000-0000-4000-8000-0000000000fb', '5ec00000-0000-4000-8000-0000000002a1', 'x') $$,
  'a work order for another company''s subcontractor');
select pg_temp.expect_refused($$
  insert into purchase_orders (project_id, vendor_id, created_by)
  values ('5ec00000-0000-4000-8000-0000000000fb', '5ec00000-0000-4000-8000-0000000001a0',
          '5ec00000-0000-4000-8000-0000000000b1') $$,
  'a purchase order to another company''s supplier');
select pg_temp.expect_refused($$
  insert into variations (id, project_id, work_order_id, title, origin, raised_by)
  values (gen_random_uuid(), '5ec00000-0000-4000-8000-0000000000fb', '5ec00000-0000-4000-8000-0000000003a1', 'x', 'other',
          '5ec00000-0000-4000-8000-0000000000b1') $$,
  'a variation on another site''s work order');
select pg_temp.expect_refused($$
  insert into crm_leads (id, company_id, name, project_id)
  values (gen_random_uuid(), '5ec00000-0000-4000-8000-00000000c0b0', 'x', '5ec00000-0000-4000-8000-0000000000fa') $$,
  'a lead linked to another company''s site');

-- ... and links inside your own company still work.
insert into work_orders (project_id, subcontractor_id, description)
values ('5ec00000-0000-4000-8000-0000000000fb', '5ec00000-0000-4000-8000-0000000002b0', 'own');
insert into purchase_orders (project_id, vendor_id, created_by)
values ('5ec00000-0000-4000-8000-0000000000fb', '5ec00000-0000-4000-8000-0000000001b0',
        '5ec00000-0000-4000-8000-0000000000b1');

-- --- claim photos: a subcontractor sees only their own -------------------------
select pg_temp.act_as('5ec00000-0000-4000-8000-0000000000a4');
do $$
begin
  if exists (select 1 from storage.objects where name = '5ec00000-0000-4000-8000-0000000000fa/claims/one.jpg') then
    raise exception 'a subcontractor read another firm''s claim photo';
  end if;
  if not exists (select 1 from storage.objects where name = '5ec00000-0000-4000-8000-0000000000fa/claims/two.jpg') then
    raise exception 'a subcontractor could not read their own claim photo';
  end if;
end $$;
-- they can re-send (update) their own upload, not someone else's
update storage.objects set metadata = '{"resent": true}'
 where name = '5ec00000-0000-4000-8000-0000000000fa/claims/two.jpg';
do $$
begin
  if (select count(*) from storage.objects where name = '5ec00000-0000-4000-8000-0000000000fa/claims/two.jpg'
        and metadata ->> 'resent' = 'true') <> 1 then
    raise exception 'a subcontractor could not re-send their own claim photo';
  end if;
end $$;

-- --- site files: only the uploader or a manager replaces or deletes ------------
select pg_temp.act_as('5ec00000-0000-4000-8000-0000000000a2');
update storage.objects set metadata = '{"swapped": true}'
 where name = '5ec00000-0000-4000-8000-0000000000fa/expenses/owner-bill.jpg';
delete from storage.objects where name = '5ec00000-0000-4000-8000-0000000000fa/expenses/owner-bill.jpg';
reset role;
do $$
begin
  if (select metadata ->> 'swapped' from storage.objects
       where name = '5ec00000-0000-4000-8000-0000000000fa/expenses/owner-bill.jpg') is not null then
    raise exception 'a site engineer replaced the owner''s file';
  end if;
  if not exists (select 1 from storage.objects where name = '5ec00000-0000-4000-8000-0000000000fa/expenses/owner-bill.jpg') then
    raise exception 'a site engineer deleted the owner''s file';
  end if;
end $$;
set local role authenticated;
select pg_temp.act_as('5ec00000-0000-4000-8000-0000000000a2');
delete from storage.objects where name = '5ec00000-0000-4000-8000-0000000000fa/expenses/engineer-bill.jpg';
select pg_temp.act_as('5ec00000-0000-4000-8000-0000000000a1');
delete from storage.objects where name = '5ec00000-0000-4000-8000-0000000000fa/expenses/owner-bill.jpg';
reset role;
do $$
begin
  if exists (select 1 from storage.objects where name like '5ec00000-0000-4000-8000-0000000000fa/expenses/%') then
    raise exception 'the uploader or the owner could not delete a file';
  end if;
end $$;

\echo 'security_hardening_test: OK'
rollback;
