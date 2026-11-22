-- Site viewers only read, on the server too.
--
-- A site team member with the role 'viewer' ("Can see the site, changes
-- nothing") was read-only only in the app. The server's policies let any
-- site member change most site records, so a viewer (often someone outside
-- the firm: the client's consultant, an auditor) could still edit tasks,
-- daily reports, issues and the rest straight through the API with their
-- own sign-in. A single trigger on every site table now refuses a viewer's
-- insert, update or delete there.
--
-- Not covered, on purpose: project chat (a viewer can still talk to the
-- team), the change log and voucher counters (written by other triggers
-- as a side effect), and the tables whose own policies already decide who
-- writes them (the site roster, site access and the client portal codes).
-- The company's owners and project managers are never refused, even if
-- they are also listed as a viewer on a site. Calls without a signed-in
-- user (the service role, the open API's SQL functions run as the key's
-- company) are not affected.

create or replace function site_viewer_read_only()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  me uuid := (select auth.uid());
  pid uuid;
begin
  if me is null then
    return coalesce(new, old);
  end if;
  pid := case when tg_op = 'DELETE' then (to_jsonb(old) ->> 'project_id')::uuid
              else (to_jsonb(new) ->> 'project_id')::uuid end;
  if pid is not null
     and exists (select 1 from project_members pm
                  where pm.project_id = pid and pm.user_id = me and pm.role = 'viewer')
     and not is_company_manager_of_project(pid) then
    raise exception 'You can see this site but not change it (your role on it is Viewer).' using errcode = '42501';
  end if;
  -- An update that moves a row out of a site the viewer only sees.
  if tg_op = 'UPDATE' and (to_jsonb(old) ->> 'project_id')::uuid is distinct from pid
     and exists (select 1 from project_members pm
                  where pm.project_id = (to_jsonb(old) ->> 'project_id')::uuid and pm.user_id = me and pm.role = 'viewer')
     and not is_company_manager_of_project((to_jsonb(old) ->> 'project_id')::uuid) then
    raise exception 'You can see this site but not change it (your role on it is Viewer).' using errcode = '42501';
  end if;
  return coalesce(new, old);
end $$;
revoke all on function site_viewer_read_only() from public, anon, authenticated;

do $$
declare
  t text;
begin
  for t in
    select c.table_name
      from information_schema.columns c
      join information_schema.tables x on x.table_schema = c.table_schema and x.table_name = c.table_name
     where c.table_schema = 'public' and c.column_name = 'project_id' and x.table_type = 'BASE TABLE'
       and c.table_name not in ('project_messages', 'sync_changes', 'entry_history', 'site_voucher_counters',
                                'project_members', 'site_access', 'client_codes', 'client_users')
     order by c.table_name
  loop
    execute format('drop trigger if exists %I on %I', t || '_site_viewer_read_only', t);
    execute format('create trigger %I before insert or update or delete on %I
                    for each row execute function site_viewer_read_only()', t || '_site_viewer_read_only', t);
  end loop;
end $$;
