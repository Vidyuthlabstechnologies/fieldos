-- "Delete my cloud account" (issue #139, 20261111150000_account_deletion_files.sql):
-- a sole-member company's site folders are queued for the account-cleanup
-- edge function, which only the service role can drive, and nothing
-- outside those folders is touched. Everything rolls back.
\set ON_ERROR_STOP on
begin;

insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000d1', 'leaving@solo.example', now()),
  ('00000000-0000-0000-0000-0000000000d2', 'stays@other.example', now());

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d1';
select ensure_company('00000000-0000-0000-0000-00000000d0a1', 'Solo Builders');
insert into projects (id, company_id, name, status) values
  ('00000000-0000-0000-0000-00000000d0b1', '00000000-0000-0000-0000-00000000d0a1', 'Tower A', 'active'),
  ('00000000-0000-0000-0000-00000000d0b2', '00000000-0000-0000-0000-00000000d0a1', 'Villa', 'active');
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d2';
select ensure_company('00000000-0000-0000-0000-00000000d0a2', 'Other Co');
insert into projects (id, company_id, name, status) values
  ('00000000-0000-0000-0000-00000000d0b3', '00000000-0000-0000-0000-00000000d0a2', 'Keep me', 'active');
reset role;

insert into storage.objects (bucket_id, name) values
  ('documents', '00000000-0000-0000-0000-00000000d0b1/photo-1.jpg'),
  ('documents', '00000000-0000-0000-0000-00000000d0b1/claims/claim-1.jpg'),
  ('documents', '00000000-0000-0000-0000-00000000d0b2/selfie-1.jpg'),
  ('documents', '00000000-0000-0000-0000-00000000d0b3/other.pdf');
insert into ai_usage (user_id, period, kind, used)
  values ('00000000-0000-0000-0000-0000000000d1', date_trunc('month', now())::date, 'chat', 3);

-- App users can neither read the queue nor drive the cleanup.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d2';
do $$
begin
  begin
    perform 1 from public.storage_cleanup;
    raise exception 'an app user read storage_cleanup';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.storage_cleanup_files(10);
    raise exception 'an app user listed cleanup files';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d1';
select set_config('test.result', delete_my_account()::text, true);
reset role;

do $$
begin
  if (current_setting('test.result')::json ->> 'file_folders_queued')::int <> 2 then
    raise exception 'two site folders should be queued: %', current_setting('test.result');
  end if;
  if exists (select 1 from companies where id = '00000000-0000-0000-0000-00000000d0a1') then raise exception 'company not deleted'; end if;
  if exists (select 1 from ai_usage where user_id = '00000000-0000-0000-0000-0000000000d1') then raise exception 'ai usage kept'; end if;
end $$;

set local role service_role;
do $$
declare
  n int;
begin
  select count(*) into n from public.storage_cleanup_files(100);
  if n <> 3 then raise exception 'expected the 3 files of the deleted sites, got %', n; end if;
  if exists (select 1 from public.storage_cleanup_files(100) where name like '00000000-0000-0000-0000-00000000d0b3/%') then
    raise exception 'another company''s file was listed';
  end if;
  if public.storage_cleanup_finish() <> 0 then raise exception 'folders with files left must stay queued'; end if;
end $$;
reset role;

-- What the edge function does through the Storage API.
delete from storage.objects where name like '00000000-0000-0000-0000-00000000d0b1/%' or name like '00000000-0000-0000-0000-00000000d0b2/%';

set local role service_role;
do $$
begin
  if public.storage_cleanup_finish() <> 2 then raise exception 'both folders should clear'; end if;
  if exists (select 1 from public.storage_cleanup) then raise exception 'queue should be empty'; end if;
end $$;
reset role;

do $$
begin
  if not exists (select 1 from storage.objects where name = '00000000-0000-0000-0000-00000000d0b3/other.pdf') then
    raise exception 'another company''s file was removed';
  end if;
  raise notice 'delete account checks passed';
end $$;

rollback;
