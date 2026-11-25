-- Step 1 of restoring a tools/db_backup.py backup into a fresh Supabase
-- project: empty what the migrations put there (app_config has a row from
-- its migration, which would collide with the backup's) before loading
-- data.sql. See docs/SUPABASE_PRODUCTION_RUNBOOK.md, "Restoring a backup".
-- Tested 26 Nov 2026 on a local stack: after clear + load, company, project,
-- task, expense and user counts matched the source exactly.
SET session_replication_role = replica;
DO $$ declare r record; begin
  for r in select schemaname, tablename from pg_tables
           where (schemaname = 'public')
              or (schemaname = 'auth' and tablename not in ('schema_migrations')) loop
    execute format('truncate table %I.%I cascade', r.schemaname, r.tablename);
  end loop;
end $$;
