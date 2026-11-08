-- Bug reports hold other people's device details and free text. The app
-- only ever inserts them (without reading the row back), and the triage
-- job reads them with the service role. Supabase gives anon and
-- authenticated every privilege on new public tables by default; RLS
-- already hid the rows, but take the read, change and delete rights away
-- too, so a missing or wrong policy can never expose them.
revoke select, update, delete, truncate on table bug_reports from anon, authenticated;
grant insert on bug_reports to anon, authenticated;
