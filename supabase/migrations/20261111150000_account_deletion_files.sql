-- Issue #139: "Delete my cloud account" must remove the company's files
-- too, not only its rows. Storage refuses direct SQL deletes, so the
-- function queues each deleted site's folder ({projectId}/ in the
-- `documents` bucket, which holds every photo, selfie, document and claim
-- photo) and the `account-cleanup` edge function removes the files through
-- the Storage API. The app calls that function right after deleting; any
-- call drains the whole queue, so nothing missed stays queued for long.
--
-- Also: someone leaving a shared company loses their supplier, client and
-- subcontractor portal links and their AI usage rows even when the login
-- itself cannot be deleted (records they created still point at it).

create table if not exists public.storage_cleanup (
  bucket text not null,
  prefix text not null check (prefix ~ '^[0-9a-f-]{36}/$'),
  queued_at timestamptz not null default now(),
  primary key (bucket, prefix)
);
alter table public.storage_cleanup enable row level security;
revoke all on public.storage_cleanup from public, anon, authenticated;
grant select, insert, delete on public.storage_cleanup to service_role;

create or replace function delete_my_account()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_company record;
  v_deleted int := 0;
  v_left int := 0;
  v_heir uuid;
  v_login_removed boolean := true;
  v_folders int := 0;
  v_n int;
begin
  if v_uid is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;

  for v_company in
    select cm.company_id, cm.role,
           (select count(*) from company_members o where o.company_id = cm.company_id) as members
    from company_members cm
    where cm.user_id = v_uid
  loop
    if v_company.members = 1 then
      insert into storage_cleanup (bucket, prefix)
      select 'documents', p.id::text || '/' from projects p where p.company_id = v_company.company_id
      on conflict do nothing;
      get diagnostics v_n = row_count;
      v_folders := v_folders + v_n;
      delete from companies where id = v_company.company_id;
      v_deleted := v_deleted + 1;
    else
      if v_company.role = 'owner' and not exists (
        select 1 from company_members o
        where o.company_id = v_company.company_id and o.user_id <> v_uid and o.role = 'owner'
      ) then
        select o.user_id into v_heir
        from company_members o
        where o.company_id = v_company.company_id and o.user_id <> v_uid
        order by (o.role = 'project_manager') desc, o.created_at
        limit 1;
        update company_members set role = 'owner'
        where company_id = v_company.company_id and user_id = v_heir;
      end if;
      delete from company_members where company_id = v_company.company_id and user_id = v_uid;
      v_left := v_left + 1;
    end if;
  end loop;

  update project_messages set sender_name = 'Former member' where sender_id = v_uid;
  delete from project_members where user_id = v_uid;
  update companies set created_by = null where created_by = v_uid;
  -- Portal links and AI allowances are about this person only. They
  -- cascade when the login is deleted, but not when it can only be wiped.
  delete from supplier_users where user_id = v_uid;
  delete from client_users where user_id = v_uid;
  delete from subcontractor_users where user_id = v_uid;
  delete from ai_usage where user_id = v_uid;

  begin
    delete from auth.users where id = v_uid;
  exception when foreign_key_violation then
    v_login_removed := false;
    update auth.users
    set email = 'deleted-' || v_uid || '@deleted.invalid',
        phone = null,
        encrypted_password = '',
        raw_user_meta_data = '{}'::jsonb,
        banned_until = 'infinity'
    where id = v_uid;
    delete from auth.identities where user_id = v_uid;
    delete from auth.sessions where user_id = v_uid;
  end;

  return json_build_object(
    'companies_deleted', v_deleted,
    'companies_left', v_left,
    'login_deleted', v_login_removed,
    'file_folders_queued', v_folders
  );
end;
$$;

revoke all on function delete_my_account() from public, anon;
grant execute on function delete_my_account() to authenticated;

-- For the edge function (service role): up to p_limit files still in a
-- queued folder, and then clearing folders that have none left.
create or replace function public.storage_cleanup_files(p_limit int default 1000)
returns table (bucket text, name text)
language sql
stable
security definer
set search_path = public, storage
as $$
  select o.bucket_id::text, o.name::text
  from storage_cleanup q
  join storage.objects o on o.bucket_id = q.bucket and o.name like q.prefix || '%'
  limit greatest(1, least(p_limit, 5000));
$$;

create or replace function public.storage_cleanup_finish()
returns int
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  v_n int;
begin
  delete from storage_cleanup q
  where not exists (
    select 1 from storage.objects o where o.bucket_id = q.bucket and o.name like q.prefix || '%');
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke all on function public.storage_cleanup_files(int) from public, anon, authenticated;
revoke all on function public.storage_cleanup_finish() from public, anon, authenticated;
grant execute on function public.storage_cleanup_files(int) to service_role;
grant execute on function public.storage_cleanup_finish() to service_role;
