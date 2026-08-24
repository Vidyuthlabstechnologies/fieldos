-- Documents sync needs the files themselves to move between devices, not
-- just metadata rows -- that's Supabase Storage's job. Private bucket;
-- object path convention is {projectId}/{documentId}.
insert into storage.buckets (id, name, public)
values ('documents', 'documents', false)
on conflict (id) do nothing;

-- storage.objects has its own RLS, separate from the public.documents row
-- policies. Access mirrors the documents table exactly: project membership
-- for everything, derived from the object path's first folder segment.
create policy "project members can read document files" on storage.objects for select
  to authenticated
  using (bucket_id = 'documents'
    and has_project_access(((storage.foldername(name))[1])::uuid));
create policy "project members can upload document files" on storage.objects for insert
  to authenticated
  with check (bucket_id = 'documents'
    and has_project_access(((storage.foldername(name))[1])::uuid));
create policy "project members can replace document files" on storage.objects for update
  to authenticated
  using (bucket_id = 'documents'
    and has_project_access(((storage.foldername(name))[1])::uuid));
create policy "project members can delete document files" on storage.objects for delete
  to authenticated
  using (bucket_id = 'documents'
    and has_project_access(((storage.foldername(name))[1])::uuid));
