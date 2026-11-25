-- A check-in sent more than 24 hours after it was made waits for a manager.
--
-- Whether a staff check-in is 'ok' (verified at once, selfie deleted at once)
-- was decided from the coordinates alone, and the check-in time, like the
-- coordinates, comes from the phone. A day back-dated by changing the clock,
-- with a spoofed location inside the fence, was verified automatically and
-- left no selfie to look at. Now a check-in that reaches the server more than
-- 24 hours after the time it carries is 'pending' whatever the coordinates
-- say, with a reason if the person gave none, and its selfie is kept until a
-- manager decides. sent_late records that, set by the server and not by the
-- phone.
--
-- Nothing is refused: a phone that was offline for days still delivers its
-- check-ins, they just need a manager's yes. The phone's later check-out
-- (a whole-row update that still carries its own, older status and an empty
-- reason) is not refused either: on a late row the server's value is kept.
-- Everything else in the function is as it was (built from the live
-- definition). Idempotent.
-- Tested in supabase/tests/late_checkins_test.sql.

alter table staff_attendance add column if not exists sent_late boolean not null default false;

create or replace function public.staff_attendance_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    -- Sent more than a day after it was made: the time came from the phone, so
    -- a manager looks at it even if the coordinates say inside. Never refused
    -- (an offline phone must not lose a day); while it is pending the selfie is
    -- kept for them to see.
    new.sent_late := new.check_in < now() - interval '24 hours';
    if new.sent_late then
      new.status := 'pending';
      if coalesce(btrim(new.reason), '') = '' then
        new.reason := 'Sent more than 24 hours after check-in';
      end if;
    end if;
    new.reviewed_by := null;
    new.reviewed_at := null;
    new.review_note := null;
    return new;
  end if;

  -- The phone's copy of a late row is older than the server's verdict: it still
  -- says 'ok' and has no reason. Its check-out must not be refused for that, so
  -- the server's value is kept. Approving or rejecting is NOT tolerated; that
  -- still goes through the decision rules below and is refused for the person.
  new.sent_late := old.sent_late;
  if old.sent_late and old.user_id = auth.uid() then
    if new.status in ('ok', old.status) then new.status := old.status; end if;
    if coalesce(btrim(new.reason), '') = '' then new.reason := old.reason; end if;
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
end $function$;
