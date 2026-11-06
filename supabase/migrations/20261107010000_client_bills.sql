-- Client bills from the phone: running account (RA) bills of measured work
-- and GST tax invoices. Money to and from the client is the owner's and
-- PM's business, like site_payments_received. Lines are the bill's items as
-- JSON text ([{d: description, u: unit, r: rate, q: quantity}]).

create table if not exists site_client_bills (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  kind text not null check (kind in ('ra', 'tax_invoice')),
  bill_number text not null check (char_length(bill_number) between 1 and 30),
  bill_date date not null,
  client_name text not null check (char_length(client_name) between 1 and 200),
  client_gstin text check (client_gstin is null or char_length(client_gstin) = 15),
  sac text not null default '995411' check (char_length(sac) <= 10),
  lines text not null check (char_length(lines) <= 100000),
  gst_rate numeric(5, 2) not null default 18 check (gst_rate between 0 and 28),
  inter_state boolean not null default false,
  retention_pct numeric(5, 2) not null default 0 check (retention_pct between 0 and 100),
  tds_pct numeric(5, 2) not null default 0 check (tds_pct between 0 and 100),
  gross numeric(14, 2) not null check (gross >= 0),
  net_payable numeric(14, 2) not null,
  status text not null default 'issued' check (status in ('issued', 'paid')),
  notes text check (char_length(notes) <= 500),
  recorded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists site_client_bills_project_idx on site_client_bills (project_id, bill_date);

alter table site_client_bills enable row level security;
revoke all on table site_client_bills from anon, authenticated;
grant all on table site_client_bills to service_role;
grant select, insert, update on site_client_bills to authenticated;

create policy "owners and PMs read bills" on site_client_bills for select
  to authenticated using ((select is_project_owner_or_pm(project_id)));
create policy "owners and PMs add bills as themselves" on site_client_bills for insert
  to authenticated with check (recorded_by = (select auth.uid()) and (select is_project_owner_or_pm(project_id)));
-- The phone only updates a bill to mark it paid or unpaid.
create policy "owners and PMs mark bills paid" on site_client_bills for update
  to authenticated using ((select is_project_owner_or_pm(project_id)))
  with check ((select is_project_owner_or_pm(project_id)));

-- An update can't move a bill to another project or change who raised it.
create or replace function site_client_bills_keep_owner()
returns trigger language plpgsql as $$
begin
  new.recorded_by := old.recorded_by;
  new.project_id := old.project_id;
  return new;
end $$;
drop trigger if exists site_client_bills_keep_owner on site_client_bills;
create trigger site_client_bills_keep_owner before update on site_client_bills
  for each row execute function site_client_bills_keep_owner();
