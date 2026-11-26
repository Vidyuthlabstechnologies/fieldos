-- A supplier sees, and can dispatch against, only purchase orders the builder
-- has approved.
--
-- supplier_portal() listed every PO that was not cancelled, and
-- supplier_dispatch() acknowledged any PO that was not closed, so an order the
-- builder's owner had not yet approved (a PO above an approval rule's amount
-- waits for the owner or a manager) was already visible to the supplier, who
-- could send a truck against it. An order is approved when its approval chain
-- is complete (approval_chain_complete, 20261110900000_approval_rules.sql); an
-- order no rule applies to is complete at once, so ordinary orders are
-- unaffected. A held order simply appears on the supplier's list when it is
-- approved.
--
-- The functions are otherwise exactly as they were. Idempotent.
-- Tested in supabase/tests/supplier_approved_orders_test.sql.

create or replace function public.supplier_portal()
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
       where o.status <> 'cancelled'
         and approval_chain_complete('purchase_order', o.id, o.project_id, o.total_amount, o.created_at)), '[]'::json));
$function$;

create or replace function public.supplier_dispatch(p_po_id uuid, p_vehicle text, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  if not exists (select 1 from purchase_orders o
                  where o.id = p_po_id
                    and approval_chain_complete('purchase_order', o.id, o.project_id, o.total_amount, o.created_at)) then
    raise exception 'this order is waiting for the builder''s approval' using errcode = '22023';
  end if;
  update purchase_orders
     set status = 'acknowledged',
         dispatched_on = coalesce(dispatched_on, now()),
         dispatch_vehicle = left(nullif(trim(p_vehicle), ''), 40),
         supplier_note = left(nullif(trim(p_note), ''), 300)
   where id = p_po_id;
end $function$;
