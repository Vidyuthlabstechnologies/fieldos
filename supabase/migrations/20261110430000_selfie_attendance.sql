-- Selfie and geofence attendance (2026-11-10).
--
-- attendance_photos: the photo taken at a labour punch (the worker, or the
--   morning roll call standing for everyone punched in together) or at a
--   staff check-in or check-out (a selfie). Stamped with time and GPS on the
--   phone, kept as evidence, never edited. Files sit in the documents bucket
--   at {project_id}/attendance/{id}.jpg, under the existing site policies.
-- site_attendance: gains photo_id, distance_m and accuracy_m.
-- staff_attendance: staff checking themselves in and out at a site. The
--   server works out "inside the geofence" again from the coordinates and
--   the site's location, so a changed app cannot mark itself inside. Inside
--   counts at once ('ok'); outside, without a fix or without a site location
--   it waits ('pending') for an owner or project manager to approve.
-- staff_members: gains user_id, the person's FieldOS login, so their days
--   show beside their salary.
--
-- Who:
-- - Anyone on a site's team checks themselves in there; they see their own
--   days. Owners and project managers see everyone's and decide.
-- - Nobody approves their own day.

-- --- Photos ------------------------------------------------------------------

create table if not exists attendance_photos (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  file_path text not null check (char_length(file_path) between 1 and 500),
  mime_type text not null default 'image/jpeg' check (char_length(mime_type) <= 100),
  taken_by uuid references auth.users(id) default auth.uid(),
  taken_at timestamptz not null,
  lat double precision,
  lng double precision,
  created_at timestamptz not null default now()
);
create index if not exists attendance_photos_project_idx on attendance_photos (project_id);

create or replace function attendance_photos_stamp()
returns trigger language plpgsql as $$
begin
  new.taken_by := auth.uid();
  new.created_at := now();
  if new.taken_at > now() + interval '5 minutes' then
    new.taken_at := now();
  end if;
  -- The file sits in the site's own folder.
  if split_part(new.file_path, '/', 1) <> new.project_id::text then
    raise exception 'photo file belongs to another site' using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists attendance_photos_stamp on attendance_photos;
create trigger attendance_photos_stamp before insert on attendance_photos
  for each row execute function attendance_photos_stamp();

alter table attendance_photos enable row level security;
revoke all on table attendance_photos from anon, authenticated;
grant select, insert on table attendance_photos to authenticated;

drop policy if exists "site team reads attendance photos" on attendance_photos;
create policy "site team reads attendance photos" on attendance_photos for select to authenticated
  using ((select has_project_access(project_id)));
drop policy if exists "site team adds attendance photos" on attendance_photos;
create policy "site team adds attendance photos" on attendance_photos for insert to authenticated
  with check ((select has_project_access(project_id)));

drop trigger if exists attendance_photos_log_sync_change on attendance_photos;
create trigger attendance_photos_log_sync_change after insert or update or delete on attendance_photos
  for each row execute function log_sync_change();

-- --- Labour punches ----------------------------------------------------------

alter table site_attendance add column if not exists photo_id uuid;
alter table site_attendance add column if not exists distance_m numeric(12, 1)
  check (distance_m is null or distance_m >= 0);
alter table site_attendance add column if not exists accuracy_m numeric(10, 1)
  check (accuracy_m is null or accuracy_m >= 0);

-- --- Staff login on the salary list -----------------------------------------

alter table staff_members add column if not exists user_id uuid references auth.users(id) on delete set null;
create unique index if not exists staff_members_user_idx on staff_members (company_id, user_id)
  where user_id is not null;

-- --- Staff checking in -------------------------------------------------------

create table if not exists staff_attendance (
  id uuid primary key,
  company_id uuid not null references companies(id) on delete cascade,
  project_id uuid not null references projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  check_in timestamptz not null,
  check_out timestamptz,
  in_lat double precision,
  in_lng double precision,
  in_accuracy_m numeric(10, 1),
  in_distance_m numeric(12, 1),
  in_photo_id uuid,
  within_geofence boolean,
  out_lat double precision,
  out_lng double precision,
  out_distance_m numeric(12, 1),
  out_photo_id uuid,
  out_within boolean,
  status text not null default 'pending' check (status in ('ok', 'pending', 'approved', 'rejected')),
  reason text check (char_length(reason) <= 300),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  review_note text check (char_length(review_note) <= 300),
  created_at timestamptz not null default now(),
  check (check_out is null or check_out > check_in),
  unique (user_id, project_id, day)
);
create index if not exists staff_attendance_company_day_idx on staff_attendance (company_id, day);
create index if not exists staff_attendance_project_idx on staff_attendance (project_id);

-- Metres between two points (haversine), for the geofence check.
create or replace function geo_distance_m(lat1 double precision, lng1 double precision,
                                          lat2 double precision, lng2 double precision)
returns double precision language sql immutable as $$
  select 2 * 6371000 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2)
    + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)))
$$;

create or replace function staff_attendance_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  site record;
  manager boolean;
  d double precision;
begin
  select company_id, location_lat, location_lng, coalesce(geofence_radius_m, 100) as radius
    into site from projects where id = new.project_id;
  if site.company_id is null or site.company_id <> new.company_id then
    raise exception 'site belongs to another company' using errcode = '42501';
  end if;
  manager := is_company_owner_or_pm(new.company_id);

  if tg_op = 'INSERT' then
    new.user_id := auth.uid();
    new.created_at := now();
    if new.check_in > now() + interval '5 minutes' then
      raise exception 'check-in is in the future' using errcode = '22023';
    end if;
    -- Inside or not is the server's call, from the coordinates.
    if new.in_lat is not null and new.in_lng is not null and site.location_lat is not null
       and site.location_lng is not null then
      d := geo_distance_m(new.in_lat, new.in_lng, site.location_lat, site.location_lng);
      new.in_distance_m := round(d::numeric, 1);
      new.within_geofence := d <= site.radius;
    else
      new.in_distance_m := null;
      new.within_geofence := null;
    end if;
    new.status := case when new.within_geofence then 'ok' else 'pending' end;
    new.reviewed_by := null;
    new.reviewed_at := null;
    new.review_note := null;
    return new;
  end if;

  if new.company_id is distinct from old.company_id or new.project_id is distinct from old.project_id
     or new.user_id is distinct from old.user_id or new.day is distinct from old.day
     or new.check_in is distinct from old.check_in or new.in_lat is distinct from old.in_lat
     or new.in_lng is distinct from old.in_lng or new.in_photo_id is distinct from old.in_photo_id
     or new.reason is distinct from old.reason then
    raise exception 'a check-in is kept as it was made' using errcode = '42501';
  end if;
  new.in_distance_m := old.in_distance_m;
  new.within_geofence := old.within_geofence;
  new.in_accuracy_m := old.in_accuracy_m;
  new.created_at := old.created_at;

  -- Check-out: only the person themself, once.
  if new.check_out is distinct from old.check_out or new.out_lat is distinct from old.out_lat
     or new.out_lng is distinct from old.out_lng or new.out_photo_id is distinct from old.out_photo_id then
    if old.user_id <> auth.uid() then
      raise exception 'only they check themselves out' using errcode = '42501';
    end if;
    if old.check_out is not null then
      raise exception 'already checked out' using errcode = '42501';
    end if;
    if new.out_lat is not null and new.out_lng is not null and site.location_lat is not null
       and site.location_lng is not null then
      d := geo_distance_m(new.out_lat, new.out_lng, site.location_lat, site.location_lng);
      new.out_distance_m := round(d::numeric, 1);
      new.out_within := d <= site.radius;
    else
      new.out_distance_m := null;
      new.out_within := null;
    end if;
  else
    new.out_distance_m := old.out_distance_m;
    new.out_within := old.out_within;
  end if;

  -- The decision: an owner or project manager, never on their own day.
  if new.status is distinct from old.status or new.review_note is distinct from old.review_note then
    if not manager or old.user_id = auth.uid() then
      raise exception 'an owner or project manager decides, not on their own day' using errcode = '42501';
    end if;
    if new.status not in ('approved', 'rejected') then
      raise exception 'approve or turn down' using errcode = '22023';
    end if;
    new.reviewed_by := auth.uid();
    new.reviewed_at := now();
  else
    new.reviewed_by := old.reviewed_by;
    new.reviewed_at := old.reviewed_at;
  end if;
  return new;
end $$;
revoke all on function staff_attendance_guard() from public, anon, authenticated;

drop trigger if exists staff_attendance_guard on staff_attendance;
create trigger staff_attendance_guard before insert or update on staff_attendance
  for each row execute function staff_attendance_guard();

alter table staff_attendance enable row level security;
revoke all on table staff_attendance from anon, authenticated;
grant select, insert, update on table staff_attendance to authenticated;

drop policy if exists "own or manager reads staff attendance" on staff_attendance;
create policy "own or manager reads staff attendance" on staff_attendance for select to authenticated
  using (user_id = (select auth.uid()) or (select is_company_owner_or_pm(company_id)));
drop policy if exists "site team checks in" on staff_attendance;
create policy "site team checks in" on staff_attendance for insert to authenticated
  with check (user_id = (select auth.uid()) and (select has_project_access(project_id))
              and (select is_company_member(company_id)));
drop policy if exists "own check-out or manager decision" on staff_attendance;
create policy "own check-out or manager decision" on staff_attendance for update to authenticated
  using (user_id = (select auth.uid()) or (select is_company_owner_or_pm(company_id)))
  with check (user_id = (select auth.uid()) or (select is_company_owner_or_pm(company_id)));

drop trigger if exists staff_attendance_log_sync_change on staff_attendance;
create trigger staff_attendance_log_sync_change after insert or update or delete on staff_attendance
  for each row execute function log_sync_change();
