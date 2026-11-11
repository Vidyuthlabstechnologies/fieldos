-- Minimum supported app build (issue #146).
--
-- Raise min_build_android / min_build_ios as the last step of a migration
-- that older builds can't sync safely against. A phone below the minimum
-- stops syncing (everything on the phone keeps working) and asks the person
-- to update. 0 = no minimum.
--
--   update public.app_config set min_build_android = 19, min_build_ios = 19,
--     message = null, updated_at = now();

create table if not exists public.app_config (
  id boolean primary key default true check (id),
  min_build_android integer not null default 0 check (min_build_android >= 0),
  min_build_ios integer not null default 0 check (min_build_ios >= 0),
  -- Optional sentence shown with the update prompt (English).
  message text check (message is null or length(message) <= 300),
  updated_at timestamptz not null default now()
);

insert into public.app_config (id) values (true) on conflict (id) do nothing;

-- Only the function below reads it; only the service role changes it.
alter table public.app_config enable row level security;
revoke all on table public.app_config from anon, authenticated;

-- Callable before sign-in, so the check works on any phone.
create or replace function public.min_app_build()
returns json
language sql
stable
security definer
set search_path = public
as $$
  select json_build_object('android', min_build_android, 'ios', min_build_ios, 'message', message)
    from public.app_config
   where id;
$$;

revoke all on function public.min_app_build() from public;
grant execute on function public.min_app_build() to anon, authenticated;
