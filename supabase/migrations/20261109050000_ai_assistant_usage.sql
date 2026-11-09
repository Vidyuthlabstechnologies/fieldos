-- Usage of the in-app AI assistant, per account, so the ai-assistant edge
-- function can cap what one account costs FieldOS on the shared Anthropic and
-- Sarvam keys. Two counters:
--   chat   model calls in one India calendar day (period = that day), a guard
--          against bursts
--   spend  what the account's AI use cost this India calendar month
--          (period = the 1st of the month), in units of 1/10,000 of a rupee,
--          worked out by the function from the providers' own token counts
-- Only the edge function (service role) touches it: the app never reads or
-- writes this table, and RLS with no policies keeps it that way.
create table if not exists public.ai_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  period date not null,
  kind text not null check (kind in ('chat', 'spend')),
  used bigint not null default 0 check (used >= 0),
  primary key (user_id, period, kind)
);

alter table public.ai_usage enable row level security;
revoke all on public.ai_usage from anon, authenticated;

-- Takes p_amount from today's call allowance and returns the new total, or
-- null when that would go over p_limit. One statement, so two requests at
-- once can't both squeeze under the limit.
create or replace function public.ai_usage_take(p_user uuid, p_kind text, p_amount integer, p_limit integer)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_used bigint;
begin
  if p_kind <> 'chat' or p_amount < 0 or p_amount > p_limit then
    return null;
  end if;
  insert into public.ai_usage as u (user_id, period, kind, used)
  values (p_user, (now() at time zone 'Asia/Kolkata')::date, p_kind, p_amount)
  on conflict (user_id, period, kind) do update
    set used = u.used + excluded.used
    where u.used + excluded.used <= p_limit
  returning u.used into v_used;
  return v_used;
end;
$$;

-- Adds p_amount (0 just reads) to this month's spend and returns the total.
create or replace function public.ai_spend_add(p_user uuid, p_amount bigint)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_used bigint;
begin
  if p_amount < 0 then
    raise exception 'ai_spend_add: negative amount';
  end if;
  insert into public.ai_usage as u (user_id, period, kind, used)
  values (p_user, date_trunc('month', now() at time zone 'Asia/Kolkata')::date, 'spend', p_amount)
  on conflict (user_id, period, kind) do update
    set used = u.used + excluded.used
  returning u.used into v_used;
  return v_used;
end;
$$;

revoke execute on function public.ai_usage_take(uuid, text, integer, integer) from public, anon, authenticated;
grant execute on function public.ai_usage_take(uuid, text, integer, integer) to service_role;
revoke execute on function public.ai_spend_add(uuid, bigint) from public, anon, authenticated;
grant execute on function public.ai_spend_add(uuid, bigint) to service_role;
