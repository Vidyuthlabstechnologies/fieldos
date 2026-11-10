-- Multi-level approvals by amount (item 5 of the weekly-close plan, schema
-- v30 on the phone). The owner sets, for purchase requests, expenses and
-- purchase orders, the amount above which a project manager must approve
-- and the amount above which the owner must too. Each signature is one
-- insert-only step; the phone works out whether the chain is complete.
--
-- Apply after 20261110310000_billing_reconciliation.sql.

create table if not exists site_approval_rules (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  kind text not null check (kind in ('purchase_request', 'expense', 'purchase_order')),
  role text not null check (role in ('project_manager', 'owner')),
  above_amount numeric(14, 2) not null check (above_amount >= 0),
  voided boolean not null default false,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists site_approval_rules_company on site_approval_rules (company_id);

alter table site_approval_rules enable row level security;

drop policy if exists "members read approval rules" on site_approval_rules;
create policy "members read approval rules" on site_approval_rules for select
  to authenticated using ((select is_company_member(company_id)));

-- Only the company's owner sets the rules.
drop policy if exists "owner adds approval rules" on site_approval_rules;
create policy "owner adds approval rules" on site_approval_rules for insert
  to authenticated with check (
    (select company_role(company_id)) = 'owner' and created_by = (select auth.uid()));

drop policy if exists "owner changes approval rules" on site_approval_rules;
create policy "owner changes approval rules" on site_approval_rules for update
  to authenticated
  using ((select company_role(company_id)) = 'owner')
  with check ((select company_role(company_id)) = 'owner');

grant select, insert, update on table site_approval_rules to authenticated;

-- A rule keeps its company, kind and level; only the amount and voided
-- change.
create or replace function site_approval_rules_keep()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.company_id <> old.company_id or new.kind <> old.kind or new.role <> old.role
     or new.created_by <> old.created_by then
    raise exception 'an approval rule keeps its company, kind and level';
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists site_approval_rules_keep on site_approval_rules;
create trigger site_approval_rules_keep before update on site_approval_rules
  for each row execute function site_approval_rules_keep();

create table if not exists site_approval_steps (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  kind text not null check (kind in ('purchase_request', 'expense', 'purchase_order')),
  item_id uuid not null,
  level text not null check (level in ('project_manager', 'owner')),
  decision text not null check (decision in ('approved', 'rejected')),
  amount numeric(14, 2),
  note text check (note is null or length(note) <= 300),
  decided_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (kind, item_id, level, decided_by)
);
create index if not exists site_approval_steps_item on site_approval_steps (kind, item_id);
create index if not exists site_approval_steps_project on site_approval_steps (project_id);

alter table site_approval_steps enable row level security;

drop policy if exists "site team reads approval steps" on site_approval_steps;
create policy "site team reads approval steps" on site_approval_steps for select
  to authenticated using ((select has_project_access(project_id)));

-- Who signs which level: the owner level only the company's owner; the
-- project manager level anyone who may approve this amount on the site
-- (can_approve_on_site: the owner, a company PM, or a site PM within their
-- limit). The amount is the record's own (set by the trigger below,
-- before this check runs).
drop policy if exists "approvers sign their level" on site_approval_steps;
create policy "approvers sign their level" on site_approval_steps for insert
  to authenticated with check (
    decided_by = (select auth.uid())
    and (select has_project_access(project_id))
    and case level
      when 'owner' then (select company_role(p.company_id) from projects p where p.id = project_id) = 'owner'
      else (select can_approve_on_site(project_id, amount))
    end);

grant select, insert on table site_approval_steps to authenticated;

-- The step carries the amount on record, and the item must be on the
-- step's site.
create or replace function site_approval_steps_true_amount()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  pid uuid;
  amt numeric;
begin
  case new.kind
    when 'purchase_request' then
      select project_id, estimated_cost into pid, amt from purchase_requisitions where id = new.item_id;
    when 'expense' then
      select project_id, amount into pid, amt from site_expenses where id = new.item_id;
    when 'purchase_order' then
      select project_id, total_amount into pid, amt from purchase_orders where id = new.item_id;
  end case;
  if pid is null or pid <> new.project_id then
    raise exception 'the item is not on this site';
  end if;
  new.amount := coalesce(amt, 0);
  return new;
end $$;
revoke all on function site_approval_steps_true_amount() from public, anon, authenticated;
drop trigger if exists site_approval_steps_true_amount on site_approval_steps;
create trigger site_approval_steps_true_amount before insert on site_approval_steps
  for each row execute function site_approval_steps_true_amount();

-- Is an item's chain complete? The levels its amount crosses must each
-- have an approval at that level or above (the owner's covers both), and
-- no one may have rejected it. A rule covers items recorded after it was
-- made, so setting one doesn't stop last month's records.
create or replace function approval_chain_complete(p_kind text, p_item_id uuid, p_project_id uuid, p_amount numeric,
                                                   p_created timestamptz)
returns boolean language sql security definer set search_path = public stable as $$
  with need as (
    select r.role from site_approval_rules r join projects p on p.company_id = r.company_id
     where p.id = p_project_id and r.kind = p_kind and not r.voided
       and coalesce(abs(p_amount), 0) > r.above_amount + 0.005
       and (p_created is null or r.created_at <= p_created))
  select not exists (select 1 from site_approval_steps s
                      where s.kind = p_kind and s.item_id = p_item_id and s.decision = 'rejected')
     and (not exists (select 1 from need where role = 'owner')
          or exists (select 1 from site_approval_steps s where s.kind = p_kind and s.item_id = p_item_id
                       and s.decision = 'approved' and s.level = 'owner'))
     and (not exists (select 1 from need where role = 'project_manager')
          or exists (select 1 from site_approval_steps s where s.kind = p_kind and s.item_id = p_item_id
                       and s.decision = 'approved'));
$$;
revoke all on function approval_chain_complete(text, uuid, uuid, numeric, timestamptz) from public, anon;
grant execute on function approval_chain_complete(text, uuid, uuid, numeric, timestamptz) to authenticated;

-- The weekly close approves an expense only once its chain is complete,
-- and a PO is raised from a request only once the request's is.
create or replace function site_close_reviews_need_chain()
returns trigger language plpgsql security definer set search_path = public as $$
declare amt numeric; made timestamptz;
begin
  if new.decision = 'approved' and new.item_kind = 'expense' then
    -- site_close_reviews.item_id is text.
    select amount, created_at into amt, made from site_expenses where id = new.item_id::uuid;
    if not approval_chain_complete('expense', new.item_id::uuid, new.project_id, amt, made) then
      raise exception 'this expense still needs its approvals';
    end if;
  end if;
  return new;
end $$;
revoke all on function site_close_reviews_need_chain() from public, anon, authenticated;
drop trigger if exists site_close_reviews_need_chain on site_close_reviews;
create trigger site_close_reviews_need_chain before insert on site_close_reviews
  for each row execute function site_close_reviews_need_chain();

create or replace function purchase_orders_need_chain()
returns trigger language plpgsql security definer set search_path = public as $$
declare amt numeric; made timestamptz;
begin
  if new.requisition_id is not null then
    select estimated_cost, created_at into amt, made from purchase_requisitions where id = new.requisition_id;
    if not approval_chain_complete('purchase_request', new.requisition_id, new.project_id, amt, made) then
      raise exception 'this purchase request still needs its approvals';
    end if;
  end if;
  return new;
end $$;
revoke all on function purchase_orders_need_chain() from public, anon, authenticated;
drop trigger if exists purchase_orders_need_chain on purchase_orders;
create trigger purchase_orders_need_chain before insert on purchase_orders
  for each row execute function purchase_orders_need_chain();

-- The change log: approval rules are company-wide, so the log falls back
-- to company_id for any row without a project. Same as
-- 20261110030000_weekly_close.sql otherwise.
create or replace function log_sync_change()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  r jsonb := to_jsonb(case when tg_op = 'DELETE' then old else new end);
  pid uuid;
  cid uuid;
begin
  case tg_table_name
    when 'projects' then pid := (r->>'id')::uuid; cid := (r->>'company_id')::uuid;
    when 'vendors', 'subcontractors' then cid := (r->>'company_id')::uuid;
    when 'dpr_photos' then select project_id into pid from dpr_entries where id = (r->>'dpr_entry_id')::uuid;
    when 'equipment_logs' then select project_id into pid from equipment where id = (r->>'equipment_id')::uuid;
    when 'inspection_items' then select project_id into pid from inspections where id = (r->>'inspection_id')::uuid;
    when 'cost_heads' then select project_id into pid from estimations where id = (r->>'estimation_id')::uuid;
    when 'measurement_entries', 'steel_entries' then
      select e.project_id into pid from cost_heads c join estimations e on e.id = c.estimation_id
       where c.id = (r->>'cost_head_id')::uuid;
    when 'expense_attachments' then select project_id into pid from site_expenses where id = (r->>'expense_id')::uuid;
    when 'site_receipt_attachments' then
      select project_id into pid from site_material_receipts where id = (r->>'receipt_id')::uuid;
    else
      pid := (r->>'project_id')::uuid;
      if pid is null then cid := (r->>'company_id')::uuid; end if;
  end case;
  if pid is null and cid is null then return null; end if;
  insert into sync_changes (table_name, row_id, op, project_id, company_id)
  values (tg_table_name, (r->>'id')::uuid, case when tg_op = 'DELETE' then 'd' else 'u' end, pid, cid);
  return null;
end $$;
revoke all on function log_sync_change() from public, anon, authenticated;

do $$
declare t text;
begin
  foreach t in array array['site_approval_rules', 'site_approval_steps'] loop
    execute format('drop trigger if exists %I on %I', t || '_log_sync_change', t);
    execute format('create trigger %I after insert or update or delete on %I for each row execute function log_sync_change()',
                   t || '_log_sync_change', t);
  end loop;
end $$;
