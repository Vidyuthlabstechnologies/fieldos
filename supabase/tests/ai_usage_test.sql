-- The AI assistant's daily allowance: only the edge function (service role)
-- may read or take from it, and it never goes over the limit. Run against a
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
  if public.ai_usage_take(u, 'voice', 5, 3) is not null then raise exception 'one take over the limit must be refused'; end if;
  if exists (select 1 from public.ai_usage where user_id = u and kind = 'voice') then
    raise exception 'a refused first take must not create a row';
  end if;
  if public.ai_usage_take(u, 'voice', 3, 900) is distinct from 3 then raise exception 'voice seconds should count'; end if;
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
