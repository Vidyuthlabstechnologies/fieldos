-- Weekly site close and approvals (app schema v15, 2026-11-10).
--
-- 1. site_receipt_attachments: the delivery slip photographed when
--    material arrives. It used to stay on the supervisor's phone (its
--    path was written into the receipt's note), so the manager approving
--    the delivery never saw it. Same shape and rules as
--    expense_attachments; files go to the private `documents` bucket at
--    {projectId}/receipt-slips/{attachmentId}.{ext}.
--
-- 2. site_close_reviews: one row per decision in a site's weekly close
--    (approve, send back, mark fixed, close the week, reopen it). Rows are
--    insert-only: no update or delete grant, so the dated record of who
--    approved or sent back what cannot be rewritten from a phone. Only the
--    owner or a project manager may approve, send back, close or reopen;
--    anyone on the site may say an item sent back to them is fixed.

create table if not exists site_receipt_attachments (
  id uuid primary key,
  receipt_id uuid not null references site_material_receipts(id) on delete cascade,
  file_path text not null check (char_length(file_path) <= 300),
  mime_type text not null check (char_length(mime_type) <= 100),
  uploaded_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists site_receipt_attachments_receipt_idx on site_receipt_attachments (receipt_id);

alter table site_receipt_attachments enable row level security;
revoke all on table site_receipt_attachments from anon, authenticated;
grant select, insert, delete on table site_receipt_attachments to authenticated;

drop policy if exists "project members read delivery slips" on site_receipt_attachments;
create policy "project members read delivery slips" on site_receipt_attachments for select
  to authenticated using ((select has_project_access(
    (select project_id from site_material_receipts where id = receipt_id))));

-- The file must sit under the receipt's own site.
drop policy if exists "project members add delivery slips" on site_receipt_attachments;
create policy "project members add delivery slips" on site_receipt_attachments for insert
  to authenticated with check (
    (select has_project_access((select project_id from site_material_receipts where id = receipt_id)))
    and split_part(file_path, '/', 1) = (select project_id::text from site_material_receipts where id = receipt_id));

drop policy if exists "receiver or owner/PM removes delivery slips" on site_receipt_attachments;
create policy "receiver or owner/PM removes delivery slips" on site_receipt_attachments for delete
  to authenticated using (exists (
    select 1 from site_material_receipts r
     where r.id = receipt_id
       and (select has_project_access(r.project_id))
       and (r.received_by = (select auth.uid()) or (select is_project_owner_or_pm(r.project_id)))));

create table if not exists site_close_reviews (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  week_start date not null check (extract(isodow from week_start) = 1),
  item_kind text not null check (item_kind in ('wages', 'expense', 'receipt', 'attendance', 'week')),
  item_id text not null check (char_length(item_id) between 1 and 160),
  decision text not null check (decision in ('approved', 'sent_back', 'fixed', 'closed', 'reopened')),
  note text check (char_length(note) <= 300),
  fingerprint text check (char_length(fingerprint) <= 200),
  amount numeric(14, 2),
  accepted_qty numeric(14, 3) check (accepted_qty is null or accepted_qty >= 0),
  decided_by uuid not null references auth.users(id),
  -- When the decision was made on the phone (it may sync hours later),
  -- and when the server got it.
  created_at timestamptz not null default now(),
  synced_at timestamptz not null default now(),
  -- Closing and reopening are about the whole week, nothing else.
  check ((item_kind = 'week') = (decision in ('closed', 'reopened')))
);
create index if not exists site_close_reviews_week_idx on site_close_reviews (project_id, week_start, created_at, synced_at);

alter table site_close_reviews enable row level security;
revoke all on table site_close_reviews from anon, authenticated;
grant select, insert on table site_close_reviews to authenticated;

drop policy if exists "project members read the weekly close" on site_close_reviews;
create policy "project members read the weekly close" on site_close_reviews for select
  to authenticated using ((select has_project_access(project_id)));

drop policy if exists "decisions are recorded as yourself, by the right role" on site_close_reviews;
create policy "decisions are recorded as yourself, by the right role" on site_close_reviews for insert
  to authenticated with check (
    decided_by = (select auth.uid())
    and (select has_project_access(project_id))
    and (decision = 'fixed' or (select is_project_owner_or_pm(project_id))));

-- A decision keeps the time it was made on the phone, so one made offline
-- on Saturday still reads Saturday. The server's own clock goes in
-- synced_at, which the phone can't set, and a phone clock running ahead
-- can't date a decision in the future.
create or replace function site_close_reviews_stamp()
returns trigger language plpgsql as $$
begin
  new.synced_at := now();
  if new.created_at is null or new.created_at > now() + interval '5 minutes' then
    new.created_at := now();
  end if;
  return new;
end $$;

drop trigger if exists site_close_reviews_stamp on site_close_reviews;
create trigger site_close_reviews_stamp before insert on site_close_reviews
  for each row execute function site_close_reviews_stamp();

-- Both tables join the change log (20261110020000_incremental_sync.sql).
-- A slip finds its site through its receipt.
create or replace function log_sync_change()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  r jsonb := to_jsonb(case when tg_op = 'DELETE' then old else new end);
  pid uuid;
  cid uuid;
begin
  case tg_table_name
    when 'projects' then pid := (r->>'id')::uuid; cid := (r->>'company_id')::uuid;
    when 'vendors', 'subcontractors' then cid := (r->>'company_id')::uuid;
    when 'dpr_photos' then select project_id into pid from dpr_entries where id = (r->>'dpr_entry_id')::uuid;
    when 'equipment_logs' then select project_id into pid from equipment where id = (r->>'equipment_id')::uuid;
    when 'inspection_items' then select project_id into pid from inspections where id = (r->>'inspection_id')::uuid;
    when 'cost_heads' then select project_id into pid from estimations where id = (r->>'estimation_id')::uuid;
    when 'measurement_entries', 'steel_entries' then
      select e.project_id into pid from cost_heads c join estimations e on e.id = c.estimation_id
       where c.id = (r->>'cost_head_id')::uuid;
    when 'expense_attachments' then select project_id into pid from site_expenses where id = (r->>'expense_id')::uuid;
    when 'site_receipt_attachments' then
      select project_id into pid from site_material_receipts where id = (r->>'receipt_id')::uuid;
    else pid := (r->>'project_id')::uuid;
  end case;
  if pid is null and cid is null then return null; end if;
  insert into sync_changes (table_name, row_id, op, project_id, company_id)
  values (tg_table_name, (r->>'id')::uuid, case when tg_op = 'DELETE' then 'd' else 'u' end, pid, cid);
  return null;
end $$;
revoke all on function log_sync_change() from public, anon, authenticated;

drop trigger if exists site_receipt_attachments_log_sync_change on site_receipt_attachments;
create trigger site_receipt_attachments_log_sync_change after insert or update or delete on site_receipt_attachments
  for each row execute function log_sync_change();
drop trigger if exists site_close_reviews_log_sync_change on site_close_reviews;
create trigger site_close_reviews_log_sync_change after insert or update or delete on site_close_reviews
  for each row execute function log_sync_change();
