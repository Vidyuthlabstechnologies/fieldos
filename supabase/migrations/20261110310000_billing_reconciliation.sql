-- Measurement to billing, and reconciliation (app schema v18, 2026-11-10).
--
-- 1. site_work_measurements: the measurement book for the client. The site
--    measures work done against a BOQ item (a cost head, with its rate);
--    the owner or a project manager approves or rejects each measurement
--    (site_work_measurement_decisions, one decision per measurement,
--    insert-only). The next RA bill takes the approved quantity to date
--    less what earlier bills billed.
-- 2. site_bill_allocations: what part of a payment received pays which
--    bill, or releases which bill's retention. A part payment can spread
--    over several bills; a bill can be paid over several payments. The
--    server refuses to allocate more than the payment.
-- 3. site_supplier_invoices: a supplier's invoice, checked on the phone
--    against its purchase order and what was actually received (GRNs).
--
-- Money to and from the client stays the owner's and PM's business, like
-- site_client_bills. Measurements and supplier invoices are recorded by
-- anyone on the site.

-- 1. Measurement book --------------------------------------------------------

create table if not exists site_work_measurements (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  cost_head_id uuid references cost_heads(id) on delete set null,
  description text not null check (char_length(description) between 1 and 200),
  unit text not null check (char_length(unit) between 1 and 20),
  rate numeric(14, 2) check (rate is null or rate >= 0),
  -- Below zero corrects an earlier over-measurement.
  qty numeric(14, 3) not null check (qty <> 0),
  measured_on date not null,
  location text check (char_length(location) <= 200),
  note text check (char_length(note) <= 300),
  measured_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists site_work_measurements_project_idx on site_work_measurements (project_id, measured_on);

alter table site_work_measurements enable row level security;
revoke all on table site_work_measurements from anon, authenticated;
grant all on table site_work_measurements to service_role;
grant select, insert on table site_work_measurements to authenticated;

drop policy if exists "site team reads measurements" on site_work_measurements;
create policy "site team reads measurements" on site_work_measurements for select
  to authenticated using ((select has_project_access(project_id)));
drop policy if exists "site team measures as themselves" on site_work_measurements;
create policy "site team measures as themselves" on site_work_measurements for insert
  to authenticated with check (measured_by = (select auth.uid()) and (select has_project_access(project_id)));

create table if not exists site_work_measurement_decisions (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  measurement_id uuid not null unique references site_work_measurements(id) on delete cascade,
  decision text not null check (decision in ('approved', 'rejected')),
  approved_qty numeric(14, 3),
  note text check (char_length(note) <= 300),
  decided_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  check ((decision = 'approved') = (approved_qty is not null))
);
create index if not exists site_work_measurement_decisions_project_idx on site_work_measurement_decisions (project_id);

alter table site_work_measurement_decisions enable row level security;
revoke all on table site_work_measurement_decisions from anon, authenticated;
grant all on table site_work_measurement_decisions to service_role;
grant select, insert on table site_work_measurement_decisions to authenticated;

drop policy if exists "site team reads measurement decisions" on site_work_measurement_decisions;
create policy "site team reads measurement decisions" on site_work_measurement_decisions for select
  to authenticated using ((select has_project_access(project_id)));
drop policy if exists "managers decide measurements as themselves" on site_work_measurement_decisions;
create policy "managers decide measurements as themselves" on site_work_measurement_decisions for insert
  to authenticated with check (
    decided_by = (select auth.uid())
    and (select is_project_owner_or_pm(project_id))
    and exists (select 1 from site_work_measurements m where m.id = measurement_id and m.project_id = project_id));

-- An approved quantity has the measurement's sign and is no bigger.
create or replace function site_work_measurement_decisions_check()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_qty numeric;
begin
  select qty into v_qty from site_work_measurements where id = new.measurement_id;
  if new.decision = 'approved' and (sign(new.approved_qty) <> sign(v_qty) or abs(new.approved_qty) > abs(v_qty)) then
    raise exception 'approved quantity must be between zero and the measured quantity' using errcode = '23514';
  end if;
  return new;
end $$;
revoke all on function site_work_measurement_decisions_check() from public, anon, authenticated;
drop trigger if exists site_work_measurement_decisions_check on site_work_measurement_decisions;
create trigger site_work_measurement_decisions_check before insert on site_work_measurement_decisions
  for each row execute function site_work_measurement_decisions_check();

-- 2. Payments against bills ---------------------------------------------------

create table if not exists site_bill_allocations (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  payment_id uuid not null references site_payments_received(id) on delete cascade,
  bill_id uuid not null references site_client_bills(id) on delete cascade,
  -- 'bill': pays the bill's net amount; 'retention': releases its retention.
  kind text not null default 'bill' check (kind in ('bill', 'retention')),
  amount numeric(14, 2) not null check (amount > 0),
  note text check (char_length(note) <= 300),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists site_bill_allocations_project_idx on site_bill_allocations (project_id);
create index if not exists site_bill_allocations_payment_idx on site_bill_allocations (payment_id);
create index if not exists site_bill_allocations_bill_idx on site_bill_allocations (bill_id);

alter table site_bill_allocations enable row level security;
revoke all on table site_bill_allocations from anon, authenticated;
grant all on table site_bill_allocations to service_role;
grant select, insert, delete on table site_bill_allocations to authenticated;

drop policy if exists "owners and PMs read allocations" on site_bill_allocations;
create policy "owners and PMs read allocations" on site_bill_allocations for select
  to authenticated using ((select is_project_owner_or_pm(project_id)));
drop policy if exists "owners and PMs allocate as themselves" on site_bill_allocations;
create policy "owners and PMs allocate as themselves" on site_bill_allocations for insert
  to authenticated with check (created_by = (select auth.uid()) and (select is_project_owner_or_pm(project_id)));
drop policy if exists "owners and PMs undo allocations" on site_bill_allocations;
create policy "owners and PMs undo allocations" on site_bill_allocations for delete
  to authenticated using ((select is_project_owner_or_pm(project_id)));

-- Payment and bill belong to the allocation's site; a payment is never
-- allocated beyond its amount, a bill never paid beyond its net amount,
-- and retention never released beyond what was kept back.
create or replace function site_bill_allocations_check()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_payment site_payments_received;
  v_bill site_client_bills;
  v_used numeric;
begin
  select * into v_payment from site_payments_received where id = new.payment_id for update;
  select * into v_bill from site_client_bills where id = new.bill_id;
  if v_payment.project_id <> new.project_id or v_bill.project_id <> new.project_id then
    raise exception 'payment and bill must be on this site' using errcode = '23514';
  end if;
  if coalesce(v_payment.voided, false) then
    raise exception 'a cancelled payment pays nothing' using errcode = '23514';
  end if;
  select coalesce(sum(amount), 0) into v_used from site_bill_allocations where payment_id = new.payment_id;
  if v_used + new.amount > v_payment.amount + 0.005 then
    raise exception 'more than the payment' using errcode = '23514';
  end if;
  select coalesce(sum(amount), 0) into v_used from site_bill_allocations where bill_id = new.bill_id and kind = new.kind;
  if new.kind = 'bill' and v_used + new.amount > v_bill.net_payable + 0.005 then
    raise exception 'more than the bill' using errcode = '23514';
  end if;
  if new.kind = 'retention' and v_used + new.amount > round(v_bill.gross * v_bill.retention_pct / 100, 2) + 0.005 then
    raise exception 'more than the retention kept' using errcode = '23514';
  end if;
  return new;
end $$;
revoke all on function site_bill_allocations_check() from public, anon, authenticated;
drop trigger if exists site_bill_allocations_check on site_bill_allocations;
create trigger site_bill_allocations_check before insert on site_bill_allocations
  for each row execute function site_bill_allocations_check();

-- 3. Supplier invoices ---------------------------------------------------------

create table if not exists site_supplier_invoices (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  supplier_id uuid not null references vendors(id) on delete restrict,
  po_id uuid references purchase_orders(id) on delete set null,
  invoice_number text not null check (char_length(invoice_number) between 1 and 40),
  invoice_date date not null,
  -- The invoice total with GST, and the GST in it.
  amount numeric(14, 2) not null check (amount >= 0),
  gst_amount numeric(14, 2) not null default 0 check (gst_amount >= 0),
  qty numeric(14, 3) check (qty is null or qty >= 0),
  note text check (char_length(note) <= 300),
  voided boolean not null default false,
  void_reason text check (char_length(void_reason) <= 200),
  recorded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists site_supplier_invoices_project_idx on site_supplier_invoices (project_id, invoice_date);
create index if not exists site_supplier_invoices_po_idx on site_supplier_invoices (po_id);

alter table site_supplier_invoices enable row level security;
revoke all on table site_supplier_invoices from anon, authenticated;
grant all on table site_supplier_invoices to service_role;
grant select, insert, update on table site_supplier_invoices to authenticated;

drop policy if exists "site team reads supplier invoices" on site_supplier_invoices;
create policy "site team reads supplier invoices" on site_supplier_invoices for select
  to authenticated using ((select has_project_access(project_id)));
drop policy if exists "site team records supplier invoices" on site_supplier_invoices;
create policy "site team records supplier invoices" on site_supplier_invoices for insert
  to authenticated with check (recorded_by = (select auth.uid()) and (select has_project_access(project_id)));
-- The phone only updates an invoice to cancel it.
drop policy if exists "owners and PMs cancel supplier invoices" on site_supplier_invoices;
create policy "owners and PMs cancel supplier invoices" on site_supplier_invoices for update
  to authenticated using ((select is_project_owner_or_pm(project_id)))
  with check ((select is_project_owner_or_pm(project_id)));

create or replace function site_supplier_invoices_only_void()
returns trigger language plpgsql as $$
begin
  if not new.voided then
    raise exception 'an invoice can only be cancelled' using errcode = '23514';
  end if;
  new.id := old.id; new.project_id := old.project_id; new.supplier_id := old.supplier_id; new.po_id := old.po_id;
  new.invoice_number := old.invoice_number; new.invoice_date := old.invoice_date; new.amount := old.amount;
  new.gst_amount := old.gst_amount; new.qty := old.qty; new.note := old.note;
  new.recorded_by := old.recorded_by; new.created_at := old.created_at;
  return new;
end $$;
drop trigger if exists site_supplier_invoices_only_void on site_supplier_invoices;
create trigger site_supplier_invoices_only_void before update on site_supplier_invoices
  for each row execute function site_supplier_invoices_only_void();

-- Phones learn of new rows through the change log ----------------------------

do $$
declare t text;
begin
  foreach t in array array['site_work_measurements', 'site_work_measurement_decisions', 'site_bill_allocations',
                           'site_supplier_invoices']
  loop
    execute format('drop trigger if exists %I on %I', t || '_log_sync_change', t);
    execute format('create trigger %I after insert or update or delete on %I for each row execute function log_sync_change()',
                   t || '_log_sync_change', t);
  end loop;
end $$;
