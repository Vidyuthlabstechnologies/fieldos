-- Site teams, site roles and approval limits (app schema v17, 2026-11-10).
--
-- Until now every member of a company saw every company site (a deliberate
-- choice for a small contractor: no assignment step to forget), and roles
-- were company-wide only. A company rolling FieldOS out across many sites
-- needs three more things, and this adds them without changing anything for
-- a company that doesn't use them:
--
-- 1. A site team. project_members (in the schema since the start, unused by
--    the app) becomes the site roster, with more roles: accounts,
--    storekeeper and viewer join owner / project_manager / site_engineer.
-- 2. Members-only sites. A site marked members_only in site_access is seen
--    only by its team, plus the company's owners and project managers.
--    Every other site stays visible to the whole company, as before.
-- 3. Approval limits. A site project manager can be given a limit; in the
--    weekly close they can approve an item up to it, and anything bigger
--    needs the owner (or a manager without a limit).
--
-- A company member listed as project_manager on a site manages that site
-- (is_project_owner_or_pm), which every owner/PM write policy already uses.

alter table project_members drop constraint if exists project_members_role_check;
alter table project_members add constraint project_members_role_check
  check (role in ('owner', 'project_manager', 'site_engineer', 'accounts', 'storekeeper', 'viewer'));
alter table project_members add column if not exists approval_limit numeric(14, 2)
  check (approval_limit is null or approval_limit >= 0);
alter table project_members add column if not exists updated_at timestamptz not null default now();
alter table project_members add column if not exists added_by uuid references auth.users(id) default auth.uid();

-- id is the project's id too (phones fetch changed rows by id).
create table if not exists site_access (
  id uuid primary key,
  project_id uuid not null unique references projects(id) on delete cascade check (project_id = id),
  members_only boolean not null default false,
  updated_by uuid references auth.users(id) default auth.uid(),
  updated_at timestamptz not null default now()
);
alter table site_access enable row level security;
revoke all on table site_access from anon, authenticated;
grant select, insert, update on table site_access to authenticated;

-- The company-level check, unchanged: owner or PM of the site's company.
create or replace function is_company_manager_of_project(p_project_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from projects p where p.id = p_project_id and is_company_owner_or_pm(p.company_id));
$$;

create or replace function has_project_access(p_project_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from projects p
    where p.id = p_project_id
      and (
        company_role(p.company_id) in ('owner', 'project_manager')
        or (company_role(p.company_id) is not null
            and not coalesce((select a.members_only from site_access a where a.project_id = p.id), false))
        or exists (select 1 from project_members pm where pm.project_id = p.id and pm.user_id = (select auth.uid()))
      )
  );
$$;

-- Owner/PM of the company, or listed as the site's project manager.
create or replace function is_project_owner_or_pm(p_project_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select is_company_manager_of_project(p_project_id)
      or exists (
        select 1 from project_members pm join projects p on p.id = pm.project_id
         where pm.project_id = p_project_id
           and pm.user_id = (select auth.uid())
           and pm.role in ('owner', 'project_manager')
           and company_role(p.company_id) is not null);
$$;

-- May the caller approve [p_amount] on this site? The company owner always
-- may. A site roster row decides for anyone on it (its limit, if set);
-- otherwise a company project manager may, without a limit.
create or replace function can_approve_on_site(p_project_id uuid, p_amount numeric)
returns boolean language sql security definer set search_path = public stable as $$
  select case
    when (select company_role(p.company_id) from projects p where p.id = p_project_id) = 'owner' then true
    when exists (select 1 from project_members pm where pm.project_id = p_project_id and pm.user_id = (select auth.uid())) then
      exists (
        select 1 from project_members pm
         where pm.project_id = p_project_id and pm.user_id = (select auth.uid())
           and pm.role in ('owner', 'project_manager')
           and (pm.approval_limit is null or coalesce(p_amount, 0) <= pm.approval_limit))
    else (select company_role(p.company_id) from projects p where p.id = p_project_id) = 'project_manager'
  end;
$$;

revoke all on function is_company_manager_of_project(uuid), can_approve_on_site(uuid, numeric) from public, anon;
grant execute on function is_company_manager_of_project(uuid), can_approve_on_site(uuid, numeric) to authenticated;

-- The roster: read by the site's team; changed by the company's owners and
-- managers, or the site's own manager, who can't hand out "owner" or lift
-- their own limit. Only people already in the company are added.
drop policy if exists "owner/pm can add project members" on project_members;
drop policy if exists "managers add site team members" on project_members;
create policy "managers add site team members" on project_members for insert
  to authenticated with check (
    (select is_project_owner_or_pm(project_id))
    and exists (select 1 from projects p join company_members cm on cm.company_id = p.company_id
                 where p.id = project_id and cm.user_id = project_members.user_id)
    and (role <> 'owner' or (select is_company_manager_of_project(project_id))));

-- A site's own manager changes and removes others' rows, never their own
-- and never an owner's (USING sees the row as it was, WITH CHECK as it
-- will be).
drop policy if exists "managers change site team members" on project_members;
create policy "managers change site team members" on project_members for update
  to authenticated
  using (
    (select is_company_manager_of_project(project_id))
    or ((select is_project_owner_or_pm(project_id)) and user_id <> (select auth.uid()) and role <> 'owner'))
  with check (
    (select is_company_manager_of_project(project_id))
    or (user_id <> (select auth.uid()) and role <> 'owner'));

drop policy if exists "managers remove site team members" on project_members;
create policy "managers remove site team members" on project_members for delete
  to authenticated using (
    (select is_company_manager_of_project(project_id))
    or ((select is_project_owner_or_pm(project_id)) and user_id <> (select auth.uid()) and role <> 'owner'));

grant select, insert, update, delete on table project_members to authenticated;

-- A roster row keeps its site and person.
create or replace function project_members_keep_origin()
returns trigger language plpgsql as $$
begin
  new.id := old.id;
  new.project_id := old.project_id;
  new.user_id := old.user_id;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists project_members_keep_origin on project_members;
create trigger project_members_keep_origin before update on project_members
  for each row execute function project_members_keep_origin();

-- Only the company's owners and managers make a site members-only (a site
-- manager could otherwise hide their site from the rest of management, who
-- see it anyway, or open it to everyone).
drop policy if exists "site team reads site access" on site_access;
create policy "site team reads site access" on site_access for select
  to authenticated using ((select has_project_access(project_id)));
drop policy if exists "company managers set site access" on site_access;
create policy "company managers set site access" on site_access for insert
  to authenticated with check ((select is_company_manager_of_project(project_id)));
drop policy if exists "company managers change site access" on site_access;
create policy "company managers change site access" on site_access for update
  to authenticated using ((select is_company_manager_of_project(project_id)))
  with check ((select is_company_manager_of_project(project_id)));

-- Weekly close: approving needs a limit at least the item's amount;
-- sending back, closing and reopening need a manager of the site.
drop policy if exists "decisions are recorded as yourself, by the right role" on site_close_reviews;
create policy "decisions are recorded as yourself, by the right role" on site_close_reviews for insert
  to authenticated with check (
    decided_by = (select auth.uid())
    and (select has_project_access(project_id))
    and (decision = 'fixed'
         or (decision = 'approved' and (select can_approve_on_site(project_id, abs(coalesce(amount, 0)))))
         or (decision in ('sent_back', 'closed', 'reopened') and (select is_project_owner_or_pm(project_id)))));

-- The limit is checked against the amount on record, not the one the phone
-- sends: for an expense or a delivery, the server takes the amount from the
-- row itself before the insert policy looks at it (RLS checks the row as
-- BEFORE triggers leave it). Wages are worked out on the phone from the
-- attendance, so their amount is taken as sent.
create or replace function site_close_reviews_true_amount()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_amount numeric;
begin
  if new.item_kind = 'expense' then
    select e.amount into v_amount from site_expenses e
     where e.id::text = new.item_id and e.project_id = new.project_id;
  elsif new.item_kind = 'receipt' then
    select r.amount into v_amount from site_material_receipts r
     where r.id::text = new.item_id and r.project_id = new.project_id;
  end if;
  if v_amount is not null then
    new.amount := v_amount;
  end if;
  return new;
end $$;
revoke all on function site_close_reviews_true_amount() from public, anon, authenticated;
drop trigger if exists site_close_reviews_true_amount on site_close_reviews;
create trigger site_close_reviews_true_amount before insert on site_close_reviews
  for each row execute function site_close_reviews_true_amount();

-- Phones learn roster and access changes through the change log.
drop trigger if exists project_members_log_sync_change on project_members;
create trigger project_members_log_sync_change after insert or update or delete on project_members
  for each row execute function log_sync_change();

drop trigger if exists site_access_log_sync_change on site_access;
create trigger site_access_log_sync_change after insert or update or delete on site_access
  for each row execute function log_sync_change();
