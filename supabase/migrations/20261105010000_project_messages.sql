-- Per-project team chat (the "WhatsApp group per site" every competitor
-- either is, like Kraaft, or sits next to). Synced through the same outbox
-- as every other table; live delivery via the Realtime publication below.
-- Messages are append-only: no update/delete policy, so a sent message is
-- an auditable site record, the way a DPR is.

create table project_messages (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  sender_id uuid not null references auth.users(id),
  sender_name text not null check (char_length(sender_name) between 1 and 120),
  body text not null check (char_length(body) between 1 and 4000),
  created_at timestamptz not null default now()
);

create index project_messages_project_created_idx on project_messages (project_id, created_at);

alter table project_messages enable row level security;

revoke all on table project_messages from anon, authenticated;
grant select, insert on table project_messages to authenticated;
grant all on table project_messages to service_role;

create policy "project members can read messages" on project_messages for select
  to authenticated using ((select has_project_access(project_id)));

-- sender_id must be the caller: nobody can post as a colleague.
create policy "project members can post as themselves" on project_messages for insert
  to authenticated with check (
    sender_id = (select auth.uid())
    and (select has_project_access(project_id))
  );

alter publication supabase_realtime add table project_messages;
