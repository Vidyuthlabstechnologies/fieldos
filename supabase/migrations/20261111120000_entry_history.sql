-- Change history for money and material entries (app schema v38). Every
-- change to, or delete of, an expense, payment, receipt, usage, bill,
-- attendance punch, supplier invoice or work measurement keeps the row as
-- it was and as it became, who changed it and when. Nobody can write,
-- change or delete history: only the trigger adds to it. The site's owner,
-- project manager and accounts person read it.

create table if not exists entry_history (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  table_name text not null,
  row_id uuid not null,
  op text not null check (op in ('update', 'delete')),
  old_row jsonb not null,
  new_row jsonb,
  changed_by uuid references auth.users(id) on delete set null,
  changed_at timestamptz not null default now()
);
create index if not exists entry_history_project_idx on entry_history (project_id, changed_at desc);
create index if not exists entry_history_row_idx on entry_history (row_id);

alter table entry_history enable row level security;
revoke all on table entry_history from anon, authenticated;
grant select on table entry_history to authenticated;

drop policy if exists "site owners, managers and accounts read history" on entry_history;
create policy "site owners, managers and accounts read history" on entry_history for select
  to authenticated using (
    coalesce((select is_project_owner_or_pm(project_id)), false)
    or exists (select 1 from project_members pm
                where pm.project_id = entry_history.project_id
                  and pm.user_id = (select auth.uid()) and pm.role = 'accounts'));

-- Bookkeeping columns that change on their own don't make a history row.
create or replace function record_entry_history()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  o jsonb := to_jsonb(old);
  n jsonb := case when tg_op = 'UPDATE' then to_jsonb(new) end;
begin
  if tg_op = 'UPDATE' and (o - 'edited_at' - 'edited_by') = (n - 'edited_at' - 'edited_by') then
    return null;
  end if;
  -- A site being deleted takes its entries with it: nothing to keep.
  if not exists (select 1 from projects where id = (o->>'project_id')::uuid) then
    return null;
  end if;
  insert into entry_history (project_id, table_name, row_id, op, old_row, new_row, changed_by)
  values ((o->>'project_id')::uuid, tg_table_name, (o->>'id')::uuid, lower(tg_op), o, n,
          (select id from auth.users where id = auth.uid()));
  return null;
end $$;
revoke all on function record_entry_history() from public, anon, authenticated;

do $$
declare t text;
begin
  foreach t in array array['site_expenses', 'site_payments_received', 'site_material_receipts', 'site_material_usage',
                           'site_client_bills', 'site_attendance', 'site_supplier_invoices', 'site_work_measurements']
  loop
    if to_regclass(t) is not null then
      execute format('drop trigger if exists %I on %I', t || '_entry_history', t);
      execute format('create trigger %I after update or delete on %I for each row execute function record_entry_history()',
                     t || '_entry_history', t);
    end if;
  end loop;
end $$;

drop trigger if exists entry_history_log_sync_change on entry_history;
create trigger entry_history_log_sync_change after insert on entry_history
  for each row execute function log_sync_change();
