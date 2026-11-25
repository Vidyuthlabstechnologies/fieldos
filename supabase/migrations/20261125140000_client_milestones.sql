-- Milestones in the client's view (2026-11-25).
--
-- A stage checklist makes tasks titled "Columns: Casting", "Slab: Curing"
-- and so on. The client sees each stage as one milestone with how many of
-- its steps are done, next to the daily reports they already read. Nothing
-- else is added: no costs, wages or internal approvals.

create or replace function client_portal()
returns json language sql security definer set search_path = public stable as $$
  select coalesce(json_agg(json_build_object(
    'id', p.id, 'name', p.name, 'company_name', c.name, 'status', p.status,
    'start_date', p.start_date, 'end_date', p.end_date,
    'tasks_total', (select count(*) from tasks t where t.project_id = p.id),
    'tasks_done', (select count(*) from tasks t where t.project_id = p.id and t.status = 'done'),
    'milestones', coalesce((
      select json_agg(json_build_object('name', m.name, 'total', m.total, 'done', m.done) order by m.first_at)
        from (select split_part(t.title, ': ', 1) as name, count(*) as total,
                     count(*) filter (where t.status = 'done') as done, min(t.created_at) as first_at
                from tasks t
               where t.project_id = p.id and position(': ' in t.title) > 0
               group by split_part(t.title, ': ', 1)) m), '[]'::json),
    'updates', coalesce((
      select json_agg(u order by u.entry_date desc) from (
        select d.id, d.entry_date, d.work_summary, d.manpower_count, d.weather,
               coalesce((select json_agg(ph.photo_path) from (
                  select x.photo_path from dpr_photos x where x.dpr_entry_id = d.id order by x.created_at limit 4) ph),
                 '[]'::json) as photos
          from dpr_entries d
         where d.project_id = p.id and d.status = 'confirmed'
         order by d.entry_date desc limit 20) u), '[]'::json),
    'bills', coalesce((
      select json_agg(json_build_object('number', b.bill_number, 'date', b.bill_date, 'kind', b.kind,
                                        'amount', b.net_payable, 'status', b.status) order by b.bill_date desc)
        from site_client_bills b where b.project_id = p.id), '[]'::json),
    'payments', coalesce((
      select json_agg(json_build_object('date', r.received_on, 'amount', r.amount, 'mode', r.mode)
                      order by r.received_on desc)
        from site_payments_received r where r.project_id = p.id), '[]'::json)
  ) order by p.name), '[]'::json)
  from client_users cu join projects p on p.id = cu.project_id join companies c on c.id = p.company_id
  where cu.user_id = auth.uid();
$$;
