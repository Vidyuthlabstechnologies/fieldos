-- Step 2 of hiding workers.daily_wage: nobody but the owner, project managers
-- and accounts can read a worker's rate any more.
--
-- Step 1 (20261125150000_worker_wage_rates.sql) added worker_wage_rates(), which
-- returns rates only to those people, and from build 26 the phone reads rates
-- through it and pulls workers without the wage column. Until now the column
-- itself was still readable by every member of a site with a plain
-- `select daily_wage from workers`, a site engineer's included.
--
-- After this, `select *` or `select daily_wage` on workers is refused (42501)
-- for the whole table, which is what an app older than build 26 sends. The
-- minimum build was raised to 26 first (app_config), so such a phone shows the
-- Update banner and keeps its data rather than failing. The production
-- project had no users on older builds when this was run (27 Nov 2026).
--
-- Writes keep working: the insert and update privilege stays on every column
-- (the workers_wage_guard trigger already refuses anyone but owners, project
-- managers and accounts a rate), and the per-row RLS policy is unchanged.
-- Reads of the rate go through worker_wage_rates() only.
-- Tested in supabase/tests/wage_read_closed_test.sql and
-- tests/test_workers_column_grants.py.

revoke select on workers from authenticated;
grant select (id, project_id, name, role, phone, status, created_at) on workers to authenticated;

-- Any later column added to workers must be granted the same way:
--   grant select (new_column) on workers to authenticated;
-- tests/test_workers_column_grants.py fails the build when a migration adds a
-- workers column without that grant, or when the phone's pull-column list
-- (SyncEngine.pullColumns) no longer matches the granted columns.
