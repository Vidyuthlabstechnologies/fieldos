-- Money book (app schema v10). Onsite's Play reviews ask for vouchers an
-- accountant can work with: who was paid and how, GST, a voucher number,
-- and a way to correct a wrong entry. Entries are never deleted: a wrong
-- one is cancelled with a reason, so numbers have no gaps and the trail
-- stays. Every new column is nullable or has a default, so phones on older
-- app versions keep inserting as before.

alter table site_expenses
  add column if not exists paid_to text check (char_length(paid_to) <= 120),
  add column if not exists mode text check (mode in ('cash', 'upi', 'bank', 'cheque')),
  add column if not exists gst_pct numeric(5, 2) check (gst_pct >= 0 and gst_pct <= 40),
  add column if not exists gst_inter_state boolean not null default false,
  add column if not exists voucher_no integer check (voucher_no > 0),
  add column if not exists voided boolean not null default false,
  add column if not exists void_reason text check (char_length(void_reason) <= 200),
  add column if not exists edited_at timestamptz,
  add column if not exists edited_by uuid references auth.users(id);

alter table site_payments_received
  add column if not exists voided boolean not null default false,
  add column if not exists void_reason text check (char_length(void_reason) <= 200),
  add column if not exists edited_at timestamptz,
  add column if not exists edited_by uuid references auth.users(id);

-- Expenses already in the cloud get voucher numbers per site in date
-- order, the same order phones use when they upgrade, before the trigger
-- below exists so the rows don't read as edited.
update site_expenses e
   set voucher_no = n.rn
  from (select id, row_number() over (partition by project_id order by incurred_on, created_at) as rn
          from site_expenses) n
 where e.id = n.id and e.voucher_no is null;

grant update on site_expenses, site_payments_received to authenticated;

-- Whoever wrote an expense, or the site's owner or project manager, may
-- correct or cancel it. It can't move to another site.
drop policy if exists "writer or owner/PM corrects expenses" on site_expenses;
create policy "writer or owner/PM corrects expenses" on site_expenses for update
  to authenticated
  using ((select has_project_access(project_id))
         and (recorded_by = (select auth.uid()) or (select is_project_owner_or_pm(project_id))))
  with check ((select has_project_access(project_id)));

drop policy if exists "owners and PMs correct money in" on site_payments_received;
create policy "owners and PMs correct money in" on site_payments_received for update
  to authenticated
  using ((select is_project_owner_or_pm(project_id)))
  with check ((select is_project_owner_or_pm(project_id)));

-- What a correction may not change: the site, who first wrote it, when,
-- and its voucher number once it has one. The editor is always the caller.
create or replace function site_money_keep_origin()
returns trigger language plpgsql as $$
begin
  new.id := old.id;
  new.project_id := old.project_id;
  new.recorded_by := old.recorded_by;
  new.created_at := old.created_at;
  if tg_table_name = 'site_expenses' and old.voucher_no is not null then
    new.voucher_no := old.voucher_no;
  end if;
  new.edited_by := coalesce((select auth.uid()), new.edited_by);
  new.edited_at := coalesce(new.edited_at, now());
  return new;
end $$;

drop trigger if exists site_expenses_keep_origin on site_expenses;
create trigger site_expenses_keep_origin before update on site_expenses
  for each row execute function site_money_keep_origin();

drop trigger if exists site_payments_received_keep_origin on site_payments_received;
create trigger site_payments_received_keep_origin before update on site_payments_received
  for each row execute function site_money_keep_origin();
