-- Checks that every foreign key on a project_id or company_id column, and the
-- parent links the app lists by, has an index that starts with it.
-- (20261128140000_index_foreign_keys.sql.) Run after `supabase start`:
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/foreign_key_indexes_test.sql
do $$
declare missing text;
begin
  select string_agg(tbl || '.' || col, ', ' order by tbl, col) into missing
    from (
      select cl.relname as tbl, a.attname as col
        from pg_constraint c
        join pg_class cl on cl.oid = c.conrelid
        join pg_namespace n on n.oid = cl.relnamespace
        join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
       where c.contype = 'f' and n.nspname = 'public'
         and array_length(c.conkey, 1) = 1
         and a.attname in ('project_id', 'company_id')
         and not exists (select 1 from pg_index i where i.indrelid = c.conrelid and i.indkey[0] = c.conkey[1])
    ) x;
  if missing is not null then
    raise exception 'foreign keys on project_id or company_id with no index starting with them: %', missing;
  end if;
  raise notice 'foreign_key_indexes_test: OK';
end $$;
