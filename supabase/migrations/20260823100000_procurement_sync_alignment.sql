-- Procurement-chain sync alignment (see fieldos_mobile/lib/sync/sync_mappers.dart).
--
-- 1) purchase_orders.requisition_id: mobile POs carry requestId -> the
--    requisition they were raised from. Postgres only had quote_id (a
--    different entity -- quotes). Without this column a mobile-raised PO
--    would lose its origin link on push; with it both origins round-trip.
alter table purchase_orders add column requisition_id uuid
  references purchase_requisitions(id) on delete set null;

-- 2) Requisition updates: mobile moves pending -> ordered whenever any
--    project member creates a PO from it (procurement_screen's "Make PO").
--    The previous owner/pm-only update policy would let that push match
--    zero rows under RLS while reporting success -- the exact silent-bug
--    class from work_orders. Membership is what this app's actual workflow
--    requires; the CHECK constraint still bounds which statuses exist.
drop policy "owner/pm can approve requisitions" on purchase_requisitions;
create policy "project members can update requisitions" on purchase_requisitions for update
  to authenticated using ((select has_project_access(project_id)));

-- 3) purchase_orders had select + insert but no update policy at all;
--    mobile's "Receive" flow sets issued -> delivered and must push.
create policy "project members can update purchase orders" on purchase_orders for update
  to authenticated using ((select has_project_access(project_id)));

-- 4) Realtime publication: vendors is subscribed live by SyncEngine now;
--    requisitions/POs are added so future subscribeTo* methods don't need
--    their own migration to fire.
alter publication supabase_realtime add table vendors;
alter publication supabase_realtime add table purchase_requisitions;
alter publication supabase_realtime add table purchase_orders;
