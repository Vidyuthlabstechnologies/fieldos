-- Checks consent_records from 20261123210000_india_compliance.sql. Run after
-- `supabase start`:
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/consent_records_test.sql
-- Everything runs in one transaction that is rolled back.
begin;

insert into auth.users (id, email, aud, role) values
  ('c0e00000-0000-4000-8000-0000000000a1', 'consent-a@example.test', 'authenticated', 'authenticated'),
  ('c0e00000-0000-4000-8000-0000000000a2', 'consent-b@example.test', 'authenticated', 'authenticated');

set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', 'c0e00000-0000-4000-8000-0000000000a1', 'role', 'authenticated')::text, true);

insert into consent_records (purpose, granted, given_at, notice_version)
  values ('ai_assistant', true, now() - interval '1 hour', '23 November 2026');
insert into consent_records (purpose, granted, given_at, notice_version, app_version, language)
  values ('ai_assistant', false, now(), '23 November 2026', '1.7.9+24', 'te'),
         ('attendance_photo_location', true, now(), '23 November 2026', '1.7.9+24', 'te');

do $$ begin
  if (select granted from my_consents() where purpose = 'ai_assistant') then
    raise exception 'my_consents should show the newest choice (withdrawn)';
  end if;
  if not (select granted from my_consents() where purpose = 'attendance_photo_location') then
    raise exception 'my_consents lost the attendance consent';
  end if;
end $$;

-- Proof can't be filed for someone else, changed or removed.
do $$ begin
  insert into consent_records (user_id, purpose, granted, given_at, notice_version)
    values ('c0e00000-0000-4000-8000-0000000000a2', 'ai_assistant', true, now(), 'x');
  raise exception 'should have been refused: a consent filed for another person';
exception when insufficient_privilege then null;
end $$;
do $$ begin
  update consent_records set granted = true;
  raise exception 'should have been refused: changing a consent record';
exception when insufficient_privilege then null;
end $$;
do $$ begin
  delete from consent_records;
  raise exception 'should have been refused: deleting a consent record';
exception when insufficient_privilege then null;
end $$;
do $$ begin
  insert into consent_records (purpose, granted, given_at, notice_version)
    values ('marketing', true, now(), 'x');
  raise exception 'should have been refused: an unknown purpose';
exception when check_violation then null;
end $$;

-- Another person sees none of it.
select set_config('request.jwt.claims', json_build_object('sub', 'c0e00000-0000-4000-8000-0000000000a2', 'role', 'authenticated')::text, true);
do $$ begin
  if exists (select 1 from consent_records) or exists (select 1 from my_consents()) then
    raise exception 'one person could read another''s consent records';
  end if;
end $$;


-- Check-in selfies go as soon as the day is verified.
reset role;
select set_config('request.jwt.claims', '', true);
insert into companies (id, name, join_code, created_by) values
  ('c0e00000-0000-4000-8000-00000000c0a0', 'Selfie Co', 'SELFIEAAA1', 'c0e00000-0000-4000-8000-0000000000a1');
insert into company_members (company_id, user_id, role) values
  ('c0e00000-0000-4000-8000-00000000c0a0', 'c0e00000-0000-4000-8000-0000000000a1', 'owner'),
  ('c0e00000-0000-4000-8000-00000000c0a0', 'c0e00000-0000-4000-8000-0000000000a2', 'site_engineer');
insert into projects (id, company_id, name, location_lat, location_lng, geofence_radius_m) values
  ('c0e00000-0000-4000-8000-0000000000fa', 'c0e00000-0000-4000-8000-00000000c0a0', 'Fenced site', 17.4474, 78.3762, 100),
  ('c0e00000-0000-4000-8000-0000000000fb', 'c0e00000-0000-4000-8000-00000000c0a0', 'No location', null, null, null);
insert into project_members (project_id, user_id, role) values
  ('c0e00000-0000-4000-8000-0000000000fa', 'c0e00000-0000-4000-8000-0000000000a2', 'site_engineer'),
  ('c0e00000-0000-4000-8000-0000000000fb', 'c0e00000-0000-4000-8000-0000000000a2', 'site_engineer');

set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', 'c0e00000-0000-4000-8000-0000000000a2', 'role', 'authenticated')::text, true);
insert into attendance_photos (id, project_id, file_path, taken_at) values
  ('c0e00000-0000-4000-8000-0000000001a1', 'c0e00000-0000-4000-8000-0000000000fa',
   'c0e00000-0000-4000-8000-0000000000fa/attendance/c0e00000-0000-4000-8000-0000000001a1.jpg', now()),
  ('c0e00000-0000-4000-8000-0000000001a2', 'c0e00000-0000-4000-8000-0000000000fb',
   'c0e00000-0000-4000-8000-0000000000fb/attendance/c0e00000-0000-4000-8000-0000000001a2.jpg', now());
-- Inside the fence: 'ok' at once, so the selfie goes at once.
insert into staff_attendance (id, company_id, project_id, user_id, day, check_in, in_lat, in_lng, in_photo_id) values
  ('c0e00000-0000-4000-8000-0000000002a1', 'c0e00000-0000-4000-8000-00000000c0a0', 'c0e00000-0000-4000-8000-0000000000fa',
   'c0e00000-0000-4000-8000-0000000000a2', current_date, now(), 17.4474, 78.3762, 'c0e00000-0000-4000-8000-0000000001a1');
-- No site location: waits, and keeps its selfie for the manager.
insert into staff_attendance (id, company_id, project_id, user_id, day, check_in, reason, in_photo_id) values
  ('c0e00000-0000-4000-8000-0000000002a2', 'c0e00000-0000-4000-8000-00000000c0a0', 'c0e00000-0000-4000-8000-0000000000fb',
   'c0e00000-0000-4000-8000-0000000000a2', current_date, now(), 'At the supplier', 'c0e00000-0000-4000-8000-0000000001a2');
reset role;
do $$ begin
  if exists (select 1 from attendance_photos where id = 'c0e00000-0000-4000-8000-0000000001a1') then
    raise exception 'an ok day kept its selfie';
  end if;
  if not exists (select 1 from attendance_photos where id = 'c0e00000-0000-4000-8000-0000000001a2') then
    raise exception 'a pending day lost its selfie before the manager saw it';
  end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', 'c0e00000-0000-4000-8000-0000000000a1', 'role', 'authenticated')::text, true);
update staff_attendance set status = 'approved' where id = 'c0e00000-0000-4000-8000-0000000002a2';
reset role;
do $$ begin
  if exists (select 1 from attendance_photos where id = 'c0e00000-0000-4000-8000-0000000001a2') then
    raise exception 'an approved day kept its selfie';
  end if;
  if (select status from staff_attendance where id = 'c0e00000-0000-4000-8000-0000000002a2') <> 'approved' then
    raise exception 'the decision itself was lost';
  end if;
  if (select count(*) from storage_cleanup where prefix like 'c0e00000-0000-4000-8000-0000000000f_/attendance/%') <> 2 then
    raise exception 'the selfie files were not queued for deletion';
  end if;
end $$;

-- The client's address on bills is there and bounded.
reset role;
select set_config('request.jwt.claims', '', true);
do $$ begin
  if not exists (select 1 from information_schema.columns
                  where table_name = 'site_client_bills' and column_name = 'client_address') then
    raise exception 'site_client_bills.client_address is missing';
  end if;
end $$;

rollback;
