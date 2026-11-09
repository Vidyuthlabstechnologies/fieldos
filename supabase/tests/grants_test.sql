-- Fails (psql exits non-zero with ON_ERROR_STOP) if an app role holds a
-- table privilege that row level security cannot limit, or anon can reach
-- anything but bug reports. Run after `supabase start`:
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/grants_test.sql
do $$
declare bad text;
begin
  select string_agg(format('%s %s on %s', grantee, privilege_type, table_name), '; ')
    into bad
    from information_schema.role_table_grants
   where table_schema = 'public'
     and grantee in ('anon', 'authenticated')
     and (privilege_type in ('TRUNCATE', 'REFERENCES', 'TRIGGER')
          or (grantee = 'anon' and not (table_name = 'bug_reports' and privilege_type = 'INSERT')));
  if bad is not null then
    raise exception 'App roles hold grants they should not: %', bad;
  end if;

  select string_agg(c.relname, ', ')
    into bad
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;
  if bad is not null then
    raise exception 'Public tables without row level security: %', bad;
  end if;

  select string_agg(p.proname, ', ')
    into bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) x where x like 'search_path=%');
  if bad is not null then
    raise exception 'SECURITY DEFINER functions without a fixed search_path: %', bad;
  end if;
  raise notice 'grants_test: OK';
end $$;
