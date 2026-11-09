-- Supabase's default privileges give anon and authenticated ALL on every
-- new public table. Most migrations revoke that and grant back only what
-- the app uses, but site_attendance_marks and site_notes did not, so anon
-- held select/insert/update/delete/truncate there and authenticated held
-- delete/truncate. Row level security limits the row-level verbs, but not
-- TRUNCATE, so close it at the grant level too.

-- Nothing in the app signs in as anon except bug reports (insert only).
revoke all on table site_attendance_marks, site_notes from anon;
revoke all on table site_attendance_marks, site_notes from authenticated;
grant select, insert, update on site_attendance_marks, site_notes to authenticated;

-- No public table should ever be truncated, or have triggers or foreign
-- keys added, by an app user.
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('revoke truncate, references, trigger on table public.%I from anon, authenticated', t);
  end loop;
end $$;

-- Future tables start closed to anon; each migration grants what it needs.
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke truncate, references, trigger on tables from authenticated;
