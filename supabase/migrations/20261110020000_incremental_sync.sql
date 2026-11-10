-- Incremental pull with deletes (audit P1, 2026-11-10).
--
-- Every refresh used to page through every visible row of ~30 tables, so
-- sync got slower as a site's history grew, and a row deleted on the
-- server (or no longer shared) stayed on other phones forever. Now every
-- insert, update and delete of a synced table appends one line to
-- sync_changes. A phone keeps the last sequence number it applied and asks
-- only for newer lines: changed rows are fetched by id, deleted ones are
-- removed locally. Row level security on sync_changes mirrors the tables'
-- own scope, so a phone only learns about rows it could read.
--
-- A full pull is still done the first time, and whenever a phone's cursor
-- is older than the oldest line kept (sync_changes_floor), so lines can be
-- pruned later without breaking anyone.

create table if not exists sync_changes (
  seq bigserial primary key,
  table_name text not null,
  row_id uuid not null,
  op char(1) not null check (op in ('u', 'd')),
  project_id uuid,
  company_id uuid,
  changed_at timestamptz not null default now()
);
create index if not exists sync_changes_project_seq_idx on sync_changes (project_id, seq);
create index if not exists sync_changes_company_seq_idx on sync_changes (company_id, seq);

alter table sync_changes enable row level security;
revoke all on table sync_changes from anon, authenticated;
grant select on table sync_changes to authenticated;
grant usage, select on sequence sync_changes_seq_seq to service_role;

-- Company-wide records (vendors, subcontractors) go to the company. A
-- deleted project's own line is shown to its company too: has_project_access
-- can't answer for a project that no longer exists, and every phone holding
-- a copy needs to drop it.
drop policy if exists "members read their changes" on sync_changes;
create policy "members read their changes" on sync_changes for select
  to authenticated using (
    (project_id is not null and (select has_project_access(project_id)))
    or (company_id is not null and (project_id is null or (table_name = 'projects' and op = 'd'))
        and (select is_company_member(company_id))));

-- security definer: writes the log whatever the caller may write, and
-- looks up parents the caller may not be able to read.
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
    else pid := (r->>'project_id')::uuid;
  end case;
  -- A child deleted by a cascade can't find its (already deleted) parent;
  -- the parent's own line tells phones to drop it with its children.
  if pid is null and cid is null then return null; end if;
  insert into sync_changes (table_name, row_id, op, project_id, company_id)
  values (tg_table_name, (r->>'id')::uuid, case when tg_op = 'DELETE' then 'd' else 'u' end, pid, cid);
  return null;
end $$;
revoke all on function log_sync_change() from public, anon, authenticated;

do $$
declare t text;
begin
  foreach t in array array[
    'projects', 'tasks', 'dpr_entries', 'dpr_photos', 'issues', 'workers', 'equipment', 'equipment_logs',
    'inspections', 'inspection_items', 'subcontractors', 'work_orders', 'approvals', 'vendors', 'estimations',
    'cost_heads', 'measurement_entries', 'steel_entries', 'purchase_requisitions', 'purchase_orders',
    'project_messages', 'site_attendance', 'site_expenses', 'site_material_receipts', 'site_material_usage',
    'site_payments_received', 'site_client_bills', 'site_attendance_marks', 'site_notes', 'documents',
    'expense_attachments'
  ] loop
    execute format('drop trigger if exists %I on %I', t || '_log_sync_change', t);
    execute format('create trigger %I after insert or update or delete on %I for each row execute function log_sync_change()',
                   t || '_log_sync_change', t);
  end loop;
end $$;

-- The oldest line still kept. A phone whose cursor is below it missed
-- lines and does a full pull instead.
create or replace function sync_changes_floor()
returns bigint language sql security definer set search_path = public stable as $$
  select coalesce(min(seq) - 1, pg_sequence_last_value('sync_changes_seq_seq'), 0) from sync_changes;
$$;

-- The newest line so far, for a phone starting a full pull: lines after it
-- are applied on the next incremental pull.
create or replace function sync_changes_head()
returns bigint language sql security definer set search_path = public stable as $$
  select coalesce(max(seq), pg_sequence_last_value('sync_changes_seq_seq'), 0) from sync_changes;
$$;
revoke all on function sync_changes_floor(), sync_changes_head() from public, anon;
grant execute on function sync_changes_floor(), sync_changes_head() to authenticated;
