-- Central stores, tools register and monthly staff salaries (2026-11-10).
--
-- Stores: a company's yard or godown. Stock moves bring material into a
-- store, send it between stores and sites, and correct a count. A transfer
-- is on the way until the receiving end counts it; what was sent, from
-- where, at what rate, is not rewritten afterwards.
--
-- Who:
-- - Owners and project managers run stores, tools and salaries.
-- - A site's team sees moves into or out of its site, counts transfers in,
--   and sends material on from its site. It never sees other sites' moves.
-- - Salaries (staff, advances, payslips) are owner and project manager only.
--
-- Change log: company-level lines (company_id set, project_id null), like
-- the CRM tables; rows are still filtered by the policies below.

-- --- Tables ------------------------------------------------------------------

create table if not exists stores (
  id uuid primary key,
  company_id uuid not null references companies(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  location text check (char_length(location) <= 300),
  archived boolean not null default false,
  created_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists stores_company_idx on stores (company_id);

create table if not exists stock_moves (
  id uuid primary key,
  company_id uuid not null references companies(id) on delete cascade,
  kind text not null check (kind in ('inward', 'transfer', 'adjust')),
  from_store_id uuid references stores(id) on delete restrict,
  from_project_id uuid references projects(id) on delete cascade,
  to_store_id uuid references stores(id) on delete restrict,
  to_project_id uuid references projects(id) on delete cascade,
  supplier_name text check (char_length(supplier_name) <= 120),
  material_name text not null check (char_length(material_name) between 1 and 200),
  unit text check (char_length(unit) <= 20),
  quantity numeric(14, 3) not null check (quantity > 0),
  rate numeric(14, 2) check (rate is null or rate >= 0),
  status text not null default 'received' check (status in ('in_transit', 'received', 'cancelled')),
  received_qty numeric(14, 3) check (received_qty is null or (received_qty >= 0 and received_qty <= quantity)),
  vehicle text check (char_length(vehicle) <= 40),
  note text check (char_length(note) <= 300),
  sent_by uuid references auth.users(id) default auth.uid(),
  sent_on timestamptz not null,
  received_by uuid references auth.users(id),
  received_on timestamptz,
  created_at timestamptz not null default now(),
  -- One place at each end at most.
  check (num_nonnulls(from_store_id, from_project_id) <= 1),
  check (num_nonnulls(to_store_id, to_project_id) <= 1),
  check (kind <> 'inward' or (to_store_id is not null and num_nonnulls(from_store_id, from_project_id) = 0)),
  check (kind <> 'transfer' or (num_nonnulls(from_store_id, from_project_id) = 1
                                and num_nonnulls(to_store_id, to_project_id) = 1
                                and coalesce(from_store_id, from_project_id) <> coalesce(to_store_id, to_project_id))),
  check (kind <> 'adjust' or (from_project_id is null and to_project_id is null
                              and num_nonnulls(from_store_id, to_store_id) = 1
                              and char_length(coalesce(note, '')) > 0))
);
create index if not exists stock_moves_company_idx on stock_moves (company_id, sent_on);
create index if not exists stock_moves_from_project_idx on stock_moves (from_project_id) where from_project_id is not null;
create index if not exists stock_moves_to_project_idx on stock_moves (to_project_id) where to_project_id is not null;
create index if not exists stock_moves_from_store_idx on stock_moves (from_store_id) where from_store_id is not null;
create index if not exists stock_moves_to_store_idx on stock_moves (to_store_id) where to_store_id is not null;

create table if not exists tools (
  id uuid primary key,
  company_id uuid not null references companies(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  code text check (char_length(code) <= 40),
  category text check (char_length(category) <= 60),
  value numeric(14, 2) check (value is null or value >= 0),
  store_id uuid references stores(id) on delete set null,
  condition text not null default 'in_use' check (condition in ('in_use', 'repair', 'retired')),
  notes text check (char_length(notes) <= 300),
  created_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists tools_company_idx on tools (company_id);

create table if not exists tool_issues (
  id uuid primary key,
  company_id uuid not null references companies(id) on delete cascade,
  tool_id uuid not null references tools(id) on delete cascade,
  project_id uuid references projects(id) on delete set null,
  issued_to text not null check (char_length(issued_to) between 1 and 120),
  worker_id uuid,
  issued_by uuid references auth.users(id) default auth.uid(),
  issued_on timestamptz not null,
  due_back timestamptz,
  returned_on timestamptz,
  return_condition text check (return_condition in ('ok', 'damaged', 'lost')),
  recover_amount numeric(14, 2) check (recover_amount is null or recover_amount >= 0),
  note text check (char_length(note) <= 300),
  created_at timestamptz not null default now()
);
create index if not exists tool_issues_tool_idx on tool_issues (tool_id, issued_on);
create index if not exists tool_issues_project_idx on tool_issues (project_id) where project_id is not null;

create table if not exists staff_members (
  id uuid primary key,
  company_id uuid not null references companies(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  phone text check (char_length(phone) <= 30),
  designation text check (char_length(designation) <= 80),
  project_id uuid references projects(id) on delete set null,
  basic numeric(12, 2) not null check (basic > 0),
  hra numeric(12, 2) not null default 0 check (hra >= 0),
  other_allowance numeric(12, 2) not null default 0 check (other_allowance >= 0),
  pf boolean not null default true,
  esi boolean not null default true,
  pt_state text not null default 'TS' check (pt_state in ('TS', 'AP', 'none')),
  uan text check (char_length(uan) <= 20),
  joined_on timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists staff_members_company_idx on staff_members (company_id);

create table if not exists staff_advances (
  id uuid primary key,
  company_id uuid not null references companies(id) on delete cascade,
  staff_id uuid not null references staff_members(id) on delete cascade,
  amount numeric(12, 2) not null check (amount > 0),
  given_on timestamptz not null,
  note text check (char_length(note) <= 200),
  created_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists staff_advances_staff_idx on staff_advances (staff_id);

create table if not exists payroll_lines (
  id uuid primary key,
  company_id uuid not null references companies(id) on delete cascade,
  staff_id uuid not null references staff_members(id) on delete cascade,
  month text not null check (month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  days_in_month int not null check (days_in_month between 28 and 31),
  paid_days numeric(5, 2) not null check (paid_days >= 0 and paid_days <= days_in_month),
  basic numeric(12, 2) not null check (basic >= 0),
  hra numeric(12, 2) not null default 0 check (hra >= 0),
  other_allowance numeric(12, 2) not null default 0 check (other_allowance >= 0),
  gross numeric(12, 2) not null check (gross >= 0),
  pf_employee numeric(12, 2) not null default 0 check (pf_employee >= 0),
  esi_employee numeric(12, 2) not null default 0 check (esi_employee >= 0),
  pt numeric(12, 2) not null default 0 check (pt >= 0),
  advance_recovery numeric(12, 2) not null default 0 check (advance_recovery >= 0),
  other_deduction numeric(12, 2) not null default 0 check (other_deduction >= 0),
  net numeric(12, 2) not null check (net >= 0),
  pf_employer numeric(12, 2) not null default 0 check (pf_employer >= 0),
  esi_employer numeric(12, 2) not null default 0 check (esi_employer >= 0),
  status text not null default 'draft' check (status in ('draft', 'paid')),
  paid_on timestamptz,
  paid_mode text check (paid_mode in ('bank', 'upi', 'cash', 'cheque')),
  project_id uuid references projects(id) on delete set null,
  expense_id uuid,
  created_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (abs(gross - (basic + hra + other_allowance)) < 0.01),
  check (net <= gross),
  check (status <> 'paid' or paid_on is not null)
);
create index if not exists payroll_lines_company_month_idx on payroll_lines (company_id, month);
-- One payslip a person a month. Two phones offline making the same month
-- is caught on the phone (it makes only missing ones after a sync); the
-- second insert is refused rather than paying someone twice.
create unique index if not exists payroll_lines_staff_month_idx on payroll_lines (staff_id, month);

-- --- Checks and stamps -----------------------------------------------------

-- Every place on a move, the tool of an issue, the person of an advance or
-- payslip, and a posted site belong to the row's company.
create or replace function wh_check_company()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  c uuid := new.company_id;
  r jsonb := to_jsonb(new);
  k text;
begin
  foreach k in array array['from_store_id', 'to_store_id', 'store_id'] loop
    if r ? k and r->>k is not null
       and not exists (select 1 from stores s where s.id = (r->>k)::uuid and s.company_id = c) then
      raise exception 'store belongs to another company' using errcode = '42501';
    end if;
  end loop;
  foreach k in array array['from_project_id', 'to_project_id', 'project_id'] loop
    if r ? k and r->>k is not null
       and not exists (select 1 from projects p where p.id = (r->>k)::uuid and p.company_id = c) then
      raise exception 'site belongs to another company' using errcode = '42501';
    end if;
  end loop;
  if r ? 'tool_id' and not exists (select 1 from tools t where t.id = (r->>'tool_id')::uuid and t.company_id = c) then
    raise exception 'tool belongs to another company' using errcode = '42501';
  end if;
  if r ? 'staff_id' and not exists (select 1 from staff_members m where m.id = (r->>'staff_id')::uuid and m.company_id = c) then
    raise exception 'staff member belongs to another company' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function wh_check_company() from public, anon, authenticated;

-- Who sent, received, issued or made a row is whoever is signed in.
create or replace function stock_moves_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.sent_by := auth.uid();
    new.created_at := now();
    if new.sent_on is null or new.sent_on > now() + interval '5 minutes' then
      new.sent_on := now();
    end if;
    if new.kind = 'transfer' then
      new.status := 'in_transit';
      new.received_qty := null;
      new.received_by := null;
      new.received_on := null;
    else
      new.status := 'received';
      new.received_qty := new.quantity;
      new.received_by := auth.uid();
      new.received_on := new.sent_on;
    end if;
    return new;
  end if;

  -- What moved, from where to where, at what rate, stays as sent.
  if new.company_id is distinct from old.company_id or new.kind is distinct from old.kind
     or new.from_store_id is distinct from old.from_store_id or new.from_project_id is distinct from old.from_project_id
     or new.to_store_id is distinct from old.to_store_id or new.to_project_id is distinct from old.to_project_id
     or new.material_name is distinct from old.material_name or new.unit is distinct from old.unit
     or new.quantity is distinct from old.quantity or new.rate is distinct from old.rate
     or new.supplier_name is distinct from old.supplier_name or new.sent_by is distinct from old.sent_by
     or new.sent_on is distinct from old.sent_on then
    raise exception 'a stock move is not rewritten' using errcode = '42501';
  end if;
  if old.status <> 'in_transit' then
    -- The same close sent again (a phone retrying) changes nothing.
    if new.status = old.status then
      return old;
    end if;
    raise exception 'this move is already closed' using errcode = '42501';
  end if;
  if new.status = 'received' then
    new.received_by := auth.uid();
    new.received_qty := coalesce(new.received_qty, old.quantity);
    if new.received_on is null or new.received_on > now() + interval '5 minutes' then
      new.received_on := now();
    end if;
  elsif new.status = 'cancelled' then
    -- Called back by the sender or a manager, not by the receiver.
    if not (is_company_owner_or_pm(old.company_id) or old.sent_by = auth.uid()) then
      raise exception 'only the sender or a manager calls a transfer back' using errcode = '42501';
    end if;
    new.received_qty := null;
    new.received_by := null;
    new.received_on := null;
  end if;
  return new;
end $$;
revoke all on function stock_moves_guard() from public, anon, authenticated;

create or replace function tool_issues_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.issued_by := auth.uid();
    new.created_at := now();
    new.returned_on := null;
    new.return_condition := null;
    new.recover_amount := null;
    return new;
  end if;
  if new.company_id is distinct from old.company_id or new.tool_id is distinct from old.tool_id
     or new.project_id is distinct from old.project_id or new.issued_to is distinct from old.issued_to
     or new.issued_by is distinct from old.issued_by or new.issued_on is distinct from old.issued_on then
    raise exception 'who had the tool is not rewritten' using errcode = '42501';
  end if;
  if old.return_condition is not null then
    if new.return_condition is not distinct from old.return_condition then
      return old;
    end if;
    raise exception 'this tool was already taken back' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function tool_issues_guard() from public, anon, authenticated;

-- A tool that comes back damaged goes for repair, whoever took it back
-- (a site engineer cannot edit the register itself).
create or replace function tool_issues_mark_repair()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.return_condition = 'damaged' and old.return_condition is null then
    update tools set condition = 'repair', updated_at = now() where id = new.tool_id and condition = 'in_use';
  end if;
  return null;
end $$;
revoke all on function tool_issues_mark_repair() from public, anon, authenticated;

create or replace function wh_stamp_creator()
returns trigger language plpgsql as $$
begin
  new.created_by := auth.uid();
  if new.created_at is null or new.created_at > now() + interval '5 minutes' then
    new.created_at := now();
  end if;
  return new;
end $$;

-- A paid salary is kept as it was paid.
create or replace function payroll_lines_keep_paid()
returns trigger language plpgsql as $$
begin
  if old.status = 'paid' then
    if new.status = 'paid' then
      return old;
    end if;
    raise exception 'a paid salary is not changed' using errcode = '42501';
  end if;
  if new.staff_id is distinct from old.staff_id or new.month is distinct from old.month
     or new.company_id is distinct from old.company_id then
    raise exception 'a payslip stays with its person and month' using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists stores_stamp on stores;
create trigger stores_stamp before insert on stores for each row execute function wh_stamp_creator();
drop trigger if exists tools_stamp on tools;
create trigger tools_stamp before insert on tools for each row execute function wh_stamp_creator();
drop trigger if exists staff_advances_stamp on staff_advances;
create trigger staff_advances_stamp before insert on staff_advances for each row execute function wh_stamp_creator();
drop trigger if exists payroll_lines_stamp on payroll_lines;
create trigger payroll_lines_stamp before insert on payroll_lines for each row execute function wh_stamp_creator();

drop trigger if exists stock_moves_guard on stock_moves;
create trigger stock_moves_guard before insert or update on stock_moves for each row execute function stock_moves_guard();
drop trigger if exists tool_issues_guard on tool_issues;
create trigger tool_issues_guard before insert or update on tool_issues for each row execute function tool_issues_guard();
drop trigger if exists tool_issues_mark_repair on tool_issues;
create trigger tool_issues_mark_repair after update on tool_issues for each row execute function tool_issues_mark_repair();
drop trigger if exists payroll_lines_keep_paid on payroll_lines;
create trigger payroll_lines_keep_paid before update on payroll_lines for each row execute function payroll_lines_keep_paid();

do $$
declare t text;
begin
  foreach t in array array['stock_moves', 'tools', 'tool_issues', 'staff_members', 'staff_advances', 'payroll_lines'] loop
    execute format('drop trigger if exists %I on %I', t || '_company', t);
    execute format('create trigger %I before insert or update on %I for each row execute function wh_check_company()',
                   t || '_company', t);
  end loop;
end $$;

-- --- Grants and row level security -----------------------------------------

alter table stores enable row level security;
alter table stock_moves enable row level security;
alter table tools enable row level security;
alter table tool_issues enable row level security;
alter table staff_members enable row level security;
alter table staff_advances enable row level security;
alter table payroll_lines enable row level security;

revoke all on table stores, stock_moves, tools, tool_issues, staff_members, staff_advances, payroll_lines
  from anon, authenticated;
-- Nothing is deleted except a draft payslip: stores are archived, moves
-- called back, tools retired.
grant select, insert, update on table stores, stock_moves, tools, tool_issues, staff_members, payroll_lines to authenticated;
grant select, insert on table staff_advances to authenticated;
grant delete on table payroll_lines to authenticated;

-- Stores: every member reads them (a site sends leftovers back to one);
-- owners and managers keep them.
drop policy if exists "members read stores" on stores;
create policy "members read stores" on stores for select to authenticated
  using ((select is_company_member(company_id)));
drop policy if exists "owner/pm add stores" on stores;
create policy "owner/pm add stores" on stores for insert to authenticated
  with check ((select is_company_owner_or_pm(company_id)));
drop policy if exists "owner/pm edit stores" on stores;
create policy "owner/pm edit stores" on stores for update to authenticated
  using ((select is_company_owner_or_pm(company_id))) with check ((select is_company_owner_or_pm(company_id)));

-- Moves: managers see all; a site's team sees what came to or left its site.
drop policy if exists "read stock_moves" on stock_moves;
create policy "read stock_moves" on stock_moves for select to authenticated using (
  (select is_company_owner_or_pm(company_id))
  or (from_project_id is not null and has_project_access(from_project_id))
  or (to_project_id is not null and has_project_access(to_project_id)));
drop policy if exists "add stock_moves" on stock_moves;
create policy "add stock_moves" on stock_moves for insert to authenticated with check (
  (select is_company_owner_or_pm(company_id))
  or (kind = 'transfer' and from_project_id is not null and has_project_access(from_project_id)
      and (select is_company_member(company_id))));
drop policy if exists "receive stock_moves" on stock_moves;
create policy "receive stock_moves" on stock_moves for update to authenticated using (
  (select is_company_owner_or_pm(company_id))
  or (to_project_id is not null and has_project_access(to_project_id))
  or (from_project_id is not null and has_project_access(from_project_id)))
  with check (
  (select is_company_owner_or_pm(company_id))
  or (to_project_id is not null and has_project_access(to_project_id))
  or (from_project_id is not null and has_project_access(from_project_id)));

-- Tools register: members read it; managers keep it.
drop policy if exists "members read tools" on tools;
create policy "members read tools" on tools for select to authenticated using ((select is_company_member(company_id)));
drop policy if exists "owner/pm add tools" on tools;
create policy "owner/pm add tools" on tools for insert to authenticated
  with check ((select is_company_owner_or_pm(company_id)));
drop policy if exists "owner/pm edit tools" on tools;
create policy "owner/pm edit tools" on tools for update to authenticated
  using ((select is_company_owner_or_pm(company_id))) with check ((select is_company_owner_or_pm(company_id)));

-- Tool issues: managers, or the team of the site it was issued for.
drop policy if exists "read tool_issues" on tool_issues;
create policy "read tool_issues" on tool_issues for select to authenticated using (
  (select is_company_owner_or_pm(company_id)) or (project_id is not null and has_project_access(project_id)));
drop policy if exists "add tool_issues" on tool_issues;
create policy "add tool_issues" on tool_issues for insert to authenticated with check (
  (select is_company_owner_or_pm(company_id))
  or (project_id is not null and has_project_access(project_id) and (select is_company_member(company_id))));
drop policy if exists "return tool_issues" on tool_issues;
create policy "return tool_issues" on tool_issues for update to authenticated
  using ((select is_company_owner_or_pm(company_id)) or (project_id is not null and has_project_access(project_id)))
  with check ((select is_company_owner_or_pm(company_id)) or (project_id is not null and has_project_access(project_id)));

-- Salaries: owners and project managers only.
do $$
declare t text;
begin
  foreach t in array array['staff_members', 'staff_advances', 'payroll_lines'] loop
    execute format('drop policy if exists %I on %I', 'owner/pm read ' || t, t);
    execute format('create policy %I on %I for select to authenticated using ((select is_company_owner_or_pm(company_id)))',
                   'owner/pm read ' || t, t);
    execute format('drop policy if exists %I on %I', 'owner/pm add ' || t, t);
    execute format('create policy %I on %I for insert to authenticated with check ((select is_company_owner_or_pm(company_id)))',
                   'owner/pm add ' || t, t);
  end loop;
  foreach t in array array['staff_members', 'payroll_lines'] loop
    execute format('drop policy if exists %I on %I', 'owner/pm edit ' || t, t);
    execute format('create policy %I on %I for update to authenticated using ((select is_company_owner_or_pm(company_id))) '
                   'with check ((select is_company_owner_or_pm(company_id)))', 'owner/pm edit ' || t, t);
  end loop;
end $$;
drop policy if exists "owner/pm remove draft payroll_lines" on payroll_lines;
create policy "owner/pm remove draft payroll_lines" on payroll_lines for delete to authenticated
  using ((select is_company_owner_or_pm(company_id)) and status = 'draft');

-- --- Change log (20261110020000_incremental_sync.sql) -----------------------

create or replace function log_company_row_change()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  r jsonb := to_jsonb(case when tg_op = 'DELETE' then old else new end);
begin
  insert into sync_changes (table_name, row_id, op, project_id, company_id)
  values (tg_table_name, (r->>'id')::uuid, case when tg_op = 'DELETE' then 'd' else 'u' end,
          null, (r->>'company_id')::uuid);
  return null;
end $$;
revoke all on function log_company_row_change() from public, anon, authenticated;

do $$
declare t text;
begin
  foreach t in array array['stores', 'stock_moves', 'tools', 'tool_issues', 'staff_members', 'staff_advances',
                           'payroll_lines'] loop
    execute format('drop trigger if exists %I on %I', t || '_log_sync_change', t);
    execute format('create trigger %I after insert or update or delete on %I for each row execute function log_company_row_change()',
                   t || '_log_sync_change', t);
  end loop;
end $$;
