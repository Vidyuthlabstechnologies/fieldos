-- FieldOS shared Supabase schema: mirrors fieldos/models.py (desktop) and
-- fieldos_mobile/lib/data/tables.dart (mobile-only entities: subcontractors,
-- work_orders, approvals). Auth identity is Supabase Auth (auth.users /
-- auth.uid()), NOT this app's existing local pbkdf2 sessions table -- see
-- docs/SUPABASE_SYNC_RESEARCH.md for why that's a clean cutover, not a
-- migration. RLS role-gating mirrors fieldos/permissions.py and the
-- equivalent checks in fieldos/routers/*.py; a handful of mutation policies
-- below are marked "verify against fieldos/routers/X.py" where the exact
-- role requirement wasn't loaded with full confidence -- default is project
-- membership required (never fully open), tighten later if a router turns
-- out to require more.

create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- ===========================================================================
-- PART 1: TABLES (dependency order)
-- ===========================================================================

create table companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

create table company_members (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'project_manager', 'site_engineer')),
  created_at timestamptz not null default now(),
  unique (company_id, user_id)
);

create table projects (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  name text not null,
  client_name text,
  location_lat double precision,
  location_lng double precision,
  geofence_radius_m integer,
  start_date date,
  end_date date,
  status text not null default 'planning' check (status in ('planning', 'active', 'completed', 'on_hold')),
  created_at timestamptz not null default now()
);

create table project_members (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'project_manager', 'site_engineer')),
  created_at timestamptz not null default now(),
  unique (project_id, user_id)
);

create table tasks (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  title text not null,
  assignee_id uuid references auth.users(id),
  due_date date,
  status text not null default 'todo' check (status in ('todo', 'in_progress', 'done', 'blocked')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table dpr_entries (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  created_by uuid not null references auth.users(id),
  entry_date date not null,
  work_summary text not null,
  manpower_count integer not null default 0,
  weather text,
  status text not null default 'confirmed' check (status in ('draft', 'confirmed')),
  source text not null default 'manual' check (source in ('manual', 'voice')),
  created_at timestamptz not null default now()
);

create table dpr_photos (
  id uuid primary key default gen_random_uuid(),
  dpr_entry_id uuid not null references dpr_entries(id) on delete cascade,
  -- Supabase Storage bucket path -- bucket setup itself is out of scope here.
  photo_path text not null,
  caption text,
  created_at timestamptz not null default now()
);

create table issues (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  dpr_entry_id uuid references dpr_entries(id) on delete set null,
  description text not null,
  severity text not null default 'medium' check (severity in ('low', 'medium', 'high', 'critical')),
  status text not null default 'open' check (status in ('open', 'in_progress', 'resolved', 'closed')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create table estimations (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  name text not null,
  status text not null default 'draft' check (status in ('draft', 'active', 'completed')),
  contractor_profit_percent numeric(5, 2),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table cost_heads (
  id uuid primary key default gen_random_uuid(),
  estimation_id uuid not null references estimations(id) on delete cascade,
  name text not null,
  calculation_type text not null check (calculation_type in ('volume', 'area', 'steel_weight', 'count')),
  raw_unit text not null,
  billing_unit text not null,
  -- Numeric precision matches fieldos/models.py exactly -- this is the
  -- single most important precision requirement in this whole schema.
  conversion_factor numeric(18, 10) not null default 1,
  rate_per_unit numeric(14, 2),
  sort_order integer not null default 0
);

create table measurement_entries (
  id uuid primary key default gen_random_uuid(),
  cost_head_id uuid not null references cost_heads(id) on delete cascade,
  description text not null,
  length numeric(14, 6),
  width numeric(14, 6),
  depth numeric(14, 6),
  nos numeric(14, 6) not null default 1,
  is_deduction boolean not null default false
);

create table steel_entries (
  id uuid primary key default gen_random_uuid(),
  cost_head_id uuid not null references cost_heads(id) on delete cascade,
  description text not null,
  bar_dia_mm numeric(6, 2) not null,
  nos numeric(14, 6) not null,
  length_ft numeric(14, 6) not null
);

create table material_entries (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  entry_date date not null,
  item_name text not null,
  category text not null check (category in
    ('cement', 'sand', 'aggregate', 'steel', 'brick', 'timber', 'pipe', 'electrical', 'plumbing', 'paint', 'other')),
  quantity numeric(14, 3) not null,
  unit text not null,
  supplier text,
  cost numeric(14, 2),
  notes text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table material_photos (
  id uuid primary key default gen_random_uuid(),
  material_entry_id uuid not null references material_entries(id) on delete cascade,
  photo_path text not null,
  caption text,
  created_at timestamptz not null default now()
);

create table workers (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  name text not null,
  role text,
  phone text,
  daily_wage numeric(10, 2),
  status text not null default 'active' check (status in ('active', 'inactive')),
  created_at timestamptz not null default now()
);

create table attendance (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references workers(id) on delete cascade,
  attendance_date date not null,
  status text not null check (status in ('present', 'absent', 'half_day')),
  notes text,
  created_at timestamptz not null default now(),
  unique (worker_id, attendance_date)
);

create table documents (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  name text not null,
  category text not null default 'other' check (category in
    ('drawing', 'specification', 'contract', 'permit', 'report', 'photo', 'correspondence', 'safety', 'other')),
  version integer not null default 1,
  file_path text not null,
  file_size integer,
  mime_type text,
  notes text,
  uploaded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table vendors (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  name text not null,
  contact_person text,
  phone text,
  email text,
  address text,
  gst_number text,
  category text,
  notes text,
  created_at timestamptz not null default now()
);

create table purchase_requisitions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  item_name text not null,
  quantity numeric(14, 3) not null,
  unit text not null,
  estimated_cost numeric(14, 2),
  urgency text not null default 'normal' check (urgency in ('low', 'normal', 'high', 'critical')),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'ordered')),
  requested_by uuid not null references auth.users(id),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  notes text,
  created_at timestamptz not null default now()
);

create table rfqs (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  requisition_id uuid references purchase_requisitions(id) on delete set null,
  title text not null,
  deadline date,
  status text not null default 'open' check (status in ('open', 'closed', 'awarded')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table quotes (
  id uuid primary key default gen_random_uuid(),
  rfq_id uuid not null references rfqs(id) on delete cascade,
  vendor_id uuid not null references vendors(id) on delete cascade,
  total_amount numeric(14, 2) not null,
  delivery_days integer,
  payment_terms text,
  notes text,
  status text not null default 'received' check (status in ('received', 'accepted', 'rejected')),
  created_at timestamptz not null default now()
);

create table purchase_orders (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  quote_id uuid references quotes(id) on delete set null,
  vendor_id uuid not null references vendors(id) on delete cascade,
  po_number text,
  total_amount numeric(14, 2),
  delivery_date date,
  status text not null default 'issued' check (status in ('issued', 'acknowledged', 'delivered', 'cancelled')),
  notes text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table grns (
  id uuid primary key default gen_random_uuid(),
  purchase_order_id uuid not null references purchase_orders(id) on delete cascade,
  received_date date not null,
  item_description text not null,
  ordered_qty numeric(14, 3) not null,
  received_qty numeric(14, 3) not null,
  unit text not null,
  condition text not null default 'good' check (condition in ('good', 'damaged', 'partial')),
  received_by uuid not null references auth.users(id),
  notes text,
  created_at timestamptz not null default now()
);

create table equipment (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  name text not null,
  equipment_type text,
  model text,
  registration_number text,
  status text not null default 'available' check (status in ('available', 'in_use', 'maintenance', 'breakdown')),
  daily_rate numeric(10, 2),
  notes text,
  created_at timestamptz not null default now()
);

create table equipment_logs (
  id uuid primary key default gen_random_uuid(),
  equipment_id uuid not null references equipment(id) on delete cascade,
  log_date date not null,
  log_type text not null check (log_type in ('usage', 'maintenance', 'repair', 'fuel', 'inspection')),
  hours_used numeric(6, 2),
  description text,
  cost numeric(14, 2),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table inspections (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  title text not null,
  inspection_type text not null check (inspection_type in
    ('safety', 'quality', 'structural', 'mep', 'environmental', 'final', 'other')),
  status text not null default 'open' check (status in ('open', 'in_progress', 'completed')),
  inspector_id uuid references auth.users(id),
  scheduled_date date,
  completed_date date,
  overall_result text check (overall_result in ('pass', 'fail', 'partial')),
  notes text,
  created_at timestamptz not null default now()
);

create table inspection_items (
  id uuid primary key default gen_random_uuid(),
  inspection_id uuid not null references inspections(id) on delete cascade,
  item_description text not null,
  status text not null default 'pending' check (status in ('pending', 'pass', 'fail', 'na')),
  notes text,
  sort_order integer not null default 0
);

create table inspection_photos (
  id uuid primary key default gen_random_uuid(),
  inspection_id uuid not null references inspections(id) on delete cascade,
  photo_path text not null,
  caption text,
  uploaded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

-- --- Mobile-only entities (fieldos_mobile/lib/data/tables.dart) --- these
-- have no desktop backend equivalent today; kept company-scoped
-- (subcontractors, like vendors) or project-scoped (work_orders, approvals)
-- to match the Drift schema's own choices.

create table subcontractors (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  name text not null,
  contact_phone text,
  trade text,
  created_at timestamptz not null default now()
);

create table work_orders (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  subcontractor_id uuid not null references subcontractors(id) on delete cascade,
  description text not null,
  agreed_amount numeric(14, 2),
  billed_amount numeric(14, 2) not null default 0,
  status text not null default 'active' check (status in ('active', 'completed', 'cancelled')),
  created_at timestamptz not null default now()
);

create table approvals (
  id uuid primary key default gen_random_uuid(),
  project_id uuid references projects(id) on delete cascade,
  entity_type text not null,
  entity_id uuid not null,
  requested_by uuid not null references auth.users(id),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  approver_id uuid references auth.users(id),
  decision_note text,
  decided_at timestamptz,
  created_at timestamptz not null default now()
);

-- ===========================================================================
-- PART 2: RLS HELPER FUNCTIONS (tables must exist first)
-- ===========================================================================

-- security definer: bypasses RLS on company_members/project_members
-- themselves when evaluating these, avoiding policy recursion. The (select
-- ...) wrapper at call sites caches auth.uid() once per query instead of
-- once per row -- see docs/SUPABASE_SYNC_RESEARCH.md.

create or replace function is_company_member(p_company_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from company_members
    where company_id = p_company_id
      and user_id = (select auth.uid())
  );
$$;

create or replace function company_role(p_company_id uuid)
returns text
language sql
security definer
set search_path = public
stable
as $$
  select role from company_members
  where company_id = p_company_id
    and user_id = (select auth.uid())
  limit 1;
$$;

-- Mirrors fieldos/permissions.py's require_project_access exactly: company
-- owner gets automatic access to every project in their company, OR an
-- explicit project_members row.
create or replace function has_project_access(p_project_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from projects p
    where p.id = p_project_id
      and (
        company_role(p.company_id) = 'owner'
        or exists (
          select 1 from project_members pm
          where pm.project_id = p_project_id
            and pm.user_id = (select auth.uid())
        )
      )
  );
$$;

-- Mirrors fieldos/permissions.py's require_company_role's common allowed-set
-- for mutations: owner or project_manager.
create or replace function is_company_owner_or_pm(p_company_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select company_role(p_company_id) in ('owner', 'project_manager');
$$;

-- Project-level owner/PM check, resolving the project's company (mirrors
-- the pattern equipment DELETE, worker roster mutations, PO creation etc.
-- use in fieldos/routers/*.py: require_company_role({OWNER,PM}) on the
-- project's own company).
create or replace function is_project_owner_or_pm(p_project_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from projects p
    where p.id = p_project_id
      and is_company_owner_or_pm(p.company_id)
  );
$$;

-- ===========================================================================
-- PART 3: RLS -- ENABLE + POLICIES
-- ===========================================================================

alter table companies enable row level security;
alter table company_members enable row level security;
alter table projects enable row level security;
alter table project_members enable row level security;
alter table tasks enable row level security;
alter table dpr_entries enable row level security;
alter table dpr_photos enable row level security;
alter table issues enable row level security;
alter table estimations enable row level security;
alter table cost_heads enable row level security;
alter table measurement_entries enable row level security;
alter table steel_entries enable row level security;
alter table material_entries enable row level security;
alter table material_photos enable row level security;
alter table workers enable row level security;
alter table attendance enable row level security;
alter table documents enable row level security;
alter table vendors enable row level security;
alter table purchase_requisitions enable row level security;
alter table rfqs enable row level security;
alter table quotes enable row level security;
alter table purchase_orders enable row level security;
alter table grns enable row level security;
alter table equipment enable row level security;
alter table equipment_logs enable row level security;
alter table inspections enable row level security;
alter table inspection_items enable row level security;
alter table inspection_photos enable row level security;
alter table subcontractors enable row level security;
alter table work_orders enable row level security;
alter table approvals enable row level security;

-- RLS restricts which ROWS a role can see, but Postgres checks table-level
-- privileges first -- without these GRANTs, `authenticated` has zero access
-- to any table regardless of how correct the RLS policies below are (this
-- was caught by actually running rls_verification_test.sql, not assumed).
-- `anon` gets nothing at all -- every table here requires a real session.
--
-- `service_role` needs its own explicit grant too, even though it bypasses
-- RLS policy evaluation (via Supabase's bypassrls role attribute) -- RLS
-- and table-level GRANTs are two separate mechanisms, and a newly created
-- table's default privileges don't extend to service_role automatically.
-- Caught by sync_engine_test.dart's own setup code (which legitimately
-- uses the service-role client to seed test companies/users, bypassing RLS
-- the same way the app's own admin tooling would) failing with "permission
-- denied for table companies" on the very first insert.
do $$
declare
  t text;
begin
  for t in
    select unnest(array[
      'companies', 'company_members', 'projects', 'project_members', 'tasks',
      'dpr_entries', 'dpr_photos', 'issues', 'estimations', 'cost_heads',
      'measurement_entries', 'steel_entries', 'material_entries', 'material_photos',
      'workers', 'attendance', 'documents', 'vendors', 'purchase_requisitions',
      'rfqs', 'quotes', 'purchase_orders', 'grns', 'equipment', 'equipment_logs',
      'inspections', 'inspection_items', 'inspection_photos', 'subcontractors',
      'work_orders', 'approvals'
    ])
  loop
    execute format('revoke all on table %I from anon, authenticated;', t);
    execute format('grant select, insert, update, delete on table %I to authenticated;', t);
    execute format('grant all on table %I to service_role;', t);
  end loop;
end $$;

-- companies: any authenticated user can create one (becomes owner via a
-- company_members insert done in the same transaction, app-side); members
-- can read their own company.
create policy "members can read their company" on companies for select
  to authenticated using ((select is_company_member(id)));
create policy "authenticated users can create a company" on companies for insert
  to authenticated with check (true);

-- company_members: members can see their own company's roster.
create policy "members can read company roster" on company_members for select
  to authenticated using ((select is_company_member(company_id)));
create policy "owner/pm can add members" on company_members for insert
  to authenticated with check ((select is_company_owner_or_pm(company_id)));

-- projects: fieldos/routers/projects.py -- create requires owner/PM; list/
-- read requires project access (owner-override included).
create policy "project members can read their project" on projects for select
  to authenticated using ((select has_project_access(id)));
create policy "owner/pm can create projects" on projects for insert
  to authenticated with check ((select is_company_owner_or_pm(company_id)));

create policy "project members can read project roster" on project_members for select
  to authenticated using ((select has_project_access(project_id)));
create policy "owner/pm can add project members" on project_members for insert
  to authenticated with check ((select is_project_owner_or_pm(project_id)));

-- tasks: create = owner/PM; read/update = project membership.
create policy "project members can read tasks" on tasks for select
  to authenticated using ((select has_project_access(project_id)));
create policy "owner/pm can create tasks" on tasks for insert
  to authenticated with check ((select is_project_owner_or_pm(project_id)));
create policy "project members can update tasks" on tasks for update
  to authenticated using ((select has_project_access(project_id)));

-- dpr_entries / dpr_photos: project membership for all operations.
create policy "project members can read dpr" on dpr_entries for select
  to authenticated using ((select has_project_access(project_id)));
create policy "project members can create dpr" on dpr_entries for insert
  to authenticated with check ((select has_project_access(project_id)));
create policy "project members can read dpr photos" on dpr_photos for select
  to authenticated using ((select has_project_access(
    (select project_id from dpr_entries where id = dpr_entry_id))));
create policy "project members can add dpr photos" on dpr_photos for insert
  to authenticated with check ((select has_project_access(
    (select project_id from dpr_entries where id = dpr_entry_id))));

-- issues: create/read = project membership; resolve (update) = owner/PM
-- (fieldos/routers/issues.py's PATCH .../resolve requires {OWNER,PM}).
create policy "project members can read issues" on issues for select
  to authenticated using ((select has_project_access(project_id)));
create policy "project members can create issues" on issues for insert
  to authenticated with check ((select has_project_access(project_id)));
create policy "owner/pm can resolve issues" on issues for update
  to authenticated using ((select is_project_owner_or_pm(project_id)));

-- estimation tree: project membership for all operations (matches
-- fieldos/routers/estimation.py -- no role escalation beyond membership).
create policy "project members can read estimations" on estimations for select
  to authenticated using ((select has_project_access(project_id)));
create policy "project members can create estimations" on estimations for insert
  to authenticated with check ((select has_project_access(project_id)));

create policy "project members can read cost heads" on cost_heads for select
  to authenticated using ((select has_project_access(
    (select project_id from estimations where id = estimation_id))));
create policy "project members can create cost heads" on cost_heads for insert
  to authenticated with check ((select has_project_access(
    (select project_id from estimations where id = estimation_id))));

create policy "project members can read measurements" on measurement_entries for select
  to authenticated using ((select has_project_access(
    (select project_id from estimations e join cost_heads c on c.estimation_id = e.id where c.id = cost_head_id))));
create policy "project members can create measurements" on measurement_entries for insert
  to authenticated with check ((select has_project_access(
    (select project_id from estimations e join cost_heads c on c.estimation_id = e.id where c.id = cost_head_id))));

create policy "project members can read steel entries" on steel_entries for select
  to authenticated using ((select has_project_access(
    (select project_id from estimations e join cost_heads c on c.estimation_id = e.id where c.id = cost_head_id))));
create policy "project members can create steel entries" on steel_entries for insert
  to authenticated with check ((select has_project_access(
    (select project_id from estimations e join cost_heads c on c.estimation_id = e.id where c.id = cost_head_id))));

-- materials: project membership for all operations.
create policy "project members can read materials" on material_entries for select
  to authenticated using ((select has_project_access(project_id)));
create policy "project members can create materials" on material_entries for insert
  to authenticated with check ((select has_project_access(project_id)));
create policy "project members can read material photos" on material_photos for select
  to authenticated using ((select has_project_access(
    (select project_id from material_entries where id = material_entry_id))));
create policy "project members can add material photos" on material_photos for insert
  to authenticated with check ((select has_project_access(
    (select project_id from material_entries where id = material_entry_id))));

-- workers: roster mutations (insert/update) = owner/PM (fieldos/routers/
-- workers.py); read + attendance marking = project membership.
create policy "project members can read workers" on workers for select
  to authenticated using ((select has_project_access(project_id)));
create policy "owner/pm can create workers" on workers for insert
  to authenticated with check ((select is_project_owner_or_pm(project_id)));
create policy "owner/pm can update workers" on workers for update
  to authenticated using ((select is_project_owner_or_pm(project_id)));

create policy "project members can read attendance" on attendance for select
  to authenticated using ((select has_project_access(
    (select project_id from workers where id = worker_id))));
create policy "project members can mark attendance" on attendance for insert
  to authenticated with check ((select has_project_access(
    (select project_id from workers where id = worker_id))));
create policy "project members can update attendance" on attendance for update
  to authenticated using ((select has_project_access(
    (select project_id from workers where id = worker_id))));

-- documents: project membership for all operations.
create policy "project members can read documents" on documents for select
  to authenticated using ((select has_project_access(project_id)));
create policy "project members can upload documents" on documents for insert
  to authenticated with check ((select has_project_access(project_id)));

-- vendors: company-scoped (shared across a company's projects). verify
-- against fieldos/routers/procurement.py -- create was recalled as
-- {OWNER,PM}, list as any company member; defaulting list to plain
-- membership, which is the safe (never-more-open) default either way.
create policy "company members can read vendors" on vendors for select
  to authenticated using ((select is_company_member(company_id)));
create policy "owner/pm can create vendors" on vendors for insert
  to authenticated with check ((select is_company_owner_or_pm(company_id)));

-- procurement chain: project membership for create/read; requisition
-- approval = owner/PM (fieldos/routers/procurement.py's PATCH .../approve).
create policy "project members can read requisitions" on purchase_requisitions for select
  to authenticated using ((select has_project_access(project_id)));
create policy "project members can create requisitions" on purchase_requisitions for insert
  to authenticated with check ((select has_project_access(project_id)));
create policy "owner/pm can approve requisitions" on purchase_requisitions for update
  to authenticated using ((select is_project_owner_or_pm(project_id)));

create policy "project members can read rfqs" on rfqs for select
  to authenticated using ((select has_project_access(project_id)));
create policy "project members can create rfqs" on rfqs for insert
  to authenticated with check ((select has_project_access(project_id)));

-- quotes: no direct project_id -- resolve via rfq. verify against
-- fieldos/routers/procurement.py for the exact create-role requirement;
-- defaulting to project membership (the safe default).
create policy "project members can read quotes" on quotes for select
  to authenticated using ((select has_project_access(
    (select project_id from rfqs where id = rfq_id))));
create policy "project members can create quotes" on quotes for insert
  to authenticated with check ((select has_project_access(
    (select project_id from rfqs where id = rfq_id))));

-- purchase_orders: create = owner/PM (recalled from fieldos/routers/
-- procurement.py as a deliberately-stricter mutation, same tier as
-- requisition approval).
create policy "project members can read purchase orders" on purchase_orders for select
  to authenticated using ((select has_project_access(project_id)));
create policy "owner/pm can create purchase orders" on purchase_orders for insert
  to authenticated with check ((select is_project_owner_or_pm(project_id)));

create policy "project members can read grns" on grns for select
  to authenticated using ((select has_project_access(
    (select project_id from purchase_orders where id = purchase_order_id))));
create policy "project members can create grns" on grns for insert
  to authenticated with check ((select has_project_access(
    (select project_id from purchase_orders where id = purchase_order_id))));

-- equipment: create/read/update = project membership; delete = owner/PM
-- (fieldos/routers/equipment.py's DELETE requires {OWNER,PM}).
create policy "project members can read equipment" on equipment for select
  to authenticated using ((select has_project_access(project_id)));
create policy "project members can create equipment" on equipment for insert
  to authenticated with check ((select has_project_access(project_id)));
create policy "project members can update equipment" on equipment for update
  to authenticated using ((select has_project_access(project_id)));
create policy "owner/pm can delete equipment" on equipment for delete
  to authenticated using ((select is_project_owner_or_pm(project_id)));

create policy "project members can read equipment logs" on equipment_logs for select
  to authenticated using ((select has_project_access(
    (select project_id from equipment where id = equipment_id))));
create policy "project members can create equipment logs" on equipment_logs for insert
  to authenticated with check ((select has_project_access(
    (select project_id from equipment where id = equipment_id))));

-- inspections: project membership for all operations.
create policy "project members can read inspections" on inspections for select
  to authenticated using ((select has_project_access(project_id)));
create policy "project members can create inspections" on inspections for insert
  to authenticated with check ((select has_project_access(project_id)));
create policy "project members can update inspections" on inspections for update
  to authenticated using ((select has_project_access(project_id)));

create policy "project members can read inspection items" on inspection_items for select
  to authenticated using ((select has_project_access(
    (select project_id from inspections where id = inspection_id))));
create policy "project members can create inspection items" on inspection_items for insert
  to authenticated with check ((select has_project_access(
    (select project_id from inspections where id = inspection_id))));
create policy "project members can update inspection items" on inspection_items for update
  to authenticated using ((select has_project_access(
    (select project_id from inspections where id = inspection_id))));

create policy "project members can read inspection photos" on inspection_photos for select
  to authenticated using ((select has_project_access(
    (select project_id from inspections where id = inspection_id))));
create policy "project members can add inspection photos" on inspection_photos for insert
  to authenticated with check ((select has_project_access(
    (select project_id from inspections where id = inspection_id))));

-- subcontractors: company-scoped, same pattern as vendors.
create policy "company members can read subcontractors" on subcontractors for select
  to authenticated using ((select is_company_member(company_id)));
create policy "owner/pm can create subcontractors" on subcontractors for insert
  to authenticated with check ((select is_company_owner_or_pm(company_id)));

-- work_orders / approvals: project membership (mobile-only entities, no
-- desktop router to cross-check role requirements against -- defaulting to
-- plain membership, the safe default).
create policy "project members can read work orders" on work_orders for select
  to authenticated using ((select has_project_access(project_id)));
create policy "project members can create work orders" on work_orders for insert
  to authenticated with check ((select has_project_access(project_id)));

create policy "project members can read approvals" on approvals for select
  to authenticated using (project_id is null or (select has_project_access(project_id)));
create policy "project members can create approvals" on approvals for insert
  to authenticated with check (project_id is null or (select has_project_access(project_id)));
create policy "project members can decide approvals" on approvals for update
  to authenticated using (project_id is null or (select has_project_access(project_id)));

-- Realtime: the `supabase_realtime` publication that ships with a fresh
-- local stack exists but starts with zero tables in it -- `postgres_changes`
-- subscriptions silently never fire for a table until it's added here,
-- regardless of RLS or client correctness (a genuine, previously-missed gap
-- caught by test/sync_engine_realtime_test.dart's own real Realtime
-- websocket test timing out with no event ever arriving). Add tables here
-- as SyncEngine grows more `subscribeTo*` methods -- currently just the two
-- it actually subscribes to (subscribeToProjectTasks, subscribeToCompanyProjects).
alter publication supabase_realtime add table tasks, projects;
