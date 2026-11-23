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
-- 2. site_client_bills.client_address: CGST Rules 2017 rule 46(e) asks for the
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

alter table site_client_bills add column if not exists client_address text
  check (client_address is null or char_length(client_address) <= 300);

-- 3. Check-in selfies are deleted as soon as the day is verified.
--    Company decision (23 Nov 2026): a selfie is kept only while a manager
--    still has to look at it. A day inside the site ('ok') is verified by
--    the GPS check at once; a day outside it ('pending') is verified when
--    an owner or project manager approves or turns it down. From then on
--    only the result is kept (status, who decided, when, the note). This
--    is data minimisation and erasure once the purpose is served (DPDP
--    Act s.8(7)). Apps from this version on never upload an 'ok' day's
--    selfie at all; these triggers also catch older apps and any upload
--    that arrives after the decision.
--
--    The photo ids stay on staff_attendance (the guard keeps a check-in
--    as it was made); they just no longer find a photo. Files are queued
--    in storage_cleanup and removed by the account-cleanup function, which
--    the app nudges after a decision and the daily log job also calls.
--    Labour punch photos (site_attendance.photo_id) are not selfies and
--    are not touched.

-- storage_cleanup held whole site folders; it now also takes one
-- attendance photo file.
alter table storage_cleanup drop constraint if exists storage_cleanup_prefix_check;
alter table storage_cleanup add constraint storage_cleanup_prefix_check
  check (prefix ~ '^[0-9a-f-]{36}/$' or prefix ~ '^[0-9a-f-]{36}/attendance/[0-9a-f-]{36}\.[a-z]{3,4}$');

create or replace function drop_verified_selfies(p_ids uuid[])
returns int language plpgsql security definer set search_path = public as $$
declare
  n int;
begin
  insert into storage_cleanup (bucket, prefix)
    select 'documents', p.file_path from attendance_photos p
     where p.id = any (p_ids)
       and p.file_path ~ '^[0-9a-f-]{36}/attendance/[0-9a-f-]{36}\.[a-z]{3,4}$'
    on conflict do nothing;
  delete from attendance_photos where id = any (p_ids);
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function drop_verified_selfies(uuid[]) from public, anon, authenticated;

create or replace function staff_attendance_drop_selfies()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status <> 'pending' then
    perform drop_verified_selfies(array_remove(array[new.in_photo_id, new.out_photo_id], null));
  end if;
  return null;
end $$;
revoke all on function staff_attendance_drop_selfies() from public, anon, authenticated;

drop trigger if exists staff_attendance_drop_selfies on staff_attendance;
create trigger staff_attendance_drop_selfies after insert or update on staff_attendance
  for each row execute function staff_attendance_drop_selfies();

-- A selfie uploaded after its day was already decided (an older app, or a
-- phone that was offline) goes straight away.
create or replace function attendance_photos_drop_if_verified()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from staff_attendance a
              where (a.in_photo_id = new.id or a.out_photo_id = new.id) and a.status <> 'pending') then
    perform drop_verified_selfies(array[new.id]);
  end if;
  return null;
end $$;
revoke all on function attendance_photos_drop_if_verified() from public, anon, authenticated;

drop trigger if exists attendance_photos_drop_if_verified on attendance_photos;
create trigger attendance_photos_drop_if_verified after insert on attendance_photos
  for each row execute function attendance_photos_drop_if_verified();

-- Selfies of days decided before this migration are NOT deleted here, so
-- that deploying it changes nothing irreversible by itself. After the
-- company confirms, the deploy runs once:
--   select purge_verified_selfies();
create or replace function purge_verified_selfies()
returns int language sql security definer set search_path = public as $$
  select drop_verified_selfies(coalesce(array_agg(id), '{}'))
    from (select a.in_photo_id as id from staff_attendance a where a.status <> 'pending' and a.in_photo_id is not null
          union
          select a.out_photo_id from staff_attendance a where a.status <> 'pending' and a.out_photo_id is not null) x;
$$;
revoke all on function purge_verified_selfies() from public, anon, authenticated;

-- 4. A private bucket for the one-year copy of the server logs.
--    The Supabase plan keeps API, auth, database and function logs for a
--    day. CERT-In's directions ask for 180 days kept in India and the DPDP
--    Rules for a year, so tools/export_logs.py (run by the system-logs
--    workflow every 6 hours) copies them here, in this project's Mumbai
--    region, and removes copies older than 400 days. The bucket has no
--    policies, so no app user can list or read it; only the service role
--    (the workflow) can.
insert into storage.buckets (id, name, public, file_size_limit)
values ('system-logs', 'system-logs', false, 52428800)
on conflict (id) do nothing;
