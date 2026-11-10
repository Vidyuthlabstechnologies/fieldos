-- Company plans (supabase/migrations/20261111130000_company_plans.sql): only
-- the service role grants them, a plan covers every member of its company
-- for its dates, a plan granted by email reaches the owner only with a
-- confirmed email and attaches to the company they own, and active sites
-- are counted. Everything rolls back.
\set ON_ERROR_STOP on
begin;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000c1', 'owner@builder.example', now()),
  ('00000000-0000-0000-0000-0000000000c2', 'engineer@builder.example', now()),
  ('00000000-0000-0000-0000-0000000000c3', 'Unconfirmed@Builder.example', null),
  ('00000000-0000-0000-0000-0000000000c4', 'other@elsewhere.example', now());

-- The owner registers a company and adds two sites (one finished).
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000c1';
select ensure_company('00000000-0000-0000-0000-00000000c0a1', 'Builder One');
do $$
begin
  if json_array_length(public.my_company_plans()) <> 0 then raise exception 'no plan yet'; end if;
end $$;
insert into projects (id, company_id, name, status) values
  ('00000000-0000-0000-0000-00000000c0b1', '00000000-0000-0000-0000-00000000c0a1', 'Tower A', 'active'),
  ('00000000-0000-0000-0000-00000000c0b2', '00000000-0000-0000-0000-00000000c0a1', 'Villa', 'completed'),
  ('00000000-0000-0000-0000-00000000c0b3', '00000000-0000-0000-0000-00000000c0a1', 'Tower B', 'on_hold');

-- Phones can't grant, read or end plans.
do $$
begin
  begin
    perform public.grant_company_plan('enterprise', '2099-01-01', p_owner_email => 'owner@builder.example');
    raise exception 'an app user granted a plan';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from public.company_plans;
    raise exception 'an app user read company_plans';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from public.company_plan_usage;
    raise exception 'an app user read company_plan_usage';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- The team grants Site Pro by the owner's email (mixed case, padded).
set local role service_role;
select public.grant_company_plan('site_pro', public.ist_today() + 365, p_owner_email => '  Owner@Builder.example ',
                                 p_invoice_ref => 'INV-TEST-1') as plan_id \gset
-- And one by email to an account that never confirmed it.
select public.grant_company_plan('pilot', public.ist_today() + 60, p_owner_email => 'unconfirmed@builder.example');
-- A plan that starts next week covers nobody yet.
select public.grant_company_plan('business', public.ist_today() + 400, p_owner_email => 'other@elsewhere.example',
                                 p_starts_on => public.ist_today() + 7);
do $$
begin
  if (select site_limit from public.company_plans where invoice_ref = 'INV-TEST-1') <> 3 then
    raise exception 'Site Pro defaults to 3 sites';
  end if;
  if (select owner_email from public.company_plans where invoice_ref = 'INV-TEST-1') <> 'owner@builder.example' then
    raise exception 'emails are kept trimmed and lower case';
  end if;
  if not public.company_plan_covers('00000000-0000-0000-0000-0000000000c1') then
    raise exception 'a plan granted by email covers its confirmed owner';
  end if;
  if public.company_plan_covers('00000000-0000-0000-0000-0000000000c3') then
    raise exception 'an unconfirmed email must not be covered';
  end if;
  if public.company_plan_covers('00000000-0000-0000-0000-0000000000c4') then
    raise exception 'a plan that has not started covers nobody';
  end if;
  begin
    perform public.grant_company_plan('site_pro', '2099-01-01');
    raise exception 'a plan with no company and no email was accepted';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.grant_company_plan('gold', '2099-01-01', p_owner_email => 'x@example.com');
    raise exception 'an unknown plan was accepted';
  exception when check_violation then null;
  end;
end $$;
reset role;

-- The owner asks: the plan attaches to their company, with its site count.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000c1';
do $$
declare
  v json := public.my_company_plans();
begin
  if json_array_length(v) <> 1 then raise exception 'one plan expected, got %', v; end if;
  if v->0->>'company_id' <> '00000000-0000-0000-0000-00000000c0a1' then raise exception 'plan not attached: %', v; end if;
  if v->0->>'plan' <> 'site_pro' or (v->0->>'site_limit')::int <> 3 then raise exception 'wrong plan: %', v; end if;
  if (v->0->>'active_sites')::int <> 2 then raise exception 'active and on-hold sites count, completed do not: %', v; end if;
end $$;

-- A site engineer joins and is covered with no store subscription.
reset role;
select join_code as code from companies where id = '00000000-0000-0000-0000-00000000c0a1' \gset
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c2', true);
select join_company(:'code');
do $$
declare
  v json := public.my_company_plans();
begin
  if json_array_length(v) <> 1 or v->0->>'company_name' <> 'Builder One' then
    raise exception 'a member is covered by the company plan: %', v;
  end if;
end $$;

-- Someone else sees nothing.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c4', true);
do $$
begin
  if json_array_length(public.my_company_plans()) <> 0 then raise exception 'a stranger saw a plan'; end if;
end $$;

-- The unconfirmed account can't claim the pilot granted to its email.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c3', true);
do $$
begin
  if json_array_length(public.my_company_plans()) <> 0 then raise exception 'an unconfirmed email claimed a plan'; end if;
end $$;
reset role;

-- The team ends the plan: nobody is covered from today.
set local role service_role;
select public.end_company_plan(:'plan_id');
do $$
begin
  if public.company_plan_covers('00000000-0000-0000-0000-0000000000c2') then
    raise exception 'an ended plan still covers a member';
  end if;
  if (select covers_today from public.company_plan_usage where plan_id = (select id from public.company_plans where invoice_ref = 'INV-TEST-1')) then
    raise exception 'usage view says an ended plan covers today';
  end if;
end $$;
reset role;

rollback;
\echo company plans OK
