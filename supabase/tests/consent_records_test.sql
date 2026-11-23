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

-- The client's address on bills is there and bounded.
reset role;
select set_config('request.jwt.claims', '', true);
do $$ begin
  if not exists (select 1 from information_schema.columns
                  where table_name = 'client_bills' and column_name = 'client_address') then
    raise exception 'client_bills.client_address is missing';
  end if;
end $$;

rollback;
