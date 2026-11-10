-- DPR photos and expense bills reach the rest of the team (audit P1,
-- 2026-11-10). Until now both stayed on the phone that took them: the row
-- synced, the evidence did not, so a second phone saw a report or an
-- expense with nothing behind it. Files go to the existing private
-- `documents` Storage bucket, whose policies already key access off the
-- object path's first folder (the project id):
--   {projectId}/dpr-photos/{photoId}.{ext}
--   {projectId}/expense-bills/{attachmentId}.{ext}
-- The phone uploads the file before the row (SyncEngine.fileColumns), so a
-- visible row always has a file behind it.

-- dpr_photos has existed since the first schema with read/add policies.
-- Adding now also requires the file to sit under the report's own site.
drop policy if exists "project members can add dpr photos" on dpr_photos;
create policy "project members can add dpr photos" on dpr_photos for insert
  to authenticated with check (
    (select has_project_access((select project_id from dpr_entries where id = dpr_entry_id)))
    and split_part(photo_path, '/', 1) = (select project_id::text from dpr_entries where id = dpr_entry_id));

-- Taking a photo off a report is allowed for whoever can see the report.
drop policy if exists "project members can remove dpr photos" on dpr_photos;
create policy "project members can remove dpr photos" on dpr_photos for delete
  to authenticated using ((select has_project_access(
    (select project_id from dpr_entries where id = dpr_entry_id))));

create table if not exists expense_attachments (
  id uuid primary key,
  expense_id uuid not null references site_expenses(id) on delete cascade,
  file_path text not null check (char_length(file_path) <= 300),
  mime_type text not null check (char_length(mime_type) <= 100),
  uploaded_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists expense_attachments_expense_idx on expense_attachments (expense_id);

alter table expense_attachments enable row level security;
revoke all on table expense_attachments from anon, authenticated;
grant select, insert, delete on table expense_attachments to authenticated;

drop policy if exists "project members read expense bills" on expense_attachments;
create policy "project members read expense bills" on expense_attachments for select
  to authenticated using ((select has_project_access(
    (select project_id from site_expenses where id = expense_id))));

-- The file must sit under the expense's own site, so a bill can't be
-- pointed at another company's storage folder.
drop policy if exists "project members add expense bills" on expense_attachments;
create policy "project members add expense bills" on expense_attachments for insert
  to authenticated with check (
    (select has_project_access((select project_id from site_expenses where id = expense_id)))
    and split_part(file_path, '/', 1) = (select project_id::text from site_expenses where id = expense_id));

-- Same people who may correct the expense may take a bill off it.
drop policy if exists "writer or owner/PM removes expense bills" on expense_attachments;
create policy "writer or owner/PM removes expense bills" on expense_attachments for delete
  to authenticated using (exists (
    select 1 from site_expenses e
     where e.id = expense_id
       and (select has_project_access(e.project_id))
       and (e.recorded_by = (select auth.uid()) or (select is_project_owner_or_pm(e.project_id)))));
