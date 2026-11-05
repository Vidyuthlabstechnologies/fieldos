-- Site attendance punches, expenses (incl. wages and advances paid to
-- workers), material received and used, and money received from the
-- client, synced from the phones so an owner sees every site from anywhere.
--
-- These are phone-shaped tables of their own rather than mappings onto the
-- desktop app's `attendance` (a daily present/absent summary) and `grns`
-- (PO-linked receipts): see fieldos_mobile/lib/sync/sync_mappers.dart.
-- Rows are append-only apart from a punch-out, so there is no delete path.

create table if not exists site_attendance (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  worker_name text not null check (char_length(worker_name) between 1 and 120),
  worker_id uuid references workers(id) on delete set null,
  recorded_by uuid not null references auth.users(id),
  punch_in timestamptz not null,
  punch_out timestamptz,
  lat double precision,
  lng double precision,
  within_geofence boolean,
  created_at timestamptz not null default now()
);
create index if not exists site_attendance_project_idx on site_attendance (project_id, punch_in);

create table if not exists site_expenses (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  cost_head_id uuid,
  category text not null check (char_length(category) between 1 and 50),
  amount numeric(14, 2) not null check (amount >= 0),
  incurred_on text not null check (char_length(incurred_on) between 1 and 30),
  recorded_by uuid not null references auth.users(id),
  note text check (char_length(note) <= 300),
  worker_id uuid references workers(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists site_expenses_project_idx on site_expenses (project_id);

create table if not exists site_material_receipts (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  po_id uuid,
  supplier_id uuid,
  cost_head_id uuid,
  material_name text not null check (char_length(material_name) between 1 and 200),
  quantity numeric(14, 3) not null,
  unit text check (char_length(unit) <= 20),
  amount numeric(14, 2) not null,
  received_by uuid not null references auth.users(id),
  received_on timestamptz not null,
  notes text check (char_length(notes) <= 500),
  created_at timestamptz not null default now()
);
create index if not exists site_material_receipts_project_idx on site_material_receipts (project_id);

create table if not exists site_material_usage (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  material_name text not null check (char_length(material_name) between 1 and 200),
  quantity numeric(14, 3) not null check (quantity > 0),
  unit text check (char_length(unit) <= 20),
  recorded_by uuid not null references auth.users(id),
  used_on timestamptz not null,
  note text check (char_length(note) <= 300),
  created_at timestamptz not null default now()
);
create index if not exists site_material_usage_project_idx on site_material_usage (project_id);

-- Money in is the owner's and PM's business, not every site engineer's.
create table if not exists site_payments_received (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  amount numeric(14, 2) not null check (amount > 0),
  received_on timestamptz not null,
  from_party text not null check (char_length(from_party) between 1 and 120),
  mode text not null check (mode in ('cash', 'upi', 'bank', 'cheque')),
  recorded_by uuid not null references auth.users(id),
  note text check (char_length(note) <= 300),
  created_at timestamptz not null default now()
);
create index if not exists site_payments_received_project_idx on site_payments_received (project_id);

do $$
declare t text;
begin
  foreach t in array array['site_attendance', 'site_expenses', 'site_material_receipts', 'site_material_usage', 'site_payments_received']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on table %I from anon, authenticated', t);
    execute format('grant all on table %I to service_role', t);
  end loop;
end $$;

grant select, insert, update on site_attendance to authenticated;
grant select, insert on site_expenses, site_material_receipts, site_material_usage, site_payments_received to authenticated;

create policy "project members read punches" on site_attendance for select
  to authenticated using ((select has_project_access(project_id)));
create policy "project members punch in as themselves" on site_attendance for insert
  to authenticated with check (recorded_by = (select auth.uid()) and (select has_project_access(project_id)));
-- Punch-out: whoever has the project can close a punch, but not move it
-- to another project or change who recorded it.
create policy "project members punch out" on site_attendance for update
  to authenticated using ((select has_project_access(project_id)))
  with check ((select has_project_access(project_id)));

create policy "project members read expenses" on site_expenses for select
  to authenticated using ((select has_project_access(project_id)));
create policy "project members add expenses as themselves" on site_expenses for insert
  to authenticated with check (recorded_by = (select auth.uid()) and (select has_project_access(project_id)));

create policy "project members read receipts" on site_material_receipts for select
  to authenticated using ((select has_project_access(project_id)));
create policy "project members add receipts as themselves" on site_material_receipts for insert
  to authenticated with check (received_by = (select auth.uid()) and (select has_project_access(project_id)));

create policy "project members read usage" on site_material_usage for select
  to authenticated using ((select has_project_access(project_id)));
create policy "project members add usage as themselves" on site_material_usage for insert
  to authenticated with check (recorded_by = (select auth.uid()) and (select has_project_access(project_id)));

create policy "owners and PMs read money in" on site_payments_received for select
  to authenticated using ((select is_project_owner_or_pm(project_id)));
create policy "owners and PMs add money in" on site_payments_received for insert
  to authenticated with check (recorded_by = (select auth.uid()) and (select is_project_owner_or_pm(project_id)));

-- recorded_by / project_id can't be rewritten on punch-out.
create or replace function site_attendance_keep_owner()
returns trigger language plpgsql as $$
begin
  new.recorded_by := old.recorded_by;
  new.project_id := old.project_id;
  new.punch_in := old.punch_in;
  return new;
end $$;
drop trigger if exists site_attendance_keep_owner on site_attendance;
create trigger site_attendance_keep_owner before update on site_attendance
  for each row execute function site_attendance_keep_owner();

-- Site engineers register the labourers they punch in; until now only an
-- owner/PM could, so an engineer's first new worker was refused by the
-- cloud and held up everything queued after it on that phone. Changing a
-- worker (wage, status) stays with owners and PMs.
drop policy if exists "owner/pm can create workers" on workers;
create policy "project members can add workers" on workers for insert
  to authenticated with check ((select has_project_access(project_id)));
