-- Daily usage of the in-app AI assistant, per account, so the ai-assistant
-- edge function can cap what one account spends of the shared Anthropic and
-- Sarvam keys. Only the edge function (service role) touches it: the app
-- never reads or writes this table, and RLS with no policies keeps it that
-- way for anon and signed-in users.
create table if not exists public.ai_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  kind text not null check (kind in ('chat', 'voice')),
  used integer not null default 0 check (used >= 0),
  primary key (user_id, day, kind)
);

alter table public.ai_usage enable row level security;
revoke all on public.ai_usage from anon, authenticated;

-- Takes p_amount from today's allowance (India's calendar day) and returns
-- the new total, or null when that would go over p_limit. One statement, so
-- two requests at once can't both squeeze under the limit.
create or replace function public.ai_usage_take(p_user uuid, p_kind text, p_amount integer, p_limit integer)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_used integer;
begin
  if p_amount < 0 or p_amount > p_limit then
    return null;
  end if;
  insert into public.ai_usage as u (user_id, day, kind, used)
  values (p_user, (now() at time zone 'Asia/Kolkata')::date, p_kind, p_amount)
  on conflict (user_id, day, kind) do update
    set used = u.used + excluded.used
    where u.used + excluded.used <= p_limit
  returning u.used into v_used;
  return v_used;
end;
$$;

revoke execute on function public.ai_usage_take(uuid, text, integer, integer) from public, anon, authenticated;
grant execute on function public.ai_usage_take(uuid, text, integer, integer) to service_role;
