-- Site cash book (app schema v36). The owner, a project manager or the
-- site's accounts person hands cash to someone on site ("given"), takes
-- back what is left ("returned"), and now and then counts what the person
-- actually holds ("counted"). What they spent is not stored here: it is
-- their own cash expenses on the site (site_expenses, recorded_by = the
-- holder), so the book can't disagree with the money book.
--
-- A count that comes out below the book is the "unexplained cash" the
-- pilot scorecard reports. Rows are never edited; a mistake is cancelled
-- (voided, with a reason) and written again, so the trail stays whole.

create table if not exists site_cash_moves (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  holder_id uuid not null references auth.users(id),
  kind text not null check (kind in ('given', 'returned', 'counted')),
  amount numeric(14, 2) not null check (amount >= 0 and (kind = 'counted' or amount > 0)),
  moved_on date not null,
  note text check (char_length(note) <= 300),
  recorded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  voided boolean not null default false,
  void_reason text check (char_length(void_reason) <= 200)
);
create index if not exists site_cash_moves_project_idx on site_cash_moves (project_id, moved_on);
create index if not exists site_cash_moves_holder_idx on site_cash_moves (holder_id);

-- Who keeps a site's cash: the company's owners and managers, the site's
-- own project manager, and the site's accounts person. coalesce: the
-- helpers can answer NULL for an outsider (20261110445000).
create or replace function is_site_cash_keeper(p_project_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select coalesce(is_project_owner_or_pm(p_project_id), false)
      or exists (
        select 1 from project_members pm join projects p on p.id = pm.project_id
         where pm.project_id = p_project_id
           and pm.user_id = (select auth.uid())
           and pm.role = 'accounts'
           and company_role(p.company_id) is not null);
$$;
revoke all on function is_site_cash_keeper(uuid) from public, anon;
grant execute on function is_site_cash_keeper(uuid) to authenticated;

alter table site_cash_moves enable row level security;
revoke all on table site_cash_moves from anon, authenticated;
grant select, insert, update on table site_cash_moves to authenticated;

-- The holder sees their own book; keepers see everyone's on the site.
drop policy if exists "holders and keepers read the cash book" on site_cash_moves;
create policy "holders and keepers read the cash book" on site_cash_moves for select
  to authenticated using (
    (select has_project_access(project_id))
    and (holder_id = (select auth.uid()) or (select is_site_cash_keeper(project_id))));

drop policy if exists "keepers write the cash book as themselves" on site_cash_moves;
create policy "keepers write the cash book as themselves" on site_cash_moves for insert
  to authenticated with check (
    recorded_by = (select auth.uid())
    and (select has_project_access(project_id))
    and (select is_site_cash_keeper(project_id)));

drop policy if exists "keepers cancel cash book entries" on site_cash_moves;
create policy "keepers cancel cash book entries" on site_cash_moves for update
  to authenticated
  using ((select is_site_cash_keeper(project_id)))
  with check ((select is_site_cash_keeper(project_id)));

-- The holder must be in the site's company, and a phone clock running
-- ahead can't date an entry in the future.
create or replace function site_cash_moves_check()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (
       select 1 from projects p join company_members cm on cm.company_id = p.company_id
        where p.id = new.project_id and cm.user_id = new.holder_id) then
    raise exception 'The person holding the cash is not on this company';
  end if;
  if new.created_at is null or new.created_at > now() + interval '5 minutes' then
    new.created_at := now();
  end if;
  return new;
end $$;
revoke all on function site_cash_moves_check() from public, anon, authenticated;

drop trigger if exists site_cash_moves_check on site_cash_moves;
create trigger site_cash_moves_check before insert on site_cash_moves
  for each row execute function site_cash_moves_check();

-- An entry is only ever cancelled: everything but voided/void_reason keeps
-- its value, and a cancelled entry stays cancelled.
create or replace function site_cash_moves_only_cancel()
returns trigger language plpgsql as $$
begin
  if old.voided and not new.voided then
    raise exception 'A cancelled cash entry stays cancelled';
  end if;
  new.id := old.id;
  new.project_id := old.project_id;
  new.holder_id := old.holder_id;
  new.kind := old.kind;
  new.amount := old.amount;
  new.moved_on := old.moved_on;
  new.note := old.note;
  new.recorded_by := old.recorded_by;
  new.created_at := old.created_at;
  return new;
end $$;

drop trigger if exists site_cash_moves_only_cancel on site_cash_moves;
create trigger site_cash_moves_only_cancel before update on site_cash_moves
  for each row execute function site_cash_moves_only_cancel();

-- The change log (20261110020000_incremental_sync.sql); the row carries
-- project_id, so log_sync_change needs no new case.
drop trigger if exists site_cash_moves_log_sync_change on site_cash_moves;
create trigger site_cash_moves_log_sync_change after insert or update or delete on site_cash_moves
  for each row execute function log_sync_change();
