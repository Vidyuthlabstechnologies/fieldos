-- Company plans: FieldOS for builder firms, sold by GST invoice outside the
-- app stores (Site Pro, Business, Enterprise, and a paid pilot). One plan
-- covers everyone in the company, with no limit on people, and a limit on
-- active sites.
--
-- The FieldOS team switches a plan on with grant_company_plan() once the
-- invoice is paid (service role only: the Supabase SQL editor, or a script
-- with the service key). Nothing a phone can call creates, extends or
-- changes a plan. The ₹999 per-person store subscription is untouched and
-- still works on its own.
--
-- Store rules: the apps show no price and no way to buy a company plan.
-- People who already have one sign in and get in (Apple 3.1.3(c),
-- enterprise services sold to organisations for their staff).
--
-- A plan can be granted before the company is on the cloud, by the owner's
-- email: the usual sale is "invoice paid, then the owner installs the app".
-- Such a plan lets that owner past the paywall once they sign in to Team &
-- sync with that (confirmed) email, and attaches itself to the first company
-- they register as owner.
--
-- "Active site" = a project that is not completed (planning, active and on
-- hold all count), so putting sites on hold can't stretch the limit. The
-- app stops a new or reopened site past the limit; the server does not
-- refuse it, because a phone that was offline would then be stuck with a
-- site it can never send. company_plan_usage shows the team any company
-- over its limit.

create table if not exists public.company_plans (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references public.companies (id) on delete cascade,
  owner_email text check (owner_email is null or owner_email = lower(owner_email)),
  plan text not null check (plan in ('pilot', 'site_pro', 'business', 'enterprise')),
  -- null = no limit (enterprise deals can be unlimited)
  site_limit integer check (site_limit is null or site_limit > 0),
  starts_on date not null,
  -- the last day the plan covers, in India time
  ends_on date not null,
  invoice_ref text,
  notes text,
  created_at timestamptz not null default now(),
  check (company_id is not null or owner_email is not null),
  check (ends_on >= starts_on)
);

create index if not exists company_plans_by_company on public.company_plans (company_id, ends_on desc)
  where company_id is not null;
create index if not exists company_plans_unclaimed on public.company_plans (owner_email)
  where company_id is null;

-- Only the security-definer functions below touch it.
alter table public.company_plans enable row level security;
revoke all on table public.company_plans from anon, authenticated;

create or replace function public.ist_today()
returns date
language sql
stable
as $$
  select (now() at time zone 'Asia/Kolkata')::date;
$$;

create or replace function public.company_active_sites(p_company_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer from projects where company_id = p_company_id and status <> 'completed';
$$;

-- Several rows can cover today (a renewal paid early, an upgrade): the
-- biggest site limit wins, and the latest end date.
create or replace function public.company_plan_now(p_company_id uuid)
returns table (plan text, site_limit integer, ends_on date)
language sql
stable
security definer
set search_path = public
as $$
  select
    (array_agg(cp.plan order by cp.site_limit desc nulls first, cp.ends_on desc))[1],
    case when bool_or(cp.site_limit is null) then null else max(cp.site_limit) end,
    max(cp.ends_on)
  from company_plans cp
  where cp.company_id = p_company_id
    and public.ist_today() between cp.starts_on and cp.ends_on
  having count(*) > 0;
$$;

-- The phone's question: which company plans cover me right now? A json
-- array, one entry per company (company_id is null for a plan granted to my
-- email whose company is not on the cloud yet). Empty when none. Also
-- attaches a plan granted to my email to the company I own, the first
-- time I ask after registering it.
create or replace function public.my_company_plans()
returns json
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_owned uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  -- Only a confirmed email may claim a plan granted by email.
  select lower(email) into v_email from auth.users where id = v_uid and email_confirmed_at is not null;

  if v_email is not null then
    select m.company_id into v_owned
    from company_members m
    where m.user_id = v_uid and m.role = 'owner'
    order by m.created_at
    limit 1;
    if v_owned is not null then
      update company_plans set company_id = v_owned where company_id is null and owner_email = v_email;
    end if;
  end if;

  return coalesce((
    select json_agg(x order by x.ends_on desc)
    from (
      select m.company_id, c.name as company_name, p.plan, p.site_limit, p.ends_on,
             public.company_active_sites(m.company_id) as active_sites
      from company_members m
      join companies c on c.id = m.company_id
      cross join lateral public.company_plan_now(m.company_id) p
      where m.user_id = v_uid
      union all
      select null::uuid, null::text, cp.plan, cp.site_limit, cp.ends_on, 0
      from company_plans cp
      where v_email is not null and cp.company_id is null and cp.owner_email = v_email
        and public.ist_today() between cp.starts_on and cp.ends_on
    ) x
  ), '[]'::json);
end;
$$;

-- For the ai-assistant edge function: is this account covered by a company
-- plan (as a member, or as the owner a plan was granted to by email)?
create or replace function public.company_plan_covers(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from company_members m
    where m.user_id = p_user and exists (select 1 from public.company_plan_now(m.company_id))
  ) or exists (
    select 1 from company_plans cp
    join auth.users u on u.id = p_user and u.email_confirmed_at is not null and lower(u.email) = cp.owner_email
    where cp.company_id is null and public.ist_today() between cp.starts_on and cp.ends_on
  );
$$;

-- The FieldOS team, after an invoice is paid. Give the owner's email (the
-- usual way: it works before and after their company is on the cloud) or
-- the company id from company_plan_usage / the companies table. Site limits default to the
-- plan's: pilot 1, Site Pro 3, Business 10, Enterprise none.
create or replace function public.grant_company_plan(
  p_plan text,
  p_ends_on date,
  p_company_id uuid default null,
  p_owner_email text default null,
  p_site_limit integer default null,
  p_invoice_ref text default null,
  p_starts_on date default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_email text := nullif(lower(trim(coalesce(p_owner_email, ''))), '');
begin
  if p_company_id is null and v_email is null then
    raise exception 'give the company id or the owner''s email' using errcode = '22023';
  end if;
  if p_company_id is not null and not exists (select 1 from companies where id = p_company_id) then
    raise exception 'no company with id %', p_company_id using errcode = 'P0002';
  end if;
  insert into company_plans (company_id, owner_email, plan, site_limit, starts_on, ends_on, invoice_ref, notes)
  values (
    p_company_id,
    v_email,
    p_plan,
    coalesce(p_site_limit, case p_plan when 'pilot' then 1 when 'site_pro' then 3 when 'business' then 10 end),
    coalesce(p_starts_on, public.ist_today()),
    p_ends_on,
    p_invoice_ref,
    p_notes
  )
  returning id into v_id;
  return v_id;
end;
$$;

-- Ends a plan early (refund, plan replaced). It stops covering anyone today.
create or replace function public.end_company_plan(p_plan_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update company_plans
  set ends_on = public.ist_today() - 1,
      starts_on = least(starts_on, public.ist_today() - 1)
  where id = p_plan_id;
$$;

-- For the FieldOS team: every plan with its company's use, newest first.
create or replace view public.company_plan_usage as
  select cp.id as plan_id, cp.company_id, c.name as company_name, cp.owner_email, cp.plan, cp.site_limit,
         case when cp.company_id is null then null else public.company_active_sites(cp.company_id) end as active_sites,
         (select count(*) from company_members m where m.company_id = cp.company_id)::integer as people,
         cp.starts_on, cp.ends_on, public.ist_today() between cp.starts_on and cp.ends_on as covers_today,
         cp.invoice_ref
  from company_plans cp
  left join companies c on c.id = cp.company_id
  order by cp.ends_on desc;

revoke all on public.company_plan_usage from anon, authenticated;

revoke all on function public.ist_today() from public, anon;
grant execute on function public.ist_today() to authenticated, service_role;
revoke all on function public.company_active_sites(uuid) from public, anon, authenticated;
revoke all on function public.company_plan_now(uuid) from public, anon, authenticated;
revoke all on function public.my_company_plans() from public, anon;
grant execute on function public.my_company_plans() to authenticated;
revoke all on function public.company_plan_covers(uuid) from public, anon, authenticated;
revoke all on function public.grant_company_plan(text, date, uuid, text, integer, text, date, text)
  from public, anon, authenticated;
revoke all on function public.end_company_plan(uuid) from public, anon, authenticated;
grant execute on function public.company_active_sites(uuid) to service_role;
grant execute on function public.company_plan_now(uuid) to service_role;
grant execute on function public.company_plan_covers(uuid) to service_role;
grant execute on function public.grant_company_plan(text, date, uuid, text, integer, text, date, text) to service_role;
grant execute on function public.end_company_plan(uuid) to service_role;
grant select on public.company_plan_usage to service_role;
