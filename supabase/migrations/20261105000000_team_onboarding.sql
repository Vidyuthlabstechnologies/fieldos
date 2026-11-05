-- Team onboarding: how a real company gets onto the cloud backend.
--
-- Before this migration, nothing in the app ever created a `companies` or
-- `company_members` row on the server -- every sync test seeded them with
-- the service_role admin client. In a real install, the owner's first
-- project push was therefore rejected by RLS ("owner/pm can create
-- projects" requires a membership that could never exist), and the
-- owner -> member bootstrap was a chicken-and-egg: the only insert policy
-- on company_members requires already being an owner/PM of that company.
--
-- Three security-definer RPCs close that gap without loosening any table
-- policy:
--   ensure_company(id, name)  -- owner's device: registers its LOCAL
--                                company id on the server (so every local
--                                row's company_id/project_id already
--                                matches) and makes the caller its owner.
--   join_company(code)        -- a colleague's device: joins with the
--                                owner's join code as a site engineer.
--   company_roster(id)        -- the Team screen: members with emails.
-- plus set_member_role / regenerate_join_code for the owner.

alter table companies add column if not exists join_code text unique;
alter table companies add column if not exists created_by uuid references auth.users(id);

-- 10 hex chars = 40 bits; joining also needs a signed-in account, so this
-- is not the only barrier. Uppercase so it reads cleanly over the phone.
create or replace function new_join_code()
returns text
language sql
volatile
as $$
  select upper(substr(md5(random()::text || clock_timestamp()::text), 1, 10));
$$;

create or replace function ensure_company(p_company_id uuid, p_name text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_code text;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  if not exists (select 1 from companies where id = p_company_id) then
    insert into companies (id, name, join_code, created_by)
    values (p_company_id, p_name, new_join_code(), v_uid);
    insert into company_members (company_id, user_id, role)
    values (p_company_id, v_uid, 'owner');
  end if;

  select role into v_role from company_members
  where company_id = p_company_id and user_id = v_uid;
  if v_role is null then
    -- The id is a random v4 UUID generated on the owner's phone; anyone
    -- else presenting it without a membership is not let in.
    raise exception 'this company is already registered to another account' using errcode = '42501';
  end if;

  select join_code into v_code from companies where id = p_company_id;
  if v_code is null then
    update companies set join_code = new_join_code() where id = p_company_id
    returning join_code into v_code;
  end if;

  return json_build_object(
    'company_id', p_company_id,
    'role', v_role,
    'join_code', case when v_role in ('owner', 'project_manager') then v_code end
  );
end;
$$;

create or replace function join_company(p_code text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_company companies%rowtype;
  v_role text;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select * into v_company from companies
  where join_code = upper(regexp_replace(coalesce(p_code, ''), '[^0-9A-Za-z]', '', 'g'));
  if not found then
    raise exception 'invalid join code' using errcode = 'P0002';
  end if;

  insert into company_members (company_id, user_id, role)
  values (v_company.id, v_uid, 'site_engineer')
  on conflict (company_id, user_id) do nothing;

  select role into v_role from company_members
  where company_id = v_company.id and user_id = v_uid;

  return json_build_object('company_id', v_company.id, 'name', v_company.name, 'role', v_role);
end;
$$;

create or replace function company_roster(p_company_id uuid)
returns table (user_id uuid, email text, role text, joined_at timestamptz)
language sql
security definer
set search_path = public
stable
as $$
  select m.user_id, u.email::text, m.role, m.created_at
  from company_members m
  join auth.users u on u.id = m.user_id
  where m.company_id = p_company_id
    and is_company_member(p_company_id)
  order by m.created_at;
$$;

create or replace function set_member_role(p_company_id uuid, p_user_id uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if company_role(p_company_id) is distinct from 'owner' then
    raise exception 'only the company owner can change roles' using errcode = '42501';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'owners cannot change their own role' using errcode = '42501';
  end if;
  if p_role not in ('owner', 'project_manager', 'site_engineer') then
    raise exception 'unknown role %', p_role using errcode = '22023';
  end if;
  update company_members set role = p_role
  where company_id = p_company_id and user_id = p_user_id;
end;
$$;

create or replace function regenerate_join_code(p_company_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if company_role(p_company_id) is distinct from 'owner' then
    raise exception 'only the company owner can reset the join code' using errcode = '42501';
  end if;
  update companies set join_code = new_join_code() where id = p_company_id
  returning join_code into v_code;
  return v_code;
end;
$$;

revoke all on function ensure_company(uuid, text) from public, anon;
revoke all on function join_company(text) from public, anon;
revoke all on function company_roster(uuid) from public, anon;
revoke all on function set_member_role(uuid, uuid, text) from public, anon;
revoke all on function regenerate_join_code(uuid) from public, anon;
grant execute on function ensure_company(uuid, text) to authenticated;
grant execute on function join_company(text) to authenticated;
grant execute on function company_roster(uuid) to authenticated;
grant execute on function set_member_role(uuid, uuid, text) to authenticated;
grant execute on function regenerate_join_code(uuid) to authenticated;

-- Project visibility for a small contractor: every member of the company
-- sees every company project (a site engineer who joins with the code
-- immediately sees the sites they work on, with no per-project assignment
-- step the owner would have to remember). Writes stay role-gated exactly as
-- before -- creating projects/tasks/POs still needs owner or PM. Explicit
-- project_members rows keep working for anyone outside the company.
create or replace function has_project_access(p_project_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from projects p
    where p.id = p_project_id
      and (
        company_role(p.company_id) is not null
        or exists (
          select 1 from project_members pm
          where pm.project_id = p_project_id
            and pm.user_id = (select auth.uid())
        )
      )
  );
$$;

-- projects had select + insert policies but no update policy, so a site
-- location / geofence set on the owner's phone was "pushed" successfully
-- (PostgREST matches zero rows under RLS and reports no error) and never
-- reached anyone else -- the same silent failure work_orders once had.
create policy "owner/pm can update projects" on projects for update
  to authenticated using ((select is_company_owner_or_pm(company_id)));
