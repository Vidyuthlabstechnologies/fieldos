-- The daily site close: a site engineer sends, reopens and explains a day
-- as themselves; only the owner or a PM follows up, overrides or sets the
-- cutoff and supervisors; events can't be edited or deleted; an outsider
-- sees nothing; sync status is stamped by the server for the caller only.
-- Everything rolls back.
\set ON_ERROR_STOP on
begin;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'pm@example.com'),
  ('00000000-0000-0000-0000-0000000000d2', 'sup@example.com'),
  ('00000000-0000-0000-0000-0000000000d3', 'outsider@example.com');
insert into companies (id, name) values ('00000000-0000-0000-0000-00000000c001', 'Sai Constructions');
insert into company_members (company_id, user_id, role) values
  ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-0000000000d1', 'project_manager'),
  ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-0000000000d2', 'site_engineer');
insert into projects (id, company_id, name) values
  ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-00000000c001', 'Kompally Villas');

create or replace function pg_temp.as_user(u uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u::text, true);
$$;

set local role authenticated;

-- The site engineer sends the day with "no deliveries", then explains a miss.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000d2');
insert into site_day_events (id, project_id, work_date, kind, no_deliveries, recorded_by, created_at)
values ('00000000-0000-0000-0000-0000000e0001', '00000000-0000-0000-0000-00000000a001', current_date, 'submitted', true,
        '00000000-0000-0000-0000-0000000000d2', now() - interval '2 hours');
insert into site_day_events (id, project_id, work_date, kind, reason, recorded_by)
values ('00000000-0000-0000-0000-0000000e0002', '00000000-0000-0000-0000-00000000a001', current_date - 1, 'miss_reason',
        'poor_signal', '00000000-0000-0000-0000-0000000000d2');

do $$
begin
  -- The phone's time is kept (sent offline two hours ago).
  if (select created_at from site_day_events where id = '00000000-0000-0000-0000-0000000e0001')
     > now() - interval '1 hour' then
    raise exception 'the phone''s time was not kept';
  end if;
  -- Not as someone else.
  begin
    insert into site_day_events (id, project_id, work_date, kind, recorded_by)
    values (gen_random_uuid(), '00000000-0000-0000-0000-00000000a001', current_date, 'submitted',
            '00000000-0000-0000-0000-0000000000d1');
    raise exception 'recorded as someone else';
  exception when insufficient_privilege then null;
  end;
  -- Following up and overriding are the manager's.
  begin
    insert into site_day_events (id, project_id, work_date, kind, note, item_ref, recorded_by)
    values (gen_random_uuid(), '00000000-0000-0000-0000-00000000a001', current_date, 'override', 'paid anyway',
            'wages:w1', '00000000-0000-0000-0000-0000000000d2');
    raise exception 'an engineer overrode';
  exception when insufficient_privilege then null;
  end;
  -- A miss needs its reason; an override its reason and item.
  begin
    insert into site_day_events (id, project_id, work_date, kind, recorded_by)
    values (gen_random_uuid(), '00000000-0000-0000-0000-00000000a001', current_date, 'miss_reason',
            '00000000-0000-0000-0000-0000000000d2');
    raise exception 'a miss without a reason';
  exception when check_violation then null;
  end;
  -- Events can't be rewritten.
  begin
    update site_day_events set no_deliveries = false where id = '00000000-0000-0000-0000-0000000e0001';
    raise exception 'an event was edited';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from site_day_events where id = '00000000-0000-0000-0000-0000000e0001';
    raise exception 'an event was deleted';
  exception when insufficient_privilege then null;
  end;
  -- Only a manager sets the cutoff and supervisors.
  begin
    insert into site_close_settings (id, project_id, cutoff_minutes, updated_by)
    values ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-00000000a001', 1080,
            '00000000-0000-0000-0000-0000000000d2');
    raise exception 'an engineer set the cutoff';
  exception when insufficient_privilege then null;
  end;
  -- Sync status: stamped for the caller.
  perform report_sync_status('00000000-0000-0000-0000-00000000c001', 3);
  if (select pending_count from member_sync_status where user_id = '00000000-0000-0000-0000-0000000000d2') <> 3 then
    raise exception 'sync status not recorded';
  end if;
end $$;

-- The manager follows up, overrides, and names a backup supervisor.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
insert into site_day_events (id, project_id, work_date, kind, note, recorded_by)
values (gen_random_uuid(), '00000000-0000-0000-0000-00000000a001', current_date - 1, 'follow_up', 'Called Ravi',
        '00000000-0000-0000-0000-0000000000d1');
insert into site_day_events (id, project_id, work_date, kind, note, item_ref, amount, recorded_by)
values (gen_random_uuid(), '00000000-0000-0000-0000-00000000a001', current_date, 'override', 'Saw the gang on site',
        'wages:w1', 800, '00000000-0000-0000-0000-0000000000d1');
insert into site_close_settings (id, project_id, cutoff_minutes, supervisor_id, backup_id, backup_until, updated_by)
values ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-00000000a001', 1080,
        '00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000d1', current_date + 3,
        '00000000-0000-0000-0000-0000000000d1');

do $$
begin
  -- The supervisor must be on the company.
  begin
    update site_close_settings set supervisor_id = '00000000-0000-0000-0000-0000000000d3'
     where id = '00000000-0000-0000-0000-00000000a001';
    raise exception 'an outsider became supervisor';
  exception when raise_exception then
    if sqlerrm = 'an outsider became supervisor' then raise; end if;
  end;
  if (select count(*) from member_sync_status) <> 1 then raise exception 'the manager should see the team''s sync'; end if;
  begin
    perform report_sync_status('00000000-0000-0000-0000-00000000c999', 0);
    raise exception 'reported for another company';
  exception when insufficient_privilege then null;
  end;
end $$;

-- An outsider sees nothing.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000d3');
do $$
begin
  if exists (select 1 from site_day_events) or exists (select 1 from site_close_settings)
     or exists (select 1 from member_sync_status) then
    raise exception 'an outsider can read the daily close';
  end if;
end $$;

reset role;
-- Both tables are in the change log.
do $$
begin
  if (select count(*) from sync_changes where table_name = 'site_day_events') < 4 then
    raise exception 'day events missing from the change log';
  end if;
  if not exists (select 1 from sync_changes where table_name = 'site_close_settings') then
    raise exception 'settings missing from the change log';
  end if;
end $$;

rollback;
