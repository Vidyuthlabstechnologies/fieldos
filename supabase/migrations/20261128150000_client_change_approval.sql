-- The client approves or declines a change before it is built.
--
-- A homeowner's biggest fear is "extras" that appear on the bill without her
-- ever having agreed. The builder can now send a change to the client with its
-- title, what it is, the client's price and any days it adds; the client
-- approves or declines it in her portal, and the server keeps who decided, when
-- and any note. A decision cannot be changed afterwards (the builder sends a
-- new change instead); the builder can withdraw one that is still waiting.
--
-- The price is the client's price, typed by the builder. Nothing from the
-- builder's own costs is stored here or shown to the client.
--
-- Online by design (the client's answer cannot exist offline), so it is not
-- part of the phone's sync: the table has no grants at all and everything goes
-- through these functions. client_portal() is as it was, built from the live
-- definition, with a 'changes' list added (older apps ignore it).
-- Idempotent. Tested in supabase/tests/client_change_approval_test.sql.

create table if not exists client_change_orders (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  number int not null,
  title text not null check (char_length(title) between 1 and 120),
  description text check (char_length(description) <= 500),
  amount numeric(14, 2) not null check (amount between -1000000000 and 1000000000),
  extra_days int not null default 0 check (extra_days between -365 and 3650),
  status text not null default 'pending' check (status in ('pending', 'approved', 'declined', 'withdrawn')),
  requested_by uuid references auth.users(id) default auth.uid(),
  requested_at timestamptz not null default now(),
  decided_by uuid references auth.users(id),
  decided_at timestamptz,
  decision_note text check (char_length(decision_note) <= 300),
  unique (project_id, number),
  check ((status in ('approved', 'declined')) = (decided_at is not null))
);
alter table client_change_orders enable row level security;
revoke all on table client_change_orders from anon, authenticated;

-- A decision, or a withdrawal, is final. The functions below never touch a
-- row that is not waiting; this is the second lock.
create or replace function client_change_orders_final()
returns trigger language plpgsql set search_path = public as $$
begin
  if old.status <> 'pending' then
    raise exception 'this change has already been %', old.status using errcode = '55000';
  end if;
  if new.project_id <> old.project_id or new.number <> old.number or new.title <> old.title
     or new.amount <> old.amount or new.extra_days <> old.extra_days
     or new.description is distinct from old.description then
    raise exception 'a change that was sent cannot be edited; withdraw it and send a new one' using errcode = '55000';
  end if;
  return new;
end $$;
drop trigger if exists client_change_orders_final on client_change_orders;
create trigger client_change_orders_final before update on client_change_orders
  for each row execute function client_change_orders_final();

create or replace function request_change_approval(
  p_project_id uuid, p_title text, p_description text, p_amount numeric, p_extra_days int default 0)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_number int;
begin
  if not coalesce(is_project_owner_or_pm(p_project_id), false) then
    raise exception 'only the owner or a project manager can send a change to the client' using errcode = '42501';
  end if;
  if coalesce(btrim(p_title), '') = '' then raise exception 'Give the change a title.' using errcode = '23514'; end if;
  if p_amount is null then raise exception 'Enter the price for the client.' using errcode = '23514'; end if;
  perform pg_advisory_xact_lock(hashtextextended('change_approval:' || p_project_id::text, 0));
  if (select count(*) from client_change_orders where project_id = p_project_id and status = 'pending') >= 20 then
    raise exception 'Too many changes are waiting for the client.' using errcode = '23514';
  end if;
  select coalesce(max(number), 0) + 1 into v_number from client_change_orders where project_id = p_project_id;
  insert into client_change_orders (project_id, number, title, description, amount, extra_days)
  values (p_project_id, v_number, btrim(p_title), nullif(btrim(coalesce(p_description, '')), ''), p_amount,
          coalesce(p_extra_days, 0))
  returning id into v_id;
  return v_id;
end $$;

create or replace function change_approvals(p_project_id uuid)
returns json language plpgsql security definer stable set search_path = public as $$
begin
  if not coalesce(is_project_owner_or_pm(p_project_id), false) then
    raise exception 'only the owner or a project manager can see these' using errcode = '42501';
  end if;
  return coalesce((
    select json_agg(json_build_object(
             'id', o.id, 'number', o.number, 'title', o.title, 'description', o.description, 'amount', o.amount,
             'extra_days', o.extra_days, 'status', o.status, 'requested_on', o.requested_at,
             'decided_on', o.decided_at, 'note', o.decision_note) order by o.number desc)
      from client_change_orders o where o.project_id = p_project_id), '[]'::json);
end $$;

create or replace function withdraw_change_approval(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v client_change_orders%rowtype;
begin
  select * into v from client_change_orders where id = p_id for update;
  if not found or not coalesce(is_project_owner_or_pm(v.project_id), false) then
    raise exception 'only the owner or a project manager can withdraw a change' using errcode = '42501';
  end if;
  if v.status <> 'pending' then
    raise exception 'this change has already been %', v.status using errcode = '55000';
  end if;
  update client_change_orders set status = 'withdrawn' where id = p_id;
end $$;

create or replace function decide_change_approval(p_id uuid, p_approve boolean, p_note text default null)
returns json language plpgsql security definer set search_path = public as $$
declare v client_change_orders%rowtype;
begin
  if p_approve is null then raise exception 'approve or decline' using errcode = '22023'; end if;
  select * into v from client_change_orders where id = p_id for update;
  if not found or not coalesce(is_client_on_project(v.project_id), false) or v.status = 'withdrawn' then
    raise exception 'that change is not yours to decide' using errcode = '42501';
  end if;
  if v.status <> 'pending' then
    raise exception 'this change has already been %', v.status using errcode = '55000';
  end if;
  update client_change_orders
     set status = case when p_approve then 'approved' else 'declined' end,
         decided_by = auth.uid(), decided_at = now(),
         decision_note = nullif(left(btrim(coalesce(p_note, '')), 300), '')
   where id = p_id
  returning * into v;
  return json_build_object('id', v.id, 'status', v.status, 'decided_on', v.decided_at);
end $$;

revoke all on function request_change_approval(uuid, text, text, numeric, int), change_approvals(uuid),
  withdraw_change_approval(uuid), decide_change_approval(uuid, boolean, text) from public, anon;
grant execute on function request_change_approval(uuid, text, text, numeric, int), change_approvals(uuid),
  withdraw_change_approval(uuid), decide_change_approval(uuid, boolean, text) to authenticated;

create or replace function public.client_portal()
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
                                        'amount', b.net_payable, 'status', b.status,
                                        'gross', b.gross, 'gst_rate', b.gst_rate, 'retention_pct', b.retention_pct,
                                        'tds_pct', b.tds_pct) order by b.bill_date desc)
        from site_client_bills b where b.project_id = p.id), '[]'::json),
    'changes', coalesce((
      select json_agg(json_build_object(
               'id', o.id, 'number', o.number, 'title', o.title, 'description', o.description,
               'amount', o.amount, 'extra_days', o.extra_days, 'status', o.status,
               'requested_on', o.requested_at, 'decided_on', o.decided_at, 'note', o.decision_note)
             order by o.number desc)
        from client_change_orders o where o.project_id = p.id and o.status <> 'withdrawn'), '[]'::json),
    'payments', coalesce((
      select json_agg(json_build_object('date', r.received_on, 'amount', r.amount, 'mode', r.mode)
                      order by r.received_on desc)
        from site_payments_received r where r.project_id = p.id), '[]'::json)
  ) order by p.name), '[]'::json)
  from client_users cu join projects p on p.id = cu.project_id join companies c on c.id = p.company_id
  where cu.user_id = auth.uid();
$function$;
