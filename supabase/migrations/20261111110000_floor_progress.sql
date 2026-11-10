-- Floor progress for the RERA quarterly report (app schema v37). TS-RERA
-- asks each registered project for its stage and % complete, block by
-- block and floor by floor, every quarter, with photos and the work done.
-- Each update is a new row (insert-only): the latest row for a block and
-- floor on or before a date is its progress then, so last quarter's
-- figures can be printed again exactly as they were.

create table if not exists site_floor_progress (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  block text not null check (char_length(btrim(block)) between 1 and 60),
  floor text not null check (char_length(btrim(floor)) between 1 and 30),
  stage text not null check (stage in ('not_started', 'excavation', 'foundation', 'plinth', 'columns', 'slab',
                                       'masonry', 'plastering', 'flooring', 'finishing', 'complete')),
  pct integer not null check (pct between 0 and 100),
  as_of date not null,
  note text check (char_length(note) <= 300),
  recorded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists site_floor_progress_project_idx on site_floor_progress (project_id, block, floor, as_of);

alter table site_floor_progress enable row level security;
revoke all on table site_floor_progress from anon, authenticated;
grant select, insert on table site_floor_progress to authenticated;

drop policy if exists "site members read floor progress" on site_floor_progress;
create policy "site members read floor progress" on site_floor_progress for select
  to authenticated using ((select has_project_access(project_id)));

-- Anyone on the site who records work may update a floor, as themselves;
-- someone listed as a viewer on the site only reads.
drop policy if exists "site members record floor progress as themselves" on site_floor_progress;
create policy "site members record floor progress as themselves" on site_floor_progress for insert
  to authenticated with check (
    recorded_by = (select auth.uid())
    and (select has_project_access(project_id))
    and not exists (select 1 from project_members pm
                     where pm.project_id = site_floor_progress.project_id
                       and pm.user_id = (select auth.uid()) and pm.role = 'viewer'));

-- A phone clock running ahead can't date an update in the future.
create or replace function site_floor_progress_stamp()
returns trigger language plpgsql as $$
begin
  if new.created_at is null or new.created_at > now() + interval '5 minutes' then
    new.created_at := now();
  end if;
  if new.as_of > current_date + 1 then
    raise exception 'Progress can''t be dated in the future';
  end if;
  return new;
end $$;

drop trigger if exists site_floor_progress_stamp on site_floor_progress;
create trigger site_floor_progress_stamp before insert on site_floor_progress
  for each row execute function site_floor_progress_stamp();

drop trigger if exists site_floor_progress_log_sync_change on site_floor_progress;
create trigger site_floor_progress_log_sync_change after insert or update or delete on site_floor_progress
  for each row execute function log_sync_change();
