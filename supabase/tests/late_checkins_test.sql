-- Checks 20261127150000_late_checkins_need_review.sql. Run after `supabase start`:
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/late_checkins_test.sql
-- Everything runs in one transaction that is rolled back.
begin;

insert into auth.users (id, email, aud, role) values
  ('77e00000-0000-4000-8000-0000000000a1', 'lc-owner@example.test', 'authenticated', 'authenticated'),
  ('77e00000-0000-4000-8000-0000000000a2', 'lc-engineer@example.test', 'authenticated', 'authenticated');
insert into companies (id, name, join_code, created_by) values
  ('77e00000-0000-4000-8000-00000000c0a0', 'Late Co', 'LATEAAAAA1', '77e00000-0000-4000-8000-0000000000a1');
insert into company_members (company_id, user_id, role) values
  ('77e00000-0000-4000-8000-00000000c0a0', '77e00000-0000-4000-8000-0000000000a1', 'owner'),
  ('77e00000-0000-4000-8000-00000000c0a0', '77e00000-0000-4000-8000-0000000000a2', 'site_engineer');
insert into projects (id, company_id, name, location_lat, location_lng, geofence_radius_m) values
  ('77e00000-0000-4000-8000-0000000000fa', '77e00000-0000-4000-8000-00000000c0a0', 'Fenced site', 17.45, 78.38, 100);

create or replace function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

set local role authenticated;
select pg_temp.act_as('77e00000-0000-4000-8000-0000000000a2');

-- On time, inside the fence: verified at once, as before.
insert into staff_attendance (id, company_id, project_id, day, check_in, in_lat, in_lng)
values ('77e00000-0000-4000-8000-0000000007a1', '77e00000-0000-4000-8000-00000000c0a0', '77e00000-0000-4000-8000-0000000000fa',
        current_date, now() - interval '2 hours', 17.4501, 78.3801);
-- Three days late, inside the fence: waits for a manager, flagged, with a reason.
insert into staff_attendance (id, company_id, project_id, day, check_in, in_lat, in_lng)
values ('77e00000-0000-4000-8000-0000000007a2', '77e00000-0000-4000-8000-00000000c0a0', '77e00000-0000-4000-8000-0000000000fa',
        (now() - interval '3 days')::date, now() - interval '3 days', 17.4501, 78.3801);
-- Late and outside, with the person's own reason: waits, reason kept.
insert into staff_attendance (id, company_id, project_id, day, check_in, in_lat, in_lng, reason)
values ('77e00000-0000-4000-8000-0000000007a3', '77e00000-0000-4000-8000-00000000c0a0', '77e00000-0000-4000-8000-0000000000fa',
        (now() - interval '4 days')::date, now() - interval '4 days', 17.60, 78.38, 'Steel at the yard');
-- A changed app says it was not late; on time but claims it was. The server decides.
insert into staff_attendance (id, company_id, project_id, day, check_in, in_lat, in_lng, sent_late)
values ('77e00000-0000-4000-8000-0000000007a4', '77e00000-0000-4000-8000-00000000c0a0', '77e00000-0000-4000-8000-0000000000fa',
        (now() - interval '5 days')::date, now() - interval '5 days', 17.4501, 78.3801, false);
insert into staff_attendance (id, company_id, project_id, day, check_in, in_lat, in_lng, sent_late)
values ('77e00000-0000-4000-8000-0000000007a5', '77e00000-0000-4000-8000-00000000c0a0', '77e00000-0000-4000-8000-0000000000fa',
        (now() - interval '6 hours')::date - 1, now() - interval '6 hours', 17.4501, 78.3801, true);

do $$
declare r record;
begin
  select * into r from staff_attendance where id = '77e00000-0000-4000-8000-0000000007a1';
  if r.status <> 'ok' or r.sent_late then raise exception 'an on-time check-in inside the fence should be ok, got % late=%', r.status, r.sent_late; end if;
  select * into r from staff_attendance where id = '77e00000-0000-4000-8000-0000000007a2';
  if r.status <> 'pending' or not r.sent_late or r.within_geofence is not true
     or coalesce(r.reason, '') not like 'Sent more than 24 hours%' then
    raise exception 'a 3-day-late check-in inside the fence should wait with a reason: % late=% reason=%', r.status, r.sent_late, r.reason;
  end if;
  select * into r from staff_attendance where id = '77e00000-0000-4000-8000-0000000007a3';
  if r.status <> 'pending' or not r.sent_late or r.reason <> 'Steel at the yard' then
    raise exception 'the person''s own reason must be kept: %', r.reason;
  end if;
  select * into r from staff_attendance where id = '77e00000-0000-4000-8000-0000000007a4';
  if r.status <> 'pending' or not r.sent_late then raise exception 'a changed app cleared the late flag'; end if;
  select * into r from staff_attendance where id = '77e00000-0000-4000-8000-0000000007a5';
  if r.sent_late or r.status <> 'ok' then raise exception 'a changed app set the late flag on an on-time check-in'; end if;
end $$;

-- The phone's check-out on a late row is a whole-row update that still carries
-- its own, older copy ('ok', no reason). It must go through and the server's
-- verdict must stand.
update staff_attendance
   set status = 'ok', reason = null, check_out = now() - interval '2 days 16 hours', out_lat = 17.4501, out_lng = 78.3801
 where id = '77e00000-0000-4000-8000-0000000007a2';
do $$
declare r record;
begin
  select * into r from staff_attendance where id = '77e00000-0000-4000-8000-0000000007a2';
  if r.check_out is null then raise exception 'the check-out of a late row was not recorded'; end if;
  if r.status <> 'pending' or not r.sent_late or coalesce(r.reason, '') = '' then
    raise exception 'the server''s verdict on a late row was lost: % %', r.status, r.reason;
  end if;
end $$;

-- Approving your own late day is still refused, as for any day.
do $$
begin
  begin
    update staff_attendance set status = 'approved' where id = '77e00000-0000-4000-8000-0000000007a3';
    raise exception 'a person approved their own late day';
  exception when sqlstate '42501' then null;
  end;
  begin
    update staff_attendance set status = 'approved' where id = '77e00000-0000-4000-8000-0000000007a2';
    raise exception 'a person approved their own late day (stale-copy path)';
  exception when sqlstate '42501' then null;
  end;
end $$;

-- A manager still decides it, and the decision sticks.
reset role;
select pg_temp.act_as('77e00000-0000-4000-8000-0000000000a1');
set local role authenticated;
update staff_attendance set status = 'approved', review_note = 'Phone was offline' where id = '77e00000-0000-4000-8000-0000000007a2';
reset role;
do $$ begin
  if (select status from staff_attendance where id = '77e00000-0000-4000-8000-0000000007a2') <> 'approved' then
    raise exception 'the manager could not approve a late day';
  end if;
end $$;

do $$ begin raise notice 'late_checkins_test: OK'; end $$;
rollback;
