-- The site cash book: the owner/PM or the site's accounts person hands out,
-- takes back and counts cash, as themselves; the holder reads only their
-- own book; a site engineer can't write it; nobody outside the company is
-- a holder; entries are only ever cancelled, never changed or un-cancelled;
-- an outsider sees nothing. Everything rolls back.
\set ON_ERROR_STOP on
begin;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000f1', 'pm@example.com'),
  ('00000000-0000-0000-0000-0000000000f2', 'sup@example.com'),
  ('00000000-0000-0000-0000-0000000000f3', 'acc@example.com'),
  ('00000000-0000-0000-0000-0000000000f4', 'other-sup@example.com'),
  ('00000000-0000-0000-0000-0000000000f5', 'outsider@example.com');
insert into companies (id, name) values ('00000000-0000-0000-0000-00000000c0f1', 'Sai Constructions');
insert into company_members (company_id, user_id, role) values
  ('00000000-0000-0000-0000-00000000c0f1', '00000000-0000-0000-0000-0000000000f1', 'project_manager'),
  ('00000000-0000-0000-0000-00000000c0f1', '00000000-0000-0000-0000-0000000000f2', 'site_engineer'),
  ('00000000-0000-0000-0000-00000000c0f1', '00000000-0000-0000-0000-0000000000f3', 'site_engineer'),
  ('00000000-0000-0000-0000-00000000c0f1', '00000000-0000-0000-0000-0000000000f4', 'site_engineer');
insert into projects (id, company_id, name) values
  ('00000000-0000-0000-0000-00000000a0f1', '00000000-0000-0000-0000-00000000c0f1', 'Kompally Villas');
-- The accounts person is a site engineer in the company, "accounts" on this site.
insert into project_members (project_id, user_id, role) values
  ('00000000-0000-0000-0000-00000000a0f1', '00000000-0000-0000-0000-0000000000f3', 'accounts');

create or replace function pg_temp.as_user(u uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u::text, true);
$$;

set local role authenticated;

-- The PM gives the supervisor ₹20,000 and the other supervisor ₹5,000.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000f1');
insert into site_cash_moves (id, project_id, holder_id, kind, amount, moved_on, recorded_by)
values ('00000000-0000-0000-0000-00000000ca01', '00000000-0000-0000-0000-00000000a0f1',
        '00000000-0000-0000-0000-0000000000f2', 'given', 20000, current_date, '00000000-0000-0000-0000-0000000000f1'),
       ('00000000-0000-0000-0000-00000000ca02', '00000000-0000-0000-0000-00000000a0f1',
        '00000000-0000-0000-0000-0000000000f4', 'given', 5000, current_date, '00000000-0000-0000-0000-0000000000f1');

-- The accounts person counts the supervisor's cash.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000f3');
insert into site_cash_moves (id, project_id, holder_id, kind, amount, moved_on, recorded_by)
values ('00000000-0000-0000-0000-00000000ca03', '00000000-0000-0000-0000-00000000a0f1',
        '00000000-0000-0000-0000-0000000000f2', 'counted', 0, current_date, '00000000-0000-0000-0000-0000000000f3');

do $$
begin
  if (select count(*) from site_cash_moves) <> 3 then
    raise exception 'the accounts person should see every book on the site';
  end if;
end $$;

-- The supervisor reads only their own book, and can't write in it.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000f2');
do $$
begin
  if (select count(*) from site_cash_moves) <> 2
     or exists (select 1 from site_cash_moves where holder_id <> '00000000-0000-0000-0000-0000000000f2') then
    raise exception 'a holder should see only their own book';
  end if;
  begin
    insert into site_cash_moves (id, project_id, holder_id, kind, amount, moved_on, recorded_by)
    values ('00000000-0000-0000-0000-00000000ca04', '00000000-0000-0000-0000-00000000a0f1',
            '00000000-0000-0000-0000-0000000000f2', 'returned', 100, current_date, '00000000-0000-0000-0000-0000000000f2');
    raise exception 'a site engineer wrote in the cash book';
  exception when insufficient_privilege then null;
  end;
  update site_cash_moves set voided = true, void_reason = 'mine' where id = '00000000-0000-0000-0000-00000000ca01';
  if (select voided from site_cash_moves where id = '00000000-0000-0000-0000-00000000ca01') then
    raise exception 'a holder cancelled an entry';
  end if;
end $$;

-- The PM can't write as someone else, nor give cash to an outsider.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000f1');
do $$
begin
  begin
    insert into site_cash_moves (id, project_id, holder_id, kind, amount, moved_on, recorded_by)
    values ('00000000-0000-0000-0000-00000000ca05', '00000000-0000-0000-0000-00000000a0f1',
            '00000000-0000-0000-0000-0000000000f2', 'given', 100, current_date, '00000000-0000-0000-0000-0000000000f3');
    raise exception 'an entry was written as someone else';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into site_cash_moves (id, project_id, holder_id, kind, amount, moved_on, recorded_by)
    values ('00000000-0000-0000-0000-00000000ca06', '00000000-0000-0000-0000-00000000a0f1',
            '00000000-0000-0000-0000-0000000000f5', 'given', 100, current_date, '00000000-0000-0000-0000-0000000000f1');
    raise exception 'cash was given to someone outside the company';
  exception when raise_exception then
    if sqlerrm not like '%not on this company%' then raise; end if;
  end;
  begin
    insert into site_cash_moves (id, project_id, holder_id, kind, amount, moved_on, recorded_by)
    values ('00000000-0000-0000-0000-00000000ca07', '00000000-0000-0000-0000-00000000a0f1',
            '00000000-0000-0000-0000-0000000000f2', 'given', 0, current_date, '00000000-0000-0000-0000-0000000000f1');
    raise exception 'nothing was given';
  exception when check_violation then null;
  end;
end $$;

-- Cancelling keeps the amount, date and holder as they were, and stays.
update site_cash_moves set voided = true, void_reason = 'Typed wrong', amount = 1, holder_id = '00000000-0000-0000-0000-0000000000f4'
 where id = '00000000-0000-0000-0000-00000000ca01';
do $$
declare r site_cash_moves;
begin
  select * into r from site_cash_moves where id = '00000000-0000-0000-0000-00000000ca01';
  if not r.voided or r.amount <> 20000 or r.holder_id <> '00000000-0000-0000-0000-0000000000f2' then
    raise exception 'a cancel changed more than the cancel';
  end if;
  begin
    update site_cash_moves set voided = false where id = '00000000-0000-0000-0000-00000000ca01';
    raise exception 'a cancelled entry came back';
  exception when raise_exception then
    if sqlerrm not like '%stays cancelled%' then raise; end if;
  end;
  begin
    delete from site_cash_moves where id = '00000000-0000-0000-0000-00000000ca02';
    raise exception 'a cash entry was deleted';
  exception when insufficient_privilege then null;
  end;
end $$;

-- An outsider sees nothing.
select pg_temp.as_user('00000000-0000-0000-0000-0000000000f5');
do $$
begin
  if exists (select 1 from site_cash_moves) then raise exception 'an outsider saw the cash book'; end if;
end $$;

reset role;
do $$
begin
  if not exists (select 1 from sync_changes where table_name = 'site_cash_moves') then
    raise exception 'cash book changes are not in the change log';
  end if;
  raise notice 'cash_book_test: OK';
end $$;

rollback;
