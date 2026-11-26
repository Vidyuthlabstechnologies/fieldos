-- Change history for wage rates, attendance marks and purchase orders and
-- requests (follows 20261111120000_entry_history.sql).
--
-- The history trigger covered eight money tables but not the rows where a
-- quiet edit pays best: a worker's daily wage, who was marked present, and
-- what a purchase order or request said. Each change or delete of one now
-- keeps the row as it was and as it became, and who did it. Same rules as
-- before: only the trigger writes history, and only a site's owner, manager
-- and accounts person read it (so wage history is seen by exactly the people
-- who may see wages).
--
-- Additive and idempotent. Tested in supabase/tests/entry_history_test.sql.
do $$
declare t text;
begin
  foreach t in array array['workers', 'site_attendance_marks', 'purchase_orders', 'purchase_requisitions']
  loop
    if to_regclass(t) is not null then
      execute format('drop trigger if exists %I on %I', t || '_entry_history', t);
      execute format('create trigger %I after update or delete on %I for each row execute function record_entry_history()',
                     t || '_entry_history', t);
    end if;
  end loop;
end $$;
