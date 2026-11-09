-- Attendance marked by hand (app schema v11). Many sites keep a muster
-- roll instead of GPS punches, and Onsite's reviews ask for quarter and
-- half days and 1.5x, double and triple for overtime. One row per worker
-- per day: phones derive its id from the site, worker and day, so a mark
-- made on two phones is one row and the later one wins. A null units
-- means "count the punches again", which is how a mark is cleared (pulls
-- don't carry deletes).

create table if not exists site_attendance_marks (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  worker_id uuid not null references workers(id) on delete cascade,
  day text not null check (day ~ '^\d{4}-\d{2}-\d{2}$'),
  units numeric(3, 2) check (units in (0, 0.25, 0.5, 1, 1.5, 2, 3)),
  recorded_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  unique (project_id, worker_id, day)
);
create index if not exists site_attendance_marks_project_idx on site_attendance_marks (project_id, day);

alter table site_attendance_marks enable row level security;
grant select, insert, update on site_attendance_marks to authenticated;

drop policy if exists "project members read attendance marks" on site_attendance_marks;
create policy "project members read attendance marks" on site_attendance_marks for select
  to authenticated using ((select has_project_access(project_id)));

drop policy if exists "project members mark attendance as themselves" on site_attendance_marks;
create policy "project members mark attendance as themselves" on site_attendance_marks for insert
  to authenticated with check (recorded_by = (select auth.uid()) and (select has_project_access(project_id)));

drop policy if exists "project members change attendance marks" on site_attendance_marks;
create policy "project members change attendance marks" on site_attendance_marks for update
  to authenticated
  using ((select has_project_access(project_id)))
  with check (recorded_by = (select auth.uid()) and (select has_project_access(project_id)));

-- A changed mark stays on its site, worker and day.
create or replace function site_attendance_marks_keep_key()
returns trigger language plpgsql as $$
begin
  new.id := old.id;
  new.project_id := old.project_id;
  new.worker_id := old.worker_id;
  new.day := old.day;
  return new;
end $$;

drop trigger if exists site_attendance_marks_keep_key on site_attendance_marks;
create trigger site_attendance_marks_keep_key before update on site_attendance_marks
  for each row execute function site_attendance_marks_keep_key();
