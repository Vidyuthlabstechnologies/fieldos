-- In-app bug reports. Anyone using the app can send one, signed in to the
-- cloud or not; nobody can read them back through the API. The
-- bug-reports workflow (.github/workflows/bug-reports.yml) copies new ones
-- into GitHub issues with the service role and records the issue number.

create table if not exists bug_reports (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  user_id uuid default auth.uid() references auth.users(id) on delete set null,
  message text not null check (char_length(message) between 5 and 5000),
  contact_email text check (contact_email is null or char_length(contact_email) <= 200),
  app_version text check (char_length(app_version) <= 40),
  platform text check (char_length(platform) <= 200),
  recent_errors text check (char_length(recent_errors) <= 8000),
  github_issue int
);

create index if not exists bug_reports_unfiled on bug_reports (created_at) where github_issue is null;

alter table bug_reports enable row level security;

create policy "anyone can send a bug report" on bug_reports for insert
  to anon, authenticated
  with check (github_issue is null and (user_id is null or user_id = auth.uid()));

grant insert on bug_reports to anon, authenticated;
