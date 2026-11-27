-- Indexes on the foreign keys that the app reads and cascades by.
--
-- The customer review (#35) counted 13 `*_id` indexes for 93 tables. A foreign
-- key without an index means that reading a site's rows (`where project_id =
-- ...`, which is every pull), listing a parent's children, and the cascade when
-- a site or a company is deleted all read the whole table. Production is small
-- today, so this costs nothing to add now and is slow to find out about later.
--
-- Adds an index on each foreign key column below that has no index starting
-- with it. Only the columns the app filters or joins by: project and company
-- links, parent links (a purchase order's supplier, a drawing's RFIs), and the
-- three "who recorded it" columns that a row-level-security policy compares
-- with the signed-in user. Other who-did-it columns (created_by and the like)
-- are left out on purpose: an index on each is write cost for a lookup nobody
-- makes. A table or column that is not there is skipped. Idempotent. Guarded by
-- supabase/tests/foreign_key_indexes_test.sql, which fails if a later migration
-- adds a project or company link without one.

do $$
declare
  spec text;
  v_table text;
  v_col text;
  v_attnum int2;
begin
  foreach spec in array array[
    'approvals.project_id',
    'crm_leads.project_id',
    'documents.project_id',
    'dpr_entries.project_id',
    'equipment.project_id',
    'estimations.project_id',
    'inspections.project_id',
    'issues.project_id',
    'material_entries.project_id',
    'payroll_lines.project_id',
    'purchase_orders.project_id',
    'purchase_requisitions.project_id',
    'rfqs.project_id',
    'site_close_settings.project_id',
    'site_handover_checks.project_id',
    'staff_members.project_id',
    'tasks.project_id',
    'work_certifications.project_id',
    'work_orders.project_id',
    'workers.project_id',
    'company_webhook_deliveries.company_id',
    'crm_activities.company_id',
    'staff_advances.company_id',
    'subcontractors.company_id',
    'tool_issues.company_id',
    'vendors.company_id',
    'cost_heads.estimation_id',
    'dpr_photos.dpr_entry_id',
    'equipment_logs.equipment_id',
    'grns.purchase_order_id',
    'inspection_items.inspection_id',
    'inspection_photos.inspection_id',
    'issues.dpr_entry_id',
    'material_photos.material_entry_id',
    'measurement_entries.cost_head_id',
    'purchase_orders.vendor_id',
    'purchase_orders.quote_id',
    'purchase_orders.cost_code_id',
    'quotes.rfq_id',
    'quotes.vendor_id',
    'rfq_invites.vendor_id',
    'rfqs.requisition_id',
    'site_attendance.worker_id',
    'site_attendance_marks.worker_id',
    'site_defects.unit_id',
    'site_defects.subcontractor_id',
    'site_drawing_pins.revision_id',
    'site_expenses.cost_code_id',
    'site_expenses.worker_id',
    'site_hold_points.unit_id',
    'site_liaison_logs.approval_id',
    'site_rfis.drawing_id',
    'site_submittals.drawing_id',
    'site_supplier_invoices.supplier_id',
    'site_supplier_quotes.po_id',
    'site_supplier_quotes.vendor_id',
    'site_work_measurements.cost_head_id',
    'steel_entries.cost_head_id',
    'tools.store_id',
    'variations.cost_code_id',
    'variations.source_claim_id',
    'work_orders.cost_code_id',
    'work_orders.subcontractor_id',
    'work_certifications.variation_id',
    'site_expenses.recorded_by',
    'site_payments_received.recorded_by',
    'site_attendance.recorded_by'
  ] loop
    v_table := split_part(spec, '.', 1);
    v_col := split_part(spec, '.', 2);
    if to_regclass('public.' || v_table) is null then continue; end if;
    select attnum into v_attnum from pg_attribute
     where attrelid = ('public.' || v_table)::regclass and attname = v_col and not attisdropped;
    if v_attnum is null then continue; end if;
    -- Already first in some index (a primary key, a unique constraint, a composite)?
    if exists (select 1 from pg_index i
                where i.indrelid = ('public.' || v_table)::regclass and i.indkey[0] = v_attnum) then
      continue;
    end if;
    execute format('create index if not exists %I on public.%I (%I)', left(v_table || '_' || v_col || '_idx', 63), v_table, v_col);
  end loop;
end $$;
