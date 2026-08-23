-- vendors had select + insert policies but no update policy. That is the
-- exact gap class that silently swallowed work_orders pushes once already:
-- PostgREST matches zero rows under RLS, reports success, and the value
-- never changes -- undetectable without a test asserting the real synced
-- value. The SupplierDao has no local update path yet; this policy exists so
-- the day one is added (or a desktop-era client updates a vendor), the push
-- is a real write instead of a silent no-op.
--
-- Update is gated to owner/PM, matching the vendors insert tier (create was
-- {OWNER,PM} in fieldos/routers/procurement.py) -- never-more-open.
create policy "owner/pm can update vendors" on vendors for update
  to authenticated using ((select is_company_owner_or_pm(company_id)));
