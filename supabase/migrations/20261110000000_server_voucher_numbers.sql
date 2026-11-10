-- Voucher numbers are given out by the server (audit P0, 2026-11-10).
--
-- Each phone used to number a new expense one past the highest voucher it
-- knew for the site. Two phones offline on the same site both issued, say,
-- voucher 12, and both rows synced with the same printed reference. The
-- expense id stays the record's identity; the voucher number is now only
-- final once the server has allocated it on insert. The number a phone
-- shows before that is provisional (the app marks it so) and is replaced
-- by the server's on the next pull.
--
-- Older app versions keep working: whatever voucher_no they send on insert
-- is ignored the same way.

create table if not exists site_voucher_counters (
  project_id uuid primary key references projects(id) on delete cascade,
  last_no integer not null check (last_no >= 0)
);

-- Only the trigger below touches the counters.
alter table site_voucher_counters enable row level security;
revoke all on table site_voucher_counters from anon, authenticated;

-- Start each site's counter after the highest number already in the cloud.
insert into site_voucher_counters (project_id, last_no)
select project_id, max(voucher_no) from site_expenses where voucher_no is not null group by project_id
on conflict (project_id) do update set last_no = greatest(site_voucher_counters.last_no, excluded.last_no);

-- Sites that already hold the same number twice (the bug this fixes): the
-- later entry, by when it reached the server, gets a fresh number at the
-- end, so every printed reference in the cloud is unique from here on.
do $$
declare r record; n integer;
begin
  for r in
    select id, project_id from (
      select id, project_id,
             row_number() over (partition by project_id, voucher_no order by created_at, id) as dup
        from site_expenses where voucher_no is not null) d
     where dup > 1
     order by project_id
  loop
    update site_voucher_counters set last_no = last_no + 1 where project_id = r.project_id returning last_no into n;
    -- Bypass the keep-origin trigger's "a voucher number never changes"
    -- rule for this one-off repair only.
    alter table site_expenses disable trigger site_expenses_keep_origin;
    update site_expenses set voucher_no = n where id = r.id;
    alter table site_expenses enable trigger site_expenses_keep_origin;
  end loop;
end $$;

create unique index if not exists site_expenses_voucher_unique
  on site_expenses (project_id, voucher_no) where voucher_no is not null;

-- security definer: callers have no grant on the counters table. The row
-- lock taken by the upsert serialises concurrent inserts for one site.
create or replace function site_expenses_allocate_voucher()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into site_voucher_counters as c (project_id, last_no) values (new.project_id, 1)
  on conflict (project_id) do update set last_no = c.last_no + 1
  returning last_no into new.voucher_no;
  return new;
end $$;

revoke all on function site_expenses_allocate_voucher() from public, anon, authenticated;

drop trigger if exists site_expenses_allocate_voucher on site_expenses;
create trigger site_expenses_allocate_voucher before insert on site_expenses
  for each row execute function site_expenses_allocate_voucher();
