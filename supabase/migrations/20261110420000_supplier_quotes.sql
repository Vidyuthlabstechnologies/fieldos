-- Supplier quotes against a purchase request (2026-11-10).
--
-- Each supplier's rate, GST, transport, delivery days and terms for one
-- purchase request, so a site compares them at their landed cost and the
-- chosen one becomes the PO. Phone-shaped, like the other site_* tables;
-- the old desktop rfqs/quotes tables are left alone.
--
-- Who: the site's team reads and adds quotes; owners and project managers
-- turn one down or give the order. Once decided, a quote's price is kept.

create table if not exists site_supplier_quotes (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  request_id uuid not null references purchase_requisitions(id) on delete cascade,
  vendor_id uuid not null references vendors(id) on delete cascade,
  rate numeric(14, 2) not null check (rate > 0),
  gst_pct numeric(5, 2) not null default 18 check (gst_pct between 0 and 28),
  transport numeric(14, 2) not null default 0 check (transport >= 0),
  delivery_days int check (delivery_days is null or delivery_days >= 0),
  payment_terms text check (char_length(payment_terms) <= 120),
  valid_until timestamptz,
  notes text check (char_length(notes) <= 300),
  status text not null default 'received' check (status in ('received', 'accepted', 'rejected')),
  po_id uuid references purchase_orders(id) on delete set null,
  created_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists site_supplier_quotes_request_idx on site_supplier_quotes (request_id);
create index if not exists site_supplier_quotes_project_idx on site_supplier_quotes (project_id);
-- One order per request.
create unique index if not exists site_supplier_quotes_one_award_idx on site_supplier_quotes (request_id)
  where status = 'accepted';

create or replace function site_supplier_quotes_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  cid uuid;
begin
  select company_id into cid from projects where id = new.project_id;
  if not exists (select 1 from purchase_requisitions r where r.id = new.request_id and r.project_id = new.project_id) then
    raise exception 'request belongs to another site' using errcode = '42501';
  end if;
  if not exists (select 1 from vendors v where v.id = new.vendor_id and v.company_id = cid) then
    raise exception 'supplier belongs to another company' using errcode = '42501';
  end if;
  if new.po_id is not null
     and not exists (select 1 from purchase_orders o where o.id = new.po_id and o.project_id = new.project_id) then
    raise exception 'order belongs to another site' using errcode = '42501';
  end if;

  if tg_op = 'INSERT' then
    new.created_by := auth.uid();
    new.created_at := now();
    if not is_company_owner_or_pm(cid) then
      new.status := 'received';
      new.po_id := null;
    end if;
    return new;
  end if;

  if new.project_id is distinct from old.project_id or new.request_id is distinct from old.request_id
     or new.vendor_id is distinct from old.vendor_id or new.created_by is distinct from old.created_by then
    raise exception 'a quote stays with its request and supplier' using errcode = '42501';
  end if;
  if old.status <> 'received' then
    -- The same decision sent again (a phone retrying) changes nothing.
    if new.status = old.status and new.rate = old.rate and new.gst_pct = old.gst_pct
       and new.transport = old.transport then
      return new;
    end if;
    raise exception 'a decided quote is kept as it was' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function site_supplier_quotes_guard() from public, anon, authenticated;

drop trigger if exists site_supplier_quotes_guard on site_supplier_quotes;
create trigger site_supplier_quotes_guard before insert or update on site_supplier_quotes
  for each row execute function site_supplier_quotes_guard();

alter table site_supplier_quotes enable row level security;
revoke all on table site_supplier_quotes from anon, authenticated;
grant select, insert, update on table site_supplier_quotes to authenticated;

drop policy if exists "site team reads supplier quotes" on site_supplier_quotes;
create policy "site team reads supplier quotes" on site_supplier_quotes for select to authenticated
  using ((select has_project_access(project_id)));
drop policy if exists "site team adds supplier quotes" on site_supplier_quotes;
create policy "site team adds supplier quotes" on site_supplier_quotes for insert to authenticated
  with check ((select has_project_access(project_id)));
drop policy if exists "owner/pm decide supplier quotes" on site_supplier_quotes;
create policy "owner/pm decide supplier quotes" on site_supplier_quotes for update to authenticated
  using ((select is_company_owner_or_pm((select company_id from projects p where p.id = project_id))))
  with check ((select is_company_owner_or_pm((select company_id from projects p where p.id = project_id))));

-- Whoever entered a quote can correct it while it is undecided (a second
-- price from the same supplier replaces the first on the phone).
drop policy if exists "creator corrects own quote" on site_supplier_quotes;
create policy "creator corrects own quote" on site_supplier_quotes for update to authenticated
  using (created_by = (select auth.uid()) and status = 'received' and (select has_project_access(project_id)))
  with check (status = 'received' and po_id is null);

-- Change log (20261110020000_incremental_sync.sql): project-scoped rows.
drop trigger if exists site_supplier_quotes_log_sync_change on site_supplier_quotes;
create trigger site_supplier_quotes_log_sync_change after insert or update or delete on site_supplier_quotes
  for each row execute function log_sync_change();
