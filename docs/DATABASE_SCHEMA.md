# Database Schema

## Overview

SQLAlchemy 2.0 models, SQLite only (there's no PostgreSQL driver in
`requirements.txt` and no code path that uses one — see `docs/DEPLOYMENT.md`
for why this app is SQLite-only by design). All monetary/quantity fields
use `Decimal` for precision.

Every table below has a real Alembic migration under
`fieldos/alembic/versions/` — as of 21 Aug 2026 that's true for all 33
tables (the 18 newer ones landed in a single migration,
`de346d844641_add_materials_workers_documents_...py`). If you add a new
table to `fieldos/models.py`, generate its migration in the same session —
see `docs/DEVELOPMENT.md`'s Migrations section for the exact commands and a
note about pruning autogenerate's noisy false-positive diffs on unrelated
tables.

## Core Tables

### Users & Auth

```sql
users
  id (PK, UUID)
  username (unique)
  name
  password_hash
  created_at

sessions
  token (PK)
  user_id (FK → users.id)
  created_at
  expires_at

app_settings
  key (PK)
  value
  updated_at
```

### Companies & Projects

```sql
companies
  id (PK, UUID)
  name
  created_at

company_members
  id (PK, UUID)
  company_id (FK → companies.id)
  user_id
  role (owner, project_manager, site_engineer)
  created_at
  UNIQUE(company_id, user_id)

projects
  id (PK, UUID)
  company_id (FK → companies.id)
  name
  client_name
  location_lat, location_lng
  geofence_radius_m
  start_date, end_date
  status (planning, active, completed, on_hold)
  created_at

project_members
  id (PK, UUID)
  project_id (FK → projects.id)
  user_id
  role (owner, project_manager, site_engineer)
  created_at
  UNIQUE(project_id, user_id)
```

### Tasks

```sql
tasks
  id (PK, UUID)
  project_id (FK → projects.id)
  title
  assignee_id
  due_date
  status (todo, in_progress, done, blocked)
  created_at
  updated_at
```

### DPR (Daily Progress Reports)

```sql
dpr_entries
  id (PK, UUID)
  project_id (FK → projects.id)
  created_by
  entry_date
  work_summary
  manpower_count
  weather
  status (draft, confirmed)
  source (manual, voice)
  created_at

dpr_photos
  id (PK, UUID)
  dpr_entry_id (FK → dpr_entries.id)
  photo_url
  caption
  created_at
```

### Issues

```sql
issues
  id (PK, UUID)
  project_id (FK → projects.id)
  dpr_entry_id (FK → dpr_entries.id, nullable)
  description
  severity (low, medium, high, critical)
  status (open, in_progress, resolved, closed)
  created_at
  resolved_at
```

### Estimations / BOQ

```sql
estimations
  id (PK, UUID)
  project_id (FK → projects.id)
  name
  status (draft, active, completed)
  contractor_profit_percent
  created_by
  created_at

cost_heads
  id (PK, UUID)
  estimation_id (FK → estimations.id)
  name
  calculation_type (volume, area, steel_weight, count)
  raw_unit
  billing_unit
  conversion_factor
  rate_per_unit
  sort_order

measurement_entries
  id (PK, UUID)
  cost_head_id (FK → cost_heads.id)
  description
  length, width, depth
  nos
  is_deduction

steel_entries
  id (PK, UUID)
  cost_head_id (FK → cost_heads.id)
  description
  bar_dia_mm
  nos
  length_ft
```

### Materials

```sql
material_entries
  id (PK, UUID)
  project_id (FK → projects.id)
  entry_date
  item_name
  category (cement, sand, aggregate, steel, brick, timber, pipe, electrical, plumbing, paint, other)
  quantity
  unit
  supplier
  cost
  notes
  created_by
  created_at

material_photos
  id (PK, UUID)
  material_entry_id (FK → material_entries.id)
  photo_url
  caption
  created_at
```

### Workers & Attendance

```sql
workers
  id (PK, UUID)
  project_id (FK → projects.id)
  name
  role
  phone
  daily_wage
  status (active, inactive)
  created_at

attendance
  id (PK, UUID)
  worker_id (FK → workers.id)
  attendance_date
  status (present, absent, half_day)
  notes
  created_at
  UNIQUE(worker_id, attendance_date)
```

### Documents

```sql
documents
  id (PK, UUID)
  project_id (FK → projects.id)
  name
  category (drawing, specification, contract, permit, report, photo, correspondence, safety, other)
  version
  file_path
  file_size
  mime_type
  notes
  uploaded_by
  created_at
```

### Procurement

```sql
vendors
  id (PK, UUID)
  company_id (FK → companies.id)
  name
  contact_person
  phone
  email
  address
  gst_number
  category
  notes
  created_at

purchase_requisitions
  id (PK, UUID)
  project_id (FK → projects.id)
  item_name
  quantity
  unit
  estimated_cost
  urgency (low, normal, high, critical)
  status (pending, approved, rejected, ordered)
  requested_by
  approved_by
  approved_at
  notes
  created_at

rfqs
  id (PK, UUID)
  project_id (FK → projects.id)
  requisition_id (FK → purchase_requisitions.id, nullable)
  title
  deadline
  status (open, closed, awarded)
  created_by
  created_at

quotes
  id (PK, UUID)
  rfq_id (FK → rfqs.id)
  vendor_id (FK → vendors.id)
  total_amount
  delivery_days
  payment_terms
  notes
  status (received, accepted, rejected)
  created_at

purchase_orders
  id (PK, UUID)
  project_id (FK → projects.id)
  quote_id (FK → quotes.id, nullable)
  vendor_id (FK → vendors.id)
  po_number
  total_amount
  delivery_date
  status (issued, acknowledged, delivered, cancelled)
  notes
  created_by
  created_at

grns
  id (PK, UUID)
  purchase_order_id (FK → purchase_orders.id)
  received_date
  item_description
  ordered_qty
  received_qty
  unit
  condition (good, damaged, partial)
  received_by
  notes
  created_at
```

### Equipment

```sql
equipment
  id (PK, UUID)
  project_id (FK → projects.id)
  name
  equipment_type
  model
  registration_number
  status (available, in_use, maintenance, breakdown)
  daily_rate
  notes
  created_at

equipment_logs
  id (PK, UUID)
  equipment_id (FK → equipment.id)
  log_date
  log_type (usage, maintenance, repair, fuel, inspection)
  hours_used
  description
  cost
  created_by
  created_at
```

### Inspections

```sql
inspections
  id (PK, UUID)
  project_id (FK → projects.id)
  title
  inspection_type (safety, quality, structural, mep, environmental, final, other)
  status (open, in_progress, completed)
  inspector_id
  scheduled_date
  completed_date
  overall_result (pass, fail, partial)
  notes
  created_at

inspection_items
  id (PK, UUID)
  inspection_id (FK → inspections.id)
  item_description
  status (pending, pass, fail, na)
  notes
  sort_order

inspection_photos
  id (PK, UUID)
  inspection_id (FK → inspections.id)
  photo_url
  caption
  uploaded_by
  created_at
```

### Real-time (WebSocket)

No persistence - in-memory connection manager.

### Billing

```sql
subscription_plans
  id (PK, UUID)
  name
  stripe_price_id
  monthly_price_usd
  max_projects
  max_users_per_project
  features (JSON)
  is_active
  created_at

company_subscriptions
  id (PK, UUID)
  company_id (FK → companies.id, UNIQUE)
  plan_id (FK → subscription_plans.id)
  stripe_customer_id
  stripe_subscription_id
  status (trial, active, past_due, canceled)
  trial_ends_at
  current_period_end
  cancel_at_period_end
  created_at
  updated_at

billing_events
  id (PK, UUID)
  company_id (FK → companies.id)
  event_type
  stripe_event_id
  amount_usd
  currency
  description
  event_metadata (JSON)
  created_at
```

## Indexes

- All FK columns indexed
- Unique constraints on username, company membership, project membership, attendance
- Composite indexes on common query patterns (project_id + date, etc.)

## Migration Notes

- SQLite has no `ALTER COLUMN`/`DROP CONSTRAINT` — Alembic's batch mode
  handles this by recreating the table, which is why autogenerate diffs
  against SQLite can show noisy FK drop/recreate pairs on tables you didn't
  actually change. Review and prune those before committing a migration.
- Decimal columns: use `Numeric(precision, scale)` for money/quantities