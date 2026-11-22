-- Security review 2026-11-21 (end-to-end pass over RLS, storage, functions).
--
-- 1. Files in the documents bucket. Any member of a site could overwrite or
--    delete any file on it: someone else's bill photo, delivery slip or
--    attendance selfie could be swapped for another picture or removed.
--    Now only the person who uploaded a file, or the site's owner or
--    project manager, replaces or deletes it. Re-sending your own upload
--    (the phone's retry after a lost reply) still works.
--
-- 2. Claim photos. A subcontractor on a site could list and download every
--    claim photo on it, including other subcontractor firms' claims (their
--    bills and quantities). Now a subcontractor reads only the photos they
--    uploaded and the photos on claims of their own work orders. They can
--    also re-send their own upload, which used to fail ("already exists")
--    and left the claim photo stuck in the phone's outbox.
--
-- 3. Links to another company's records. A row on your own site could point
--    at another company's record: a work order at another company's
--    subcontractor, a purchase order at another company's supplier (which
--    then showed up in that supplier's portal and could be acted on), a
--    variation at another site's work order or claim, and a few more. Each
--    such link now has to stay on the same site (or the same company, for
--    suppliers and subcontractors). Only new links are checked: rows already
--    stored are not touched, and an update that leaves the link alone passes.
--
-- 4. join_portal() and join_as_subcontractor() take the same per-account lock
--    as join_company(), so a burst of parallel guesses cannot all pass the
--    10-an-hour count before any of them is recorded.

-- --- 1 and 2: storage ---------------------------------------------------------

drop policy if exists "project members can replace document files" on storage.objects;
create policy "project members can replace document files" on storage.objects for update
  to authenticated
  using (bucket_id = 'documents'
    and has_project_access(((storage.foldername(name))[1])::uuid)
    and (owner_id = (select auth.uid())::text
         or (select is_project_owner_or_pm(((storage.foldername(name))[1])::uuid))))
  with check (bucket_id = 'documents'
    and has_project_access(((storage.foldername(name))[1])::uuid));

drop policy if exists "project members can delete document files" on storage.objects;
create policy "project members can delete document files" on storage.objects for delete
  to authenticated
  using (bucket_id = 'documents'
    and has_project_access(((storage.foldername(name))[1])::uuid)
    and (owner_id = (select auth.uid())::text
         or (select is_project_owner_or_pm(((storage.foldername(name))[1])::uuid))));

drop policy if exists "subcontractors read claim photos" on storage.objects;
create policy "subcontractors read claim photos" on storage.objects for select
  to authenticated using (
    bucket_id = 'documents' and (storage.foldername(name))[2] = 'claims'
    and (select is_subcontractor_on_project(((storage.foldername(name))[1])::uuid))
    and (owner_id = (select auth.uid())::text
         or exists (select 1 from public.commercial_attachments ca
                     where ca.file_path = objects.name
                       and ca.parent_kind = 'claim'
                       and public.commercial_parent_visible(ca.parent_kind, ca.parent_id))));

drop policy if exists "subcontractors re-send their claim photos" on storage.objects;
create policy "subcontractors re-send their claim photos" on storage.objects for update
  to authenticated
  using (bucket_id = 'documents' and (storage.foldername(name))[2] = 'claims'
    and owner_id = (select auth.uid())::text
    and (select is_subcontractor_on_project(((storage.foldername(name))[1])::uuid)))
  with check (bucket_id = 'documents' and (storage.foldername(name))[2] = 'claims'
    and (select is_subcontractor_on_project(((storage.foldername(name))[1])::uuid)));

create index if not exists commercial_attachments_file_path_idx on commercial_attachments (file_path);

-- --- 3: links stay on the same site or company ---------------------------------

-- Trigger arguments: the link column, the table it points at, and the scope:
--   site         the linked row is on the same site (its project_id)
--   company      the linked row belongs to this site's company (its company_id)
--   row_company  the linked row belongs to this row's own company_id
create or replace function same_owner_link()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  col constant text := tg_argv[0];
  target constant text := tg_argv[1];
  scope constant text := tg_argv[2];
  ref uuid := (to_jsonb(new) ->> col)::uuid;
  ok boolean;
begin
  if ref is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and ref is not distinct from (to_jsonb(old) ->> col)::uuid
     and (to_jsonb(new) -> 'project_id') is not distinct from (to_jsonb(old) -> 'project_id')
     and (to_jsonb(new) -> 'company_id') is not distinct from (to_jsonb(old) -> 'company_id') then
    return new;
  end if;
  if scope = 'site' then
    execute format('select exists (select 1 from %I x where x.id = $1 and x.project_id = $2)', target)
      into ok using ref, (to_jsonb(new) ->> 'project_id')::uuid;
  elsif scope = 'company' then
    execute format('select exists (select 1 from %I x join projects p on p.company_id = x.company_id
                                    where x.id = $1 and p.id = $2)', target)
      into ok using ref, (to_jsonb(new) ->> 'project_id')::uuid;
  elsif scope = 'row_company' then
    execute format('select exists (select 1 from %I x where x.id = $1 and x.company_id = $2)', target)
      into ok using ref, (to_jsonb(new) ->> 'company_id')::uuid;
  else
    raise exception 'same_owner_link: unknown scope %', scope;
  end if;
  if not ok then
    raise exception '% points at a record of another %', col,
      case scope when 'site' then 'site' else 'company' end using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function same_owner_link() from public, anon, authenticated;

do $$
declare
  l record;
begin
  for l in select * from (values
    ('issues',                 'dpr_entry_id',     'dpr_entries',           'site'),
    ('rfqs',                   'requisition_id',   'purchase_requisitions', 'site'),
    ('purchase_orders',        'requisition_id',   'purchase_requisitions', 'site'),
    ('purchase_orders',        'cost_code_id',     'cost_codes',            'site'),
    ('purchase_orders',        'vendor_id',        'vendors',               'company'),
    ('work_orders',            'cost_code_id',     'cost_codes',            'site'),
    ('work_orders',            'subcontractor_id', 'subcontractors',        'company'),
    ('site_attendance',        'worker_id',        'workers',               'site'),
    ('site_attendance_marks',  'worker_id',        'workers',               'site'),
    ('site_expenses',          'worker_id',        'workers',               'site'),
    ('site_expenses',          'cost_code_id',     'cost_codes',            'site'),
    ('variations',             'work_order_id',    'work_orders',           'site'),
    ('variations',             'source_claim_id',  'work_claims',           'site'),
    ('variations',             'cost_code_id',     'cost_codes',            'site'),
    ('site_handover_checks',   'unit_id',          'site_handover_units',   'site'),
    ('site_hold_points',       'unit_id',          'site_handover_units',   'site'),
    ('site_defects',           'unit_id',          'site_handover_units',   'site'),
    ('site_defects',           'subcontractor_id', 'subcontractors',        'company'),
    ('site_supplier_invoices', 'po_id',            'purchase_orders',       'site'),
    ('site_supplier_invoices', 'supplier_id',      'vendors',               'company'),
    ('crm_leads',              'project_id',       'projects',              'row_company')
  ) as t(tbl, col, target, scope)
  loop
    -- Skip a pair this database doesn't have (an older schema), rather than fail.
    continue when not exists (select 1 from information_schema.columns
                               where table_schema = 'public' and table_name = l.tbl and column_name = l.col);
    execute format('drop trigger if exists %I on %I', l.tbl || '_' || l.col || '_same_owner', l.tbl);
    execute format('create trigger %I before insert or update on %I for each row
                    execute function same_owner_link(%L, %L, %L)',
                   l.tbl || '_' || l.col || '_same_owner', l.tbl, l.col, l.target, l.scope);
  end loop;
end $$;

-- quotes has no project_id: its supplier belongs to the company of its RFQ's site.
create or replace function quotes_same_company_vendor()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.vendor_id is not null and (tg_op = 'INSERT' or new.vendor_id is distinct from old.vendor_id
                                    or new.rfq_id is distinct from old.rfq_id)
     and not exists (select 1 from rfqs r join projects p on p.id = r.project_id
                       join vendors v on v.company_id = p.company_id
                      where r.id = new.rfq_id and v.id = new.vendor_id) then
    raise exception 'vendor_id points at a record of another company' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function quotes_same_company_vendor() from public, anon, authenticated;
drop trigger if exists quotes_vendor_id_same_owner on quotes;
create trigger quotes_vendor_id_same_owner before insert or update on quotes
  for each row execute function quotes_same_company_vendor();

-- --- 4: one portal join at a time per account -----------------------------------

create or replace function join_portal(p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^0-9A-Za-z]', '', 'g'));
  v_vendor vendors%rowtype;
  v_project projects%rowtype;
  v_company companies%rowtype;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('join_company:' || v_uid::text, 0));
  if (select count(*) from join_attempts where user_id = v_uid and attempted_at > now() - interval '1 hour') >= 10 then
    return json_build_object('error', 'too_many_attempts');
  end if;
  select v.* into v_vendor from vendors v join supplier_codes c on c.vendor_id = v.id where c.code = v_code;
  if found then
    select * into v_company from companies where id = v_vendor.company_id;
    insert into supplier_users (vendor_id, user_id) values (v_vendor.id, v_uid) on conflict do nothing;
    return json_build_object('kind', 'supplier', 'id', v_vendor.id, 'name', v_vendor.name,
                             'company_id', v_company.id, 'company_name', v_company.name);
  end if;
  select p.* into v_project from projects p join client_codes c on c.project_id = p.id where c.code = v_code;
  if found then
    select * into v_company from companies where id = v_project.company_id;
    insert into client_users (project_id, user_id) values (v_project.id, v_uid) on conflict do nothing;
    return json_build_object('kind', 'client', 'id', v_project.id, 'name', v_project.name,
                             'company_id', v_company.id, 'company_name', v_company.name);
  end if;
  insert into join_attempts (user_id) values (v_uid);
  return json_build_object('error', 'invalid_join_code');
end $$;

create or replace function join_as_subcontractor(p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^0-9A-Za-z]', '', 'g'));
  v_sub subcontractors%rowtype;
  v_company companies%rowtype;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('join_company:' || v_uid::text, 0));
  if (select count(*) from join_attempts
      where user_id = v_uid and attempted_at > now() - interval '1 hour') >= 10 then
    return json_build_object('error', 'too_many_attempts');
  end if;
  select s.* into v_sub from subcontractors s join subcontractor_codes c on c.subcontractor_id = s.id
   where c.code = v_code;
  if not found then
    insert into join_attempts (user_id) values (v_uid);
    return json_build_object('error', 'invalid_join_code');
  end if;
  select * into v_company from companies where id = v_sub.company_id;
  insert into subcontractor_users (subcontractor_id, user_id) values (v_sub.id, v_uid)
  on conflict do nothing;
  return json_build_object('subcontractor_id', v_sub.id, 'subcontractor_name', v_sub.name,
                           'company_id', v_company.id, 'company_name', v_company.name);
end $$;

revoke all on function join_portal(text), join_as_subcontractor(text) from public, anon;
grant execute on function join_portal(text), join_as_subcontractor(text) to authenticated;
