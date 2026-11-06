-- Launch hardening: join codes, approvals, removing a member, bug reports.
--
-- 1. Join codes could be guessed without limit. join_company() answered a
--    signed-in account as fast as it asked, and a direct insert into
--    companies with a chosen join_code said, by its unique violation,
--    whether that code was taken. Now:
--      - each account gets 10 wrong codes an hour (join_attempts). A wrong
--        code is recorded and the function returns an error object rather
--        than raising, because a raise would roll the record back too;
--      - the direct insert policy on companies is gone. The app has always
--        created companies through ensure_company(), which still works;
--      - new codes are 10 characters of Crockford base32 from pgcrypto's
--        random bytes (50 bits; random() is not a secure generator), and a
--        typed code accepts O for 0 and I or L for 1, since codes get read
--        out over the phone. Codes already shared keep working.
-- 2. Approvals with no project could be read and changed by every account
--    of every company, and any member could approve or reject. Now an
--    approval belongs to a project the caller can see, a request is raised
--    as the caller, and only the owner or a project manager decides.
-- 3. remove_member(): the owner can take someone who has left off the
--    company. Before, a member who joined could never be removed.
-- 4. Bug reports are capped (10 an hour per account, 200 an hour in all).
--    Anyone with the app's public key can send one, and each becomes a
--    GitHub issue. A report over the cap waits on the phone and is sent
--    on a later try (lib/services/bug_report_service.dart).

create extension if not exists pgcrypto with schema extensions;

-- --- 1. Join codes ----------------------------------------------------------

create table if not exists join_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  attempted_at timestamptz not null default now()
);
create index if not exists join_attempts_by_user on join_attempts (user_id, attempted_at desc);
-- Only join_company() (security definer) touches it: RLS on, no policies.
alter table join_attempts enable row level security;
revoke all on table join_attempts from anon, authenticated;

create or replace function new_join_code()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  -- 32 symbols, so one random byte maps to one symbol without bias.
  v_alphabet constant text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  v_bytes constant bytea := extensions.gen_random_bytes(10);
  v_code text := '';
begin
  for i in 0..9 loop
    v_code := v_code || substr(v_alphabet, get_byte(v_bytes, i) % 32 + 1, 1);
  end loop;
  return v_code;
end;
$$;

-- Called only from the security-definer functions that hand out codes.
revoke all on function new_join_code() from public, anon, authenticated;

create or replace function join_company(p_code text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_code text := translate(upper(regexp_replace(coalesce(p_code, ''), '[^0-9A-Za-z]', '', 'g')), 'OIL', '011');
  v_company companies%rowtype;
  v_role text;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  -- One join at a time per account, so a burst of parallel calls cannot
  -- all pass the count below before any of them is recorded.
  perform pg_advisory_xact_lock(hashtextextended('join_company:' || v_uid::text, 0));

  if (select count(*) from join_attempts
      where user_id = v_uid and attempted_at > now() - interval '1 hour') >= 10 then
    return json_build_object('error', 'too_many_attempts');
  end if;

  select * into v_company from companies where join_code = v_code;
  if not found then
    insert into join_attempts (user_id) values (v_uid);
    delete from join_attempts where attempted_at < now() - interval '1 day';
    return json_build_object('error', 'invalid_join_code');
  end if;

  insert into company_members (company_id, user_id, role)
  values (v_company.id, v_uid, 'site_engineer')
  on conflict (company_id, user_id) do nothing;

  select role into v_role from company_members
  where company_id = v_company.id and user_id = v_uid;

  return json_build_object('company_id', v_company.id, 'name', v_company.name, 'role', v_role);
end;
$$;

revoke all on function join_company(text) from public, anon;
grant execute on function join_company(text) to authenticated;

drop policy if exists "authenticated users can create a company" on companies;

-- --- 2. Approvals -----------------------------------------------------------

drop policy if exists "project members can read approvals" on approvals;
drop policy if exists "project members can create approvals" on approvals;
drop policy if exists "project members can decide approvals" on approvals;

create policy "project members can read approvals" on approvals for select
  to authenticated using ((select has_project_access(project_id)));

create policy "project members can ask for approval" on approvals for insert
  to authenticated with check (
    (select has_project_access(project_id))
    and requested_by = (select auth.uid())
    and status = 'pending'
    and approver_id is null
    and decided_at is null
  );

create policy "owner or project manager decides approvals" on approvals for update
  to authenticated
  using ((select is_project_owner_or_pm(project_id)))
  with check (
    (select is_project_owner_or_pm(project_id))
    and (approver_id is null or approver_id = (select auth.uid()))
  );

-- --- 3. Removing a member ---------------------------------------------------

create or replace function remove_member(p_company_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if company_role(p_company_id) is distinct from 'owner' then
    raise exception 'only the company owner can remove people' using errcode = '42501';
  end if;
  if exists (select 1 from company_members
             where company_id = p_company_id and user_id = p_user_id and role = 'owner') then
    raise exception 'the owner cannot be removed' using errcode = '42501';
  end if;
  -- Explicit per-project access to this company's sites goes too, or it
  -- would keep them in.
  delete from project_members
  where user_id = p_user_id
    and project_id in (select id from projects where company_id = p_company_id);
  delete from company_members where company_id = p_company_id and user_id = p_user_id;
end;
$$;

revoke all on function remove_member(uuid, uuid) from public, anon;
grant execute on function remove_member(uuid, uuid) to authenticated;

-- --- 4. Bug reports ---------------------------------------------------------

create index if not exists bug_reports_by_time on bug_reports (created_at desc);
create index if not exists bug_reports_by_user on bug_reports (user_id, created_at desc) where user_id is not null;

create or replace function bug_reports_throttle()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.user_id is not null and (
    select count(*) from bug_reports
    where user_id = new.user_id and created_at > now() - interval '1 hour'
  ) >= 10 then
    raise exception 'too many bug reports' using errcode = 'P0001';
  end if;
  if (select count(*) from bug_reports where created_at > now() - interval '1 hour') >= 200 then
    raise exception 'too many bug reports' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

revoke all on function bug_reports_throttle() from public, anon, authenticated;

drop trigger if exists bug_reports_throttle on bug_reports;
create trigger bug_reports_throttle before insert on bug_reports
  for each row execute function bug_reports_throttle();
