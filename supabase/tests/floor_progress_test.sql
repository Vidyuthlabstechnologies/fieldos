-- Floor progress for the RERA report: anyone on the site records an
-- update as themselves; a site viewer and an outsider can't; updates are
-- never changed or deleted; no future dates. Everything rolls back.
\set ON_ERROR_STOP on
begin;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'pm@example.com'),
  ('00000000-0000-0000-0000-0000000000e2', 'sup@example.com'),
  ('00000000-0000-0000-0000-0000000000e3', 'viewer@example.com'),
  ('00000000-0000-0000-0000-0000000000e4', 'outsider@example.com');
insert into companies (id, name) values ('00000000-0000-0000-0000-00000000c0e1', 'Sai Constructions');
insert into company_members (company_id, user_id, role) values
  ('00000000-0000-0000-0000-00000000c0e1', '00000000-0000-0000-0000-0000000000e1', 'project_manager'),
  ('00000000-0000-0000-0000-00000000c0e1', '00000000-0000-0000-0000-0000000000e2', 'site_engineer'),
  ('00000000-0000-0000-0000-00000000c0e1', '00000000-0000-0000-0000-0000000000e3', 'site_engineer');
insert into projects (id, company_id, name) values
  ('00000000-0000-0000-0000-00000000a0e1', '00000000-0000-0000-0000-00000000c0e1', 'Kompally Villas');
insert into project_members (project_id, user_id, role) values
  ('00000000-0000-0000-0000-00000000a0e1', '00000000-0000-0000-0000-0000000000e3', 'viewer');

create or replace function pg_temp.as_user(u uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u::text, true);
$$;

set local role authenticated;

-- The supervisor marks the ground floor slab cast.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e2');
insert into site_floor_progress (id, project_id, block, floor, stage, pct, as_of, recorded_by, created_at)
values ('00000000-0000-0000-0000-00000000fe01', '00000000-0000-0000-0000-00000000a0e1', 'Block A', 'Ground',
        'slab', 45, current_date, '00000000-0000-0000-0000-0000000000e2', now() + interval '3 days');

do $$
begin
  if (select created_at from site_floor_progress where id = '00000000-0000-0000-0000-00000000fe01') > now() + interval '5 minutes' then
    raise exception 'an update was dated ahead of the server clock';
  end if;
  begin
    insert into site_floor_progress (id, project_id, block, floor, stage, pct, as_of, recorded_by)
    values ('00000000-0000-0000-0000-00000000fe02', '00000000-0000-0000-0000-00000000a0e1', 'Block A', '1',
            'slab', 45, current_date + 10, '00000000-0000-0000-0000-0000000000e2');
    raise exception 'progress was dated in the future';
  exception when raise_exception then
    if sqlerrm not like '%future%' then raise; end if;
  end;
  begin
    insert into site_floor_progress (id, project_id, block, floor, stage, pct, as_of, recorded_by)
    values ('00000000-0000-0000-0000-00000000fe03', '00000000-0000-0000-0000-00000000a0e1', 'Block A', '1',
            'slab', 45, current_date, '00000000-0000-0000-0000-0000000000e1');
    raise exception 'an update was written as someone else';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into site_floor_progress (id, project_id, block, floor, stage, pct, as_of, recorded_by)
    values ('00000000-0000-0000-0000-00000000fe04', '00000000-0000-0000-0000-00000000a0e1', 'Block A', '1',
            'slab', 140, current_date, '00000000-0000-0000-0000-0000000000e2');
    raise exception 'progress went over 100%%';
  exception when check_violation then null;
  end;
  update site_floor_progress set pct = 100 where id = '00000000-0000-0000-0000-00000000fe01';
  delete from site_floor_progress where id = '00000000-0000-0000-0000-00000000fe01';
  raise exception 'an update was changed or deleted';
exception
  when insufficient_privilege then null;
end $$;

do $$
begin
  if (select pct from site_floor_progress where id = '00000000-0000-0000-0000-00000000fe01') <> 45 then
    raise exception 'an update changed';
  end if;
end $$;

-- The site viewer reads it but can't record.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e3');
do $$
begin
  if (select count(*) from site_floor_progress) <> 1 then raise exception 'the viewer should read the floors'; end if;
  begin
    insert into site_floor_progress (id, project_id, block, floor, stage, pct, as_of, recorded_by)
    values ('00000000-0000-0000-0000-00000000fe05', '00000000-0000-0000-0000-00000000a0e1', 'Block A', '1',
            'slab', 45, current_date, '00000000-0000-0000-0000-0000000000e3');
    raise exception 'a site viewer recorded progress';
  exception when insufficient_privilege then null;
  end;
end $$;

-- An outsider sees nothing and records nothing.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000e4');
do $$
begin
  if exists (select 1 from site_floor_progress) then raise exception 'an outsider saw floor progress'; end if;
  begin
    insert into site_floor_progress (id, project_id, block, floor, stage, pct, as_of, recorded_by)
    values ('00000000-0000-0000-0000-00000000fe06', '00000000-0000-0000-0000-00000000a0e1', 'Block A', '1',
            'slab', 45, current_date, '00000000-0000-0000-0000-0000000000e4');
    raise exception 'an outsider recorded progress';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
do $$
begin
  if not exists (select 1 from sync_changes where table_name = 'site_floor_progress') then
    raise exception 'floor progress is not in the change log';
  end if;
  raise notice 'floor_progress_test: OK';
end $$;

rollback;
