-- Report filing (20261111160000_report_filing.sql): only the service role
-- claims reports, a claimed report is not handed out twice within 10
-- minutes, a filed one never again, and old filed reports are purged.
\set ON_ERROR_STOP on
begin;

insert into bug_reports (message, app_version) values ('The DPR button does nothing', '1.7.4+19');
insert into bug_reports (message, app_version, created_at, github_issue)
  values ('Old and filed', '1.0.0', now() - interval '13 months', 7);

set local role authenticated;
do $$
begin
  begin
    perform public.claim_bug_reports(10);
    raise exception 'an app user claimed bug reports';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

set local role service_role;
do $$
declare
  r record;
  n int;
begin
  select * into r from public.claim_bug_reports(10);
  if r.message <> 'The DPR button does nothing' then raise exception 'wrong report claimed'; end if;
  select count(*) into n from public.claim_bug_reports(10);
  if n <> 0 then raise exception 'a claimed report was handed out again'; end if;
  perform public.mark_report_filed('bug', r.id, 501);
  if (select github_issue from bug_reports where id = r.id) <> 501 then raise exception 'issue not recorded'; end if;
  if public.purge_old_reports() <> 1 then raise exception 'the 13-month-old filed report should go'; end if;
end $$;
reset role;

-- An abandoned claim is retried after 10 minutes.
insert into bug_reports (message, claimed_at) values ('Claimed by a call that died', now() - interval '11 minutes');
set local role service_role;
do $$
begin
  if not exists (select 1 from public.claim_bug_reports(10) where message = 'Claimed by a call that died') then
    raise exception 'an abandoned claim was not retried';
  end if;
  if exists (select 1 from public.claim_message_reports(10)) then raise exception 'no message reports exist'; end if;
  raise notice 'report filing checks passed';
end $$;
reset role;

rollback;
