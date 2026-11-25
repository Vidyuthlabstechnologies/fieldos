-- Step 2 of hiding workers.daily_wage. DO NOT COPY INTO supabase/migrations
-- UNTIL every phone still in use is on build 26 (1.8.1) or newer:
-- afterwards, `select * from workers` fails with 42501 for the whole table,
-- which is what an older phone sends. The cut-over order is in
-- docs/SUPABASE_PRODUCTION_RUNBOOK.md ("Wage rates: the two-step cut-over").
--
-- Writes keep working: the insert/update privilege stays on every column
-- (the workers_wage_guard trigger already refuses anyone but owners,
-- project managers and accounts a rate), and the per-row RLS policy is
-- unchanged. Reads of the rate go through worker_wage_rates() only.

revoke select on workers from authenticated;
grant select (id, project_id, name, role, phone, status, created_at) on workers to authenticated;

-- Any later column added to workers must be granted the same way:
--   grant select (new_column) on workers to authenticated;
-- A test (tools/ or fieldos_mobile/test/wage_privacy_test.dart) fails the
-- build when a migration adds a workers column without this note.
