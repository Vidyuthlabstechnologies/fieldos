-- The AI assistant's allowances: only the edge function (service role) may
-- read or change them, the daily call count never goes over its limit, and
-- the monthly spend adds up. Run against a
-- local stack by .github/workflows/ai-assistant.yml; everything rolls back.
\set ON_ERROR_STOP on
begin;

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'ai-usage-test@example.com');

set local role service_role;
do $$
declare
  u constant uuid := '00000000-0000-0000-0000-0000000000a1';
begin
  if public.ai_usage_take(u, 'chat', 1, 2) is distinct from 1 then raise exception 'first take should be 1'; end if;
  if public.ai_usage_take(u, 'chat', 1, 2) is distinct from 2 then raise exception 'second take should be 2'; end if;
  if public.ai_usage_take(u, 'chat', 1, 2) is not null then raise exception 'third take should be refused'; end if;
  if (select used from public.ai_usage where user_id = u and kind = 'chat') <> 2 then
    raise exception 'a refused take must not be counted';
  end if;
  if public.ai_usage_take(u, 'chat', 5, 3) is not null then raise exception 'one take over the limit must be refused'; end if;
  if public.ai_usage_take(u, 'spend', 1, 9) is not null then raise exception 'only chat calls are taken by count'; end if;
  if public.ai_spend_add(u, 0) is distinct from 0::bigint then raise exception 'a new month starts at 0'; end if;
  if public.ai_spend_add(u, 350) is distinct from 350::bigint then raise exception 'spend should count'; end if;
  if public.ai_spend_add(u, 0) is distinct from 350::bigint then raise exception 'reading must not add'; end if;
  if public.ai_spend_add(u, 50) is distinct from 400::bigint then raise exception 'spend should add up'; end if;
  if (select period from public.ai_usage where user_id = u and kind = 'spend')
      <> date_trunc('month', now() at time zone 'Asia/Kolkata')::date then
    raise exception 'spend is kept per month';
  end if;
  begin
    perform public.ai_spend_add(u, -1);
    raise exception 'negative spend was accepted';
  exception when raise_exception then
    if sqlerrm = 'negative spend was accepted' then raise; end if;
  end;
end $$;
reset role;

set local role authenticated;
do $$
begin
  perform 1 from public.ai_usage;
  raise exception 'a signed-in user could read ai_usage';
exception when insufficient_privilege then null;
end $$;
do $$
begin
  perform public.ai_usage_take('00000000-0000-0000-0000-0000000000a1', 'chat', -100, 1);
  raise exception 'a signed-in user could change their own allowance';
exception when insufficient_privilege then null;
end $$;
do $$
begin
  perform public.ai_spend_add('00000000-0000-0000-0000-0000000000a1', 0);
  raise exception 'a signed-in user could read their spend';
exception when insufficient_privilege then null;
end $$;
reset role;

set local role anon;
do $$
begin
  perform public.ai_usage_take('00000000-0000-0000-0000-0000000000a1', 'chat', 1, 1);
  raise exception 'anon could call ai_usage_take';
exception when insufficient_privilege then null;
end $$;
reset role;

rollback;
\echo 'ai_usage checks passed'
