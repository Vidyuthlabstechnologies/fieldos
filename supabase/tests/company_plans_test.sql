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

-- People join only with the join code (join_company) or as a company's
-- creator (ensure_company). A project manager can't write membership rows
-- directly: not to make another account of theirs the owner, and not to
-- put an outsider under the company plan.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', true);
select set_member_role('00000000-0000-0000-0000-00000000c0a1', '00000000-0000-0000-0000-0000000000c2', 'project_manager');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c2', true);
do $$
begin
  begin
    insert into company_members (company_id, user_id, role)
    values ('00000000-0000-0000-0000-00000000c0a1', '00000000-0000-0000-0000-0000000000c4', 'owner');
    raise exception 'a project manager made another account the owner';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into company_members (company_id, user_id, role)
    values ('00000000-0000-0000-0000-00000000c0a1', '00000000-0000-0000-0000-0000000000c4', 'site_engineer');
    raise exception 'a project manager added an outsider without the join code';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
do $$
begin
  if public.company_plan_covers('00000000-0000-0000-0000-0000000000c4') then
    raise exception 'an outsider ended up under the company plan';
  end if;
end $$;
set local role authenticated;

-- The unconfirmed account can't claim the pilot granted to its email.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c3', true);
do $$
begin
  if json_array_length(public.my_company_plans()) <> 0 then raise exception 'an unconfirmed email claimed a plan'; end if;
end $$;
reset role;

-- The server holds the site limit across all the company's sites
-- (20261114130000_site_limit_enforced.sql): Site Pro covers 3, and Tower A
-- and Tower B are open.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', true);
insert into projects (id, company_id, name, status) values
  ('00000000-0000-0000-0000-00000000c0b4', '00000000-0000-0000-0000-00000000c0a1', 'Tower C', 'planning');
do $$
declare
  v_state text;
  v_message text;
begin
  -- A fourth active site is refused, with the distinctive error.
  begin
    insert into projects (id, company_id, name, status) values
      ('00000000-0000-0000-0000-00000000c0b5', '00000000-0000-0000-0000-00000000c0a1', 'Tower D', 'active');
    raise exception 'a fourth active site was accepted on Site Pro';
  exception when raise_exception then
    get stacked diagnostics v_state = returned_sqlstate, v_message = message_text;
    if v_state <> 'P0001' or v_message not like 'site_limit_reached%' then raise; end if;
    if v_message <> 'site_limit_reached: limit 3, active 3' then raise exception 'unexpected message: %', v_message; end if;
  end;
  -- So is one with no status (the default, planning, counts).
  begin
    insert into projects (id, company_id, name) values
      ('00000000-0000-0000-0000-00000000c0b5', '00000000-0000-0000-0000-00000000c0a1', 'Tower D');
    raise exception 'a default-status site went past the limit';
  exception when raise_exception then null;
  end;
  -- Reopening the finished Villa is refused.
  begin
    update projects set status = 'active' where id = '00000000-0000-0000-0000-00000000c0b2';
    raise exception 'a completed site was reopened past the limit';
  exception when raise_exception then null;
  end;
  -- An upsert of a new active site is refused too.
  begin
    insert into projects (id, company_id, name, status) values
      ('00000000-0000-0000-0000-00000000c0b5', '00000000-0000-0000-0000-00000000c0a1', 'Tower D', 'active')
    on conflict (id) do update set status = excluded.status;
    raise exception 'an upsert went past the limit';
  exception when raise_exception then null;
  end;
  -- A finished site can still be added, and open sites edited and paused.
  insert into projects (id, company_id, name, status) values
    ('00000000-0000-0000-0000-00000000c0b6', '00000000-0000-0000-0000-00000000c0a1', 'Old shed', 'completed');
  update projects set name = 'Tower A (east)', status = 'on_hold' where id = '00000000-0000-0000-0000-00000000c0b1';
  update projects set status = 'active' where id = '00000000-0000-0000-0000-00000000c0b1';
  -- A replayed insert (or upsert) of a site already on the server is not a new site.
  insert into projects (id, company_id, name, status) values
    ('00000000-0000-0000-0000-00000000c0b4', '00000000-0000-0000-0000-00000000c0a1', 'Tower C', 'active')
  on conflict (id) do update set status = excluded.status;
  begin
    insert into projects (id, company_id, name, status) values
      ('00000000-0000-0000-0000-00000000c0b4', '00000000-0000-0000-0000-00000000c0a1', 'Tower C', 'active');
    raise exception 'a duplicate id was accepted';
  exception when unique_violation then null;
  end;
  -- Two new sites in one statement can't both take the last place.
  update projects set status = 'completed' where id = '00000000-0000-0000-0000-00000000c0b4';
  begin
    insert into projects (id, company_id, name, status) values
      ('00000000-0000-0000-0000-00000000c0b7', '00000000-0000-0000-0000-00000000c0a1', 'Tower E', 'active'),
      ('00000000-0000-0000-0000-00000000c0b8', '00000000-0000-0000-0000-00000000c0a1', 'Tower F', 'active');
    raise exception 'two sites in one insert went past the limit';
  exception when raise_exception then null;
  end;
  -- Finishing a site frees a place: reopening Villa now works.
  update projects set status = 'active' where id = '00000000-0000-0000-0000-00000000c0b2';
end $$;
reset role;

-- A company over its limit (the team moved it to a 1-site pilot) keeps
-- working on the sites it has; only new or reopened ones are refused.
set local role service_role;
select public.end_company_plan(:'plan_id');
select public.grant_company_plan('pilot', public.ist_today() + 60, p_company_id => '00000000-0000-0000-0000-00000000c0a1',
                                 p_invoice_ref => 'INV-TEST-PILOT') as pilot_id \gset
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', true);
update projects set name = 'Tower B (west)', status = 'planning' where id = '00000000-0000-0000-0000-00000000c0b3';
update projects set status = 'completed' where id = '00000000-0000-0000-0000-00000000c0b2';
do $$
begin
  begin
    update projects set status = 'on_hold' where id = '00000000-0000-0000-0000-00000000c0b2';
    raise exception 'a site was reopened by a company over its limit';
  exception when raise_exception then null;
  end;
end $$;
reset role;
-- Enterprise with no limit: nothing refused.
set local role service_role;
select public.end_company_plan(:'pilot_id');
select public.grant_company_plan('enterprise', public.ist_today() + 30, p_company_id => '00000000-0000-0000-0000-00000000c0a1')
  as ent_id \gset
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', true);
insert into projects (id, company_id, name, status) values
  ('00000000-0000-0000-0000-00000000c0b9', '00000000-0000-0000-0000-00000000c0a1', 'Mall', 'active');
reset role;
set local role service_role;
select public.end_company_plan(:'ent_id');
reset role;
-- With no plan at all there is no site limit (store subscription).
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', true);
update projects set status = 'active' where id = '00000000-0000-0000-0000-00000000c0b2';
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
