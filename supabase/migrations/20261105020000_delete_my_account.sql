-- In-app account deletion (Google Play requires it for any app that lets
-- people create an account).
--
-- delete_my_account() runs as the signed-in user and:
--   1. deletes every company where the caller is the only member, with all
--      of that company's projects and records (FKs cascade from companies);
--   2. leaves every company that has other members, handing ownership to
--      the longest-standing remaining member if the caller was its only
--      owner, so the team is never left without an owner;
--   3. removes the caller's name from team chat in those shared companies;
--   4. deletes the auth user. If shared company records the caller created
--      still point at it (created_by and similar columns, which are NOT
--      NULL), the login is wiped instead: email replaced, password,
--      identities and sessions removed, account banned. Those records
--      belong to the company, which keeps them.
--
-- Document files in Storage for deleted companies are not removed here
-- (Storage blocks direct SQL deletes); see docs/PLAY_STORE_LAUNCH.md.

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
    'login_deleted', v_login_removed
  );
end;
$$;

revoke all on function delete_my_account() from public, anon;
grant execute on function delete_my_account() to authenticated;
