-- Issue #142: bug reports and "Report this message" reach GitHub without
-- GitHub Actions. The report-to-github edge function claims unfiled
-- reports here, opens one issue each, and writes the issue number back.
-- A claim lasts 10 minutes, so two calls never file the same report and a
-- call that died is retried by the next one. Reports older than 12 months
-- that were filed are deleted (the delete-account page promises that).

alter table bug_reports add column if not exists claimed_at timestamptz;
alter table message_reports add column if not exists claimed_at timestamptz;

create or replace function public.claim_bug_reports(p_limit int default 25)
returns setof bug_reports
language sql
security definer
set search_path = public
as $$
  update bug_reports b set claimed_at = now()
  where b.id in (
    select id from bug_reports
    where github_issue is null and (claimed_at is null or claimed_at < now() - interval '10 minutes')
    order by created_at
    limit greatest(1, least(p_limit, 50))
    for update skip locked)
  returning b.*;
$$;

create or replace function public.claim_message_reports(p_limit int default 25)
returns table (id uuid, created_at timestamptz, message_id uuid, reason text, details text,
               body text, sender_name text, project_id uuid, sent_at timestamptz)
language sql
security definer
set search_path = public
as $$
  with claimed as (
    update message_reports r set claimed_at = now()
    where r.id in (
      select id from message_reports
      where github_issue is null and (claimed_at is null or claimed_at < now() - interval '10 minutes')
      order by created_at
      limit greatest(1, least(p_limit, 50))
      for update skip locked)
    returning r.*)
  select c.id, c.created_at, c.message_id, c.reason, c.details, m.body, m.sender_name, m.project_id, m.created_at
  from claimed c left join project_messages m on m.id = c.message_id
  order by c.created_at;
$$;

create or replace function public.mark_report_filed(p_kind text, p_id uuid, p_issue int)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_kind = 'bug' then
    update bug_reports set github_issue = p_issue where id = p_id;
  elsif p_kind = 'message' then
    update message_reports set github_issue = p_issue where id = p_id;
  else
    raise exception 'unknown report kind %', p_kind;
  end if;
end;
$$;

create or replace function public.purge_old_reports()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  a int;
  b int;
begin
  delete from bug_reports where github_issue is not null and created_at < now() - interval '12 months';
  get diagnostics a = row_count;
  delete from message_reports where github_issue is not null and created_at < now() - interval '12 months';
  get diagnostics b = row_count;
  return a + b;
end;
$$;

revoke all on function public.claim_bug_reports(int) from public, anon, authenticated;
revoke all on function public.claim_message_reports(int) from public, anon, authenticated;
revoke all on function public.mark_report_filed(text, uuid, int) from public, anon, authenticated;
revoke all on function public.purge_old_reports() from public, anon, authenticated;
grant execute on function public.claim_bug_reports(int) to service_role;
grant execute on function public.claim_message_reports(int) to service_role;
grant execute on function public.mark_report_filed(text, uuid, int) to service_role;
grant execute on function public.purge_old_reports() to service_role;
