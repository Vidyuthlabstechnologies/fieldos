-- Free supplier and client portals (2026-11-10).
--
-- Suppliers and clients use FieldOS free, online, through the functions
-- below. They are not company members and nothing of the company syncs to
-- their phones: each function returns only what that party may see.
--
-- Supplier (a vendor of the company), joined with a code the owner or a
-- project manager shares:
-- - sees the price requests the builder asked them to quote, and sends a
--   price (it lands as a received supplier quote, compared on the site);
-- - sees their own purchase orders, says one is on the way (vehicle, when)
--   and sees when it was received.
-- Client (the site's owner or customer), joined with a code for one site:
-- - sees the site's progress (tasks done, recent daily reports and their
--   photos), and the bills raised to them and the payments recorded.

-- --- Supplier links ------------------------------------------------------------

create table if not exists supplier_users (
  vendor_id uuid not null references vendors(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (vendor_id, user_id)
);
create index if not exists supplier_users_user_idx on supplier_users (user_id);

create table if not exists supplier_codes (
  vendor_id uuid primary key references vendors(id) on delete cascade,
  code text not null unique,
  created_at timestamptz not null default now()
);

-- Which suppliers the site asked for a price on a request.
create table if not exists rfq_invites (
  request_id uuid not null references purchase_requisitions(id) on delete cascade,
  vendor_id uuid not null references vendors(id) on delete cascade,
  invited_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now(),
  primary key (request_id, vendor_id)
);

-- A purchase order on its way, as the supplier says.
alter table purchase_orders add column if not exists dispatched_on timestamptz;
alter table purchase_orders add column if not exists dispatch_vehicle text check (char_length(dispatch_vehicle) <= 40);
alter table purchase_orders add column if not exists supplier_note text check (char_length(supplier_note) <= 300);

-- --- Client links --------------------------------------------------------------

create table if not exists client_users (
  project_id uuid not null references projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (project_id, user_id)
);
create index if not exists client_users_user_idx on client_users (user_id);

create table if not exists client_codes (
  project_id uuid primary key references projects(id) on delete cascade,
  code text not null unique,
  created_at timestamptz not null default now()
);

do $$
declare t text;
begin
  foreach t in array array['supplier_users', 'supplier_codes', 'rfq_invites', 'client_users', 'client_codes'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on table %I from anon, authenticated', t);
  end loop;
end $$;
-- Only through the functions below; owners and PMs may list links.
grant select on table supplier_users, client_users, rfq_invites to authenticated;
drop policy if exists "own or manager reads supplier links" on supplier_users;
create policy "own or manager reads supplier links" on supplier_users for select to authenticated
  using (user_id = (select auth.uid())
         or (select is_company_owner_or_pm((select company_id from vendors v where v.id = vendor_id))));
drop policy if exists "own or manager reads client links" on client_users;
create policy "own or manager reads client links" on client_users for select to authenticated
  using (user_id = (select auth.uid())
         or (select is_company_owner_or_pm((select company_id from projects p where p.id = project_id))));
drop policy if exists "site team reads rfq invites" on rfq_invites;
create policy "site team reads rfq invites" on rfq_invites for select to authenticated
  using ((select has_project_access((select project_id from purchase_requisitions r where r.id = request_id))));

create or replace function is_client_on_project(p_project_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (select 1 from client_users where project_id = p_project_id and user_id = (select auth.uid()));
$$;
revoke all on function is_client_on_project(uuid) from public, anon;
grant execute on function is_client_on_project(uuid) to authenticated;

-- A code no other company, subcontractor, supplier or client uses.
create or replace function new_portal_code()
returns text language plpgsql security definer set search_path = public as $$
declare v text;
begin
  loop
    v := new_join_code();
    exit when not exists (select 1 from companies where join_code = v)
          and not exists (select 1 from subcontractor_codes where code = v)
          and not exists (select 1 from supplier_codes where code = v)
          and not exists (select 1 from client_codes where code = v);
  end loop;
  return v;
end $$;
revoke all on function new_portal_code() from public, anon, authenticated;

-- --- Owner or PM: codes and invitations ------------------------------------------

create or replace function supplier_access_code(p_vendor_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_company uuid; v_code text;
begin
  select company_id into v_company from vendors where id = p_vendor_id;
  if v_company is null or not is_company_owner_or_pm(v_company) then
    raise exception 'only the owner or a project manager can share a supplier code' using errcode = '42501';
  end if;
  select code into v_code from supplier_codes where vendor_id = p_vendor_id;
  if v_code is null then
    v_code := new_portal_code();
    insert into supplier_codes (vendor_id, code) values (p_vendor_id, v_code);
  end if;
  return v_code;
end $$;

create or replace function client_access_code(p_project_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_company uuid; v_code text;
begin
  select company_id into v_company from projects where id = p_project_id;
  if v_company is null or not is_company_owner_or_pm(v_company) then
    raise exception 'only the owner or a project manager can share a client code' using errcode = '42501';
  end if;
  select code into v_code from client_codes where project_id = p_project_id;
  if v_code is null then
    v_code := new_portal_code();
    insert into client_codes (project_id, code) values (p_project_id, v_code);
  end if;
  return v_code;
end $$;

-- The site's team asks suppliers for a price on a request. Returns how many
-- of them can see it in the app now (linked to a login).
create or replace function invite_suppliers_to_quote(p_request_id uuid, p_vendor_ids uuid[])
returns int language plpgsql security definer set search_path = public as $$
declare v_project uuid; v_company uuid;
begin
  select r.project_id, p.company_id into v_project, v_company
    from purchase_requisitions r join projects p on p.id = r.project_id where r.id = p_request_id;
  if v_project is null or not has_project_access(v_project) or not is_company_member(v_company) then
    raise exception 'not your site' using errcode = '42501';
  end if;
  insert into rfq_invites (request_id, vendor_id, invited_by)
  select p_request_id, v.id, auth.uid() from vendors v
   where v.id = any(p_vendor_ids) and v.company_id = v_company
  on conflict do nothing;
  return (select count(distinct su.vendor_id) from supplier_users su
           where su.vendor_id = any(p_vendor_ids)
             and exists (select 1 from rfq_invites i where i.request_id = p_request_id and i.vendor_id = su.vendor_id));
end $$;

-- --- Joining ----------------------------------------------------------------------

-- Same limits as join_company: 10 wrong codes an hour.
create or replace function join_portal(p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^0-9A-Za-z]', '', 'g'));
  v_vendor vendors%rowtype;
  v_project projects%rowtype;
  v_company companies%rowtype;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if (select count(*) from join_attempts where user_id = v_uid and attempted_at > now() - interval '1 hour') >= 10 then
    return json_build_object('error', 'too_many_attempts');
  end if;
  select v.* into v_vendor from vendors v join supplier_codes c on c.vendor_id = v.id where c.code = v_code;
  if found then
    select * into v_company from companies where id = v_vendor.company_id;
    insert into supplier_users (vendor_id, user_id) values (v_vendor.id, v_uid) on conflict do nothing;
    return json_build_object('kind', 'supplier', 'id', v_vendor.id, 'name', v_vendor.name,
                             'company_id', v_company.id, 'company_name', v_company.name);
  end if;
  select p.* into v_project from projects p join client_codes c on c.project_id = p.id where c.code = v_code;
  if found then
    select * into v_company from companies where id = v_project.company_id;
    insert into client_users (project_id, user_id) values (v_project.id, v_uid) on conflict do nothing;
    return json_build_object('kind', 'client', 'id', v_project.id, 'name', v_project.name,
                             'company_id', v_company.id, 'company_name', v_company.name);
  end if;
  insert into join_attempts (user_id) values (v_uid);
  return json_build_object('error', 'invalid_join_code');
end $$;

-- --- The supplier's view and actions ------------------------------------------------

create or replace function supplier_portal()
returns json language sql security definer set search_path = public stable as $$
  select json_build_object(
    'suppliers', coalesce((
      select json_agg(json_build_object('id', v.id, 'name', v.name, 'company_name', c.name) order by c.name)
        from supplier_users su join vendors v on v.id = su.vendor_id join companies c on c.id = v.company_id
       where su.user_id = auth.uid()), '[]'::json),
    'requests', coalesce((
      select json_agg(json_build_object(
               'id', r.id, 'vendor_id', i.vendor_id, 'site', p.name, 'company_name', c.name,
               'item', r.item_name, 'quantity', r.quantity, 'unit', r.unit, 'urgency', r.urgency,
               'notes', r.notes, 'asked_on', i.created_at, 'open', r.status in ('pending', 'approved'),
               'quote', (select json_build_object('rate', q.rate, 'gst_pct', q.gst_pct, 'transport', q.transport,
                                                  'delivery_days', q.delivery_days, 'payment_terms', q.payment_terms,
                                                  'status', q.status)
                           from site_supplier_quotes q
                          where q.request_id = r.id and q.vendor_id = i.vendor_id
                          order by q.created_at desc limit 1))
             order by i.created_at desc)
        from rfq_invites i
        join supplier_users su on su.vendor_id = i.vendor_id and su.user_id = auth.uid()
        join purchase_requisitions r on r.id = i.request_id
        join projects p on p.id = r.project_id
        join companies c on c.id = p.company_id), '[]'::json),
    'orders', coalesce((
      select json_agg(json_build_object(
               'id', o.id, 'vendor_id', o.vendor_id, 'po_number', o.po_number, 'site', p.name, 'company_name', c.name,
               'total', o.total_amount, 'delivery_date', o.delivery_date, 'status', o.status,
               'created_at', o.created_at, 'dispatched_on', o.dispatched_on, 'vehicle', o.dispatch_vehicle,
               'supplier_note', o.supplier_note,
               'item', (select r.item_name from purchase_requisitions r where r.id = o.requisition_id))
             order by o.created_at desc)
        from purchase_orders o
        join supplier_users su on su.vendor_id = o.vendor_id and su.user_id = auth.uid()
        join projects p on p.id = o.project_id
        join companies c on c.id = p.company_id
       where o.status <> 'cancelled'), '[]'::json));
$$;

-- A price for a request they were asked about; a second price replaces the
-- first while the site has not decided.
create or replace function supplier_send_quote(p_request_id uuid, p_vendor_id uuid, p_rate numeric, p_gst_pct numeric,
                                               p_transport numeric, p_delivery_days int, p_payment_terms text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_project uuid; v_status text; v_id uuid;
begin
  if not exists (select 1 from supplier_users where vendor_id = p_vendor_id and user_id = auth.uid())
     or not exists (select 1 from rfq_invites where request_id = p_request_id and vendor_id = p_vendor_id) then
    raise exception 'you were not asked for a price on this' using errcode = '42501';
  end if;
  select project_id, status into v_project, v_status from purchase_requisitions where id = p_request_id;
  if v_status not in ('pending', 'approved') then
    raise exception 'this request is closed' using errcode = '22023';
  end if;
  if not (p_rate > 0) or p_gst_pct < 0 or p_gst_pct > 28 or coalesce(p_transport, 0) < 0
     or coalesce(p_delivery_days, 0) < 0 then
    raise exception 'check the rate, GST, transport and days' using errcode = '22023';
  end if;
  if exists (select 1 from site_supplier_quotes where request_id = p_request_id and vendor_id = p_vendor_id
                                                  and status <> 'received') then
    raise exception 'the site has decided on your price' using errcode = '42501';
  end if;
  select id into v_id from site_supplier_quotes
   where request_id = p_request_id and vendor_id = p_vendor_id and status = 'received'
   order by created_at desc limit 1;
  if v_id is null then
    v_id := gen_random_uuid();
    insert into site_supplier_quotes (id, project_id, request_id, vendor_id, rate, gst_pct, transport, delivery_days,
                                      payment_terms, notes)
    values (v_id, v_project, p_request_id, p_vendor_id, p_rate, p_gst_pct, coalesce(p_transport, 0), p_delivery_days,
            left(nullif(trim(p_payment_terms), ''), 120), 'Sent by the supplier in FieldOS');
  else
    update site_supplier_quotes set rate = p_rate, gst_pct = p_gst_pct, transport = coalesce(p_transport, 0),
           delivery_days = p_delivery_days, payment_terms = left(nullif(trim(p_payment_terms), ''), 120)
     where id = v_id;
  end if;
  return v_id;
end $$;

-- The supplier says an order is on its way (or corrects the vehicle).
create or replace function supplier_dispatch(p_po_id uuid, p_vehicle text, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare v_status text;
begin
  select o.status into v_status from purchase_orders o
    join supplier_users su on su.vendor_id = o.vendor_id and su.user_id = auth.uid()
   where o.id = p_po_id;
  if v_status is null then
    raise exception 'not your order' using errcode = '42501';
  end if;
  if v_status in ('delivered', 'cancelled') then
    raise exception 'this order is closed' using errcode = '22023';
  end if;
  update purchase_orders
     set status = 'acknowledged',
         dispatched_on = coalesce(dispatched_on, now()),
         dispatch_vehicle = left(nullif(trim(p_vehicle), ''), 40),
         supplier_note = left(nullif(trim(p_note), ''), 300)
   where id = p_po_id;
end $$;

-- --- The client's view ----------------------------------------------------------

create or replace function client_portal()
returns json language sql security definer set search_path = public stable as $$
  select coalesce(json_agg(json_build_object(
    'id', p.id, 'name', p.name, 'company_name', c.name, 'status', p.status,
    'start_date', p.start_date, 'end_date', p.end_date,
    'tasks_total', (select count(*) from tasks t where t.project_id = p.id),
    'tasks_done', (select count(*) from tasks t where t.project_id = p.id and t.status = 'done'),
    'updates', coalesce((
      select json_agg(u order by u.entry_date desc) from (
        select d.id, d.entry_date, d.work_summary, d.manpower_count, d.weather,
               coalesce((select json_agg(ph.photo_path) from (
                  select x.photo_path from dpr_photos x where x.dpr_entry_id = d.id order by x.created_at limit 4) ph),
                 '[]'::json) as photos
          from dpr_entries d
         where d.project_id = p.id and d.status = 'confirmed'
         order by d.entry_date desc limit 20) u), '[]'::json),
    'bills', coalesce((
      select json_agg(json_build_object('number', b.bill_number, 'date', b.bill_date, 'kind', b.kind,
                                        'amount', b.net_payable, 'status', b.status) order by b.bill_date desc)
        from site_client_bills b where b.project_id = p.id), '[]'::json),
    'payments', coalesce((
      select json_agg(json_build_object('date', r.received_on, 'amount', r.amount, 'mode', r.mode)
                      order by r.received_on desc)
        from site_payments_received r where r.project_id = p.id), '[]'::json)
  ) order by p.name), '[]'::json)
  from client_users cu join projects p on p.id = cu.project_id join companies c on c.id = p.company_id
  where cu.user_id = auth.uid();
$$;

-- Clients read their site's daily report photos (a signed link per photo).
drop policy if exists "clients read site photos" on storage.objects;
create policy "clients read site photos" on storage.objects for select to authenticated using (
  bucket_id = 'documents' and (storage.foldername(name))[2] = 'dpr-photos'
  and (select is_client_on_project(((storage.foldername(name))[1])::uuid)));

-- --- Grants ---------------------------------------------------------------------

revoke all on function supplier_access_code(uuid), client_access_code(uuid), invite_suppliers_to_quote(uuid, uuid[]),
  join_portal(text), supplier_portal(), supplier_send_quote(uuid, uuid, numeric, numeric, numeric, int, text),
  supplier_dispatch(uuid, text, text), client_portal() from public, anon;
grant execute on function supplier_access_code(uuid), client_access_code(uuid), invite_suppliers_to_quote(uuid, uuid[]),
  join_portal(text), supplier_portal(), supplier_send_quote(uuid, uuid, numeric, numeric, numeric, int, text),
  supplier_dispatch(uuid, text, text), client_portal() to authenticated;
