-- Paid plans. A company is on 'free' (up to free_member_limit() people on
-- the cloud) or 'team' (unlimited) while plan_expires_at is in the future.
--
-- Only the server changes a plan: the revenuecat-webhook edge function
-- (supabase/functions/revenuecat-webhook) writes it with the service role
-- after Google Play / the App Store confirm a purchase, renewal or expiry.
-- No client-callable function can set it, and companies has no client
-- update policy for these columns.

alter table companies add column if not exists plan text not null default 'free'
  check (plan in ('free', 'team'));
alter table companies add column if not exists plan_expires_at timestamptz;

-- Clients may insert companies (RLS allows it) and the plan columns must
-- not ride along: anything but the service role gets 'free' on insert and
-- keeps the stored plan on update.
create or replace function guard_company_plan()
returns trigger
language plpgsql
as $$
begin
  if coalesce(auth.role(), '') = 'service_role' or current_user in ('postgres', 'supabase_admin') and auth.uid() is null then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.plan := 'free';
    new.plan_expires_at := null;
  else
    new.plan := old.plan;
    new.plan_expires_at := old.plan_expires_at;
  end if;
  return new;
end;
$$;

drop trigger if exists guard_company_plan on companies;
create trigger guard_company_plan before insert or update on companies
  for each row execute function guard_company_plan();

create or replace function free_member_limit()
returns int
language sql
immutable
as $$ select 3 $$;

create or replace function company_on_paid_plan(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from companies
    where id = p_company_id and plan = 'team'
      and (plan_expires_at is null or plan_expires_at > now())
  );
$$;

-- What the Team & sync screen shows. Members only.
create or replace function company_plan(p_company_id uuid)
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_paid boolean;
  v_members int;
  v_expires timestamptz;
begin
  if company_role(p_company_id) is null then
    raise exception 'not a member of this company' using errcode = '42501';
  end if;
  v_paid := company_on_paid_plan(p_company_id);
  select count(*) into v_members from company_members where company_id = p_company_id;
  select plan_expires_at into v_expires from companies where id = p_company_id;
  return json_build_object(
    'plan', case when v_paid then 'team' else 'free' end,
    'expires_at', case when v_paid then v_expires end,
    'members', v_members,
    'member_limit', case when v_paid then null else free_member_limit() end
  );
end;
$$;

-- join_company now refuses a new member once a free company is full.
-- Existing members re-joining are unaffected.
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

  if not exists (select 1 from company_members where company_id = v_company.id and user_id = v_uid)
     and not company_on_paid_plan(v_company.id)
     and (select count(*) from company_members where company_id = v_company.id) >= free_member_limit()
  then
    raise exception 'this company has reached the free plan limit of % people; the owner can upgrade to Team',
      free_member_limit() using errcode = 'P0001', hint = 'plan_limit';
  end if;

  insert into company_members (company_id, user_id, role)
  values (v_company.id, v_uid, 'site_engineer')
  on conflict (company_id, user_id) do nothing;

  select role into v_role from company_members
  where company_id = v_company.id and user_id = v_uid;

  return json_build_object('company_id', v_company.id, 'name', v_company.name, 'role', v_role);
end;
$$;

revoke all on function company_plan(uuid) from public, anon;
grant execute on function company_plan(uuid) to authenticated;
revoke all on function company_on_paid_plan(uuid) from public, anon;
grant execute on function company_on_paid_plan(uuid) to authenticated;
revoke all on function join_company(text) from public, anon;
grant execute on function join_company(text) to authenticated;
