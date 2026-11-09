-- "Report this message" in project chat (Google Play's user-generated
-- content policy). A member can report a colleague's message once; the
-- report is write-only like bug_reports: nobody reads it back through the
-- API, and the bug-reports workflow files it as a GitHub issue labelled
-- message-report for the FieldOS team to review within 24 hours.

create table if not exists message_reports (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  message_id uuid not null references project_messages(id) on delete cascade,
  reporter_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  reason text not null check (reason in ('abuse', 'spam', 'inappropriate', 'other')),
  details text check (details is null or char_length(details) <= 1000),
  github_issue int,
  unique (message_id, reporter_id)
);

create index if not exists message_reports_unfiled on message_reports (created_at) where github_issue is null;

alter table message_reports enable row level security;

revoke all on table message_reports from anon, authenticated;
grant insert on table message_reports to authenticated;
grant all on table message_reports to service_role;

-- Only as yourself, only a message you can see, and only someone else's.
create policy "members can report a colleague's message" on message_reports for insert
  to authenticated with check (
    reporter_id = (select auth.uid())
    and github_issue is null
    and exists (
      select 1 from project_messages m
      where m.id = message_id
        and m.sender_id <> (select auth.uid())
        and (select has_project_access(m.project_id))
    )
  );
