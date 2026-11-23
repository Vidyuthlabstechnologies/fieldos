-- India compliance pass, 23 November 2026.
--
-- 1. consent_records: proof of consent kept on the server.
--    The DPDP Act s.6(10) puts the burden of proving that notice was given
--    and consent was obtained on the data fiduciary. Until now the only
--    record of "I agree" to Ask FieldOS (AI) and to the check-in photo and
--    location sat in the phone's local settings, which is lost with the
--    phone. The app now appends a row here each time a person gives or
--    withdraws one of these consents while signed in. Rows are append-only
--    (no update or delete grant): a withdrawal is a new row, so the history
--    shows exactly what was in force at any time. A person reads only their
--    own rows. Rows go with the account when it is deleted (on delete
--    cascade), together with the processing they were proof for.
--
-- 2. client_bills.client_address: CGST Rules 2017 rule 46(e) asks for the
--    recipient's name, address and GSTIN on a tax invoice to a registered
--    person, and rule 46(f) asks for the address on an invoice to an
--    unregistered person above Rs 50,000. Bills stored only the client's
--    name. Nullable, so older app builds that don't send it keep working.

create table if not exists consent_records (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  purpose text not null check (purpose in ('ai_assistant', 'attendance_photo_location')),
  granted boolean not null,
  -- When the person tapped, on the phone (may be earlier than recorded_at
  -- if they were offline), and when the server received it.
  given_at timestamptz not null,
  recorded_at timestamptz not null default now(),
  -- Which notice they saw: the policy date shown in the app, and the app
  -- version and language, so the exact text can be found again.
  notice_version text not null check (char_length(notice_version) between 1 and 40),
  app_version text check (app_version is null or char_length(app_version) <= 40),
  language text check (language is null or char_length(language) <= 10),
  check (given_at <= recorded_at + interval '1 day')
);

create index if not exists consent_records_user_idx on consent_records (user_id, purpose, given_at desc);

alter table consent_records enable row level security;

drop policy if exists consent_records_own_read on consent_records;
create policy consent_records_own_read on consent_records
  for select to authenticated using (user_id = (select auth.uid()));

drop policy if exists consent_records_own_insert on consent_records;
create policy consent_records_own_insert on consent_records
  for insert to authenticated with check (user_id = (select auth.uid()));

revoke all on consent_records from anon, authenticated;
grant select, insert on consent_records to authenticated;

-- The latest choice per purpose, for the person themselves (and for the
-- ai-assistant function, which calls it with the caller's own token).
create or replace function my_consents()
returns table (purpose text, granted boolean, given_at timestamptz, notice_version text)
language sql stable security invoker set search_path = public as $$
  select distinct on (c.purpose) c.purpose, c.granted, c.given_at, c.notice_version
    from consent_records c
   where c.user_id = (select auth.uid())
   order by c.purpose, c.given_at desc, c.id desc;
$$;

revoke all on function my_consents() from public, anon;
grant execute on function my_consents() to authenticated;

alter table client_bills add column if not exists client_address text
  check (client_address is null or char_length(client_address) <= 300);
