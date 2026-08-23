-- Mobile's procurement UI lets any project member create a PO from a
-- requisition ("Make PO"), same as requisition creation. Keeping the
-- owner/pm insert gate would make that push match zero rows under RLS
-- while reporting success -- the silent-bug class this schema has been
-- burned by twice (work_orders, requisition updates). Membership is what
-- the actual app flow requires.
drop policy "owner/pm can create purchase orders" on purchase_orders;
create policy "project members can create purchase orders" on purchase_orders for insert
  to authenticated with check ((select has_project_access(project_id)));
