-- Purchase orders and requisitions: who may change what, enforced on the server.
--
-- Until now any member of a site could PATCH any column of a purchase order
-- or a requisition straight through the API (the update policies are
-- has_project_access with no column check, and the approval chain only runs
-- when a PO is inserted). An engineer, or a supplier working with one, could
-- lower a request's estimated cost to slip under an approval limit, mark a
-- request approved by themselves, or rewrite a PO's amount or vendor.
--
-- The phone changes very little on these rows, and always sends the whole row:
--   purchase_orders       status (delivered when received, cancelled) and cost_code_id
--   purchase_requisitions status (ordered when a PO is raised, rejected)
-- So everything else is frozen for people calling the API. Only direct API
-- callers are held to this: the server's own functions (the supplier's "on the
-- way", which runs as the function owner) and the service role are not.
--
-- Also: one live PO per request, so two phones awarding the same request
-- offline cannot both create an order. The second one is parked on the phone
-- with the reason, and is visible in Team & sync.
--
-- Additive and idempotent. Tested in supabase/tests/procurement_guards_test.sql.

create or replace function purchase_orders_update_guard()
returns trigger language plpgsql set search_path = public as $$
begin
  -- SECURITY INVOKER on purpose: current_user is the caller's role. A
  -- definer function (supplier_dispatch) or the service role is not held to
  -- the member rules below.
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;
  if (new.project_id, new.vendor_id, new.requisition_id, new.quote_id, new.po_number,
      new.total_amount, new.created_by, new.created_at)
     is distinct from
     (old.project_id, old.vendor_id, old.requisition_id, old.quote_id, old.po_number,
      old.total_amount, old.created_by, old.created_at) then
    raise exception 'A purchase order''s site, supplier, amount and author cannot be changed. Cancel it and raise a new one.'
      using errcode = '42501';
  end if;
  if old.status = 'cancelled' and new.status is distinct from old.status then
    raise exception 'A cancelled purchase order stays cancelled.' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function purchase_orders_update_guard() from public, anon, authenticated;
drop trigger if exists purchase_orders_update_guard on purchase_orders;
create trigger purchase_orders_update_guard before update on purchase_orders
  for each row execute function purchase_orders_update_guard();

create or replace function purchase_requisitions_update_guard()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;
  if (new.project_id, new.requested_by, new.item_name, new.quantity, new.unit,
      new.estimated_cost, new.urgency, new.created_at)
     is distinct from
     (old.project_id, old.requested_by, old.item_name, old.quantity, old.unit,
      old.estimated_cost, old.urgency, old.created_at) then
    raise exception 'A purchase request cannot be changed after it is raised. Reject it and raise a new one.'
      using errcode = '42501';
  end if;
  -- Approving is for the site's owner or a manager within their limit. The
  -- app never sets 'approved' (its approvals run through the approval
  -- chain), and never sets approved_by / approved_at. Rejecting or ordering
  -- is left open: neither can cause spend that was not approved.
  if (new.status = 'approved' and new.status is distinct from old.status)
     or new.approved_by is distinct from old.approved_by
     or new.approved_at is distinct from old.approved_at then
    if not coalesce(can_approve_on_site(new.project_id, new.estimated_cost), false) then
      raise exception 'Only the site''s owner or a manager, within their limit, approves a purchase request.'
        using errcode = '42501';
    end if;
    if new.approved_by is not null and new.approved_by is distinct from (select auth.uid()) then
      raise exception 'A purchase request is approved as yourself.' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
revoke all on function purchase_requisitions_update_guard() from public, anon, authenticated;
drop trigger if exists purchase_requisitions_update_guard on purchase_requisitions;
create trigger purchase_requisitions_update_guard before update on purchase_requisitions
  for each row execute function purchase_requisitions_update_guard();

create unique index if not exists purchase_orders_one_live_per_request
  on purchase_orders (requisition_id)
  where requisition_id is not null and status <> 'cancelled';
