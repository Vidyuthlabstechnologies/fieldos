-- Change history: a change or delete of an expense keeps the old and new
-- rows with who did it; touching only the edit stamp keeps nothing; the
-- owner/PM and the site's accounts person read it, a site engineer and an
-- outsider don't; nobody writes, changes or deletes history; deleting a
-- site still works. Everything rolls back.
\set ON_ERROR_STOP on
begin;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'pm@example.com'),
  ('00000000-0000-0000-0000-0000000000d2', 'sup@example.com'),
  ('00000000-0000-0000-0000-0000000000d3', 'acc@example.com'),
  ('00000000-0000-0000-0000-0000000000d4', 'outsider@example.com');
insert into companies (id, name) values ('00000000-0000-0000-0000-00000000c0d1', 'Sai Constructions');
insert into company_members (company_id, user_id, role) values
  ('00000000-0000-0000-0000-00000000c0d1', '00000000-0000-0000-0000-0000000000d1', 'project_manager'),
  ('00000000-0000-0000-0000-00000000c0d1', '00000000-0000-0000-0000-0000000000d2', 'site_engineer'),
  ('00000000-0000-0000-0000-00000000c0d1', '00000000-0000-0000-0000-0000000000d3', 'site_engineer');
insert into projects (id, company_id, name) values
  ('00000000-0000-0000-0000-00000000a0d1', '00000000-0000-0000-0000-00000000c0d1', 'Kompally Villas'),
  ('00000000-0000-0000-0000-00000000a0d2', '00000000-0000-0000-0000-00000000c0d1', 'Old site');
insert into project_members (project_id, user_id, role) values
  ('00000000-0000-0000-0000-00000000a0d1', '00000000-0000-0000-0000-0000000000d3', 'accounts');

create or replace function pg_temp.as_user(u uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u::text, true);
$$;

set local role authenticated;

-- The supervisor records ₹2,000 of petty cash, then the PM corrects it.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000d2');
insert into site_expenses (id, project_id, category, amount, incurred_on, recorded_by)
values ('00000000-0000-0000-0000-00000000ed01', '00000000-0000-0000-0000-00000000a0d1', 'Petty cash', 2000,
        current_date, '00000000-0000-0000-0000-0000000000d2');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
update site_expenses set amount = 1500 where id = '00000000-0000-0000-0000-00000000ed01';
reset role;
update site_expenses set edited_at = now() where id = '00000000-0000-0000-0000-00000000ed01';
set local role authenticated;

do $$
declare h entry_history;
begin
  if (select count(*) from entry_history) <> 1 then
    raise exception 'expected one history row, got %', (select count(*) from entry_history);
  end if;
  select * into h from entry_history;
  if h.op <> 'update' or (h.old_row->>'amount')::numeric <> 2000 or (h.new_row->>'amount')::numeric <> 1500
     or h.changed_by <> '00000000-0000-0000-0000-0000000000d1' or h.table_name <> 'site_expenses' then
    raise exception 'the history row is wrong: %', row_to_json(h);
  end if;
  begin
    insert into entry_history (project_id, table_name, row_id, op, old_row)
    values ('00000000-0000-0000-0000-00000000a0d1', 'site_expenses', gen_random_uuid(), 'update', '{}');
    raise exception 'history was written by hand';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from entry_history;
    raise exception 'history was deleted';
  exception when insufficient_privilege then null;
  end;
end $$;

-- The accounts person reads it; the supervisor and an outsider don't.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000d3');
do $$ begin
  if (select count(*) from entry_history) <> 1 then raise exception 'accounts should read the history'; end if;
end $$;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000d2');
do $$ begin
  if exists (select 1 from entry_history) then raise exception 'a site engineer read the history'; end if;
end $$;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000d4');
do $$ begin
  if exists (select 1 from entry_history) then raise exception 'an outsider read the history'; end if;
end $$;

-- A delete keeps the row as it was.
reset role;
delete from site_expenses where id = '00000000-0000-0000-0000-00000000ed01';
do $$ begin
  if not exists (select 1 from entry_history where op = 'delete' and new_row is null
                   and (old_row->>'amount')::numeric = 1500) then
    raise exception 'a delete left no history';
  end if;
  if not exists (select 1 from sync_changes where table_name = 'entry_history') then
    raise exception 'history is not in the change log';
  end if;
end $$;

-- Deleting a whole site with entries still works.
insert into site_expenses (id, project_id, category, amount, incurred_on, recorded_by)
values ('00000000-0000-0000-0000-00000000ed02', '00000000-0000-0000-0000-00000000a0d2', 'Petty cash', 100,
        current_date, '00000000-0000-0000-0000-0000000000d2');
delete from projects where id = '00000000-0000-0000-0000-00000000a0d2';
do $$ begin
  raise notice 'entry_history_test: OK';
end $$;

rollback;
