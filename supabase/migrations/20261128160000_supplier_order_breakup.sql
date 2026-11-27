-- A supplier sees what an order is made of, not only its total.
--
-- supplier_portal() gave an order's number, item, total, delivery date and
-- status. A supplier checking an order against his own quotation could not see
-- the quantity, the rate or the GST it was placed at, so a total was a figure to
-- trust. Each order now also carries quantity, unit, and the rate, GST % and
-- transport of the quote that was accepted for it (this supplier's own, so
-- nothing of another supplier's price is reachable). Null where the order was
-- not made from a quote. The rest of the function is as it was (built from the
-- live definition); older apps ignore the extra keys. Idempotent. Tested in
-- supabase/tests/supplier_order_breakup_test.sql.

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
               'item', (select r.item_name from purchase_requisitions r where r.id = o.requisition_id),
               'quantity', (select r.quantity from purchase_requisitions r where r.id = o.requisition_id),
               'unit', (select r.unit from purchase_requisitions r where r.id = o.requisition_id),
               'rate', (select q.rate from site_supplier_quotes q where q.po_id = o.id and q.vendor_id = o.vendor_id
                         order by q.created_at desc limit 1),
               'gst_pct', (select q.gst_pct from site_supplier_quotes q where q.po_id = o.id and q.vendor_id = o.vendor_id
                            order by q.created_at desc limit 1),
               'transport', (select q.transport from site_supplier_quotes q where q.po_id = o.id and q.vendor_id = o.vendor_id
                              order by q.created_at desc limit 1))
             order by o.created_at desc)
        from purchase_orders o
        join supplier_users su on su.vendor_id = o.vendor_id and su.user_id = auth.uid()
        join projects p on p.id = o.project_id
        join companies c on c.id = p.company_id
       where o.status <> 'cancelled'
         and approval_chain_complete('purchase_order', o.id, o.project_id, o.total_amount, o.created_at)), '[]'::json));
$function$;
