-- A tool cannot be issued while it is already out.
--
-- The phone refuses it ("This tool is already out. Take it back first."), but a
-- phone only knows the issues it can see, and two sites each see their own. Two
-- phones could each hand over the same drill offline and both sync. Nothing on
-- the server stopped the second, so a tool would be "with" two crews and the
-- return and recovery of its value could not be told apart.
--
-- A new issue is now refused when the tool has an issue that has not been
-- returned, or is in repair or retired. The tool row is locked first, so two
-- issues arriving together cannot both pass. Only new rows are checked (what
-- is already recorded is left as it is). The refused phone keeps the row and
-- shows the reason, as with any other rule. Idempotent. Tested in
-- supabase/tests/tool_not_issued_twice_test.sql.

create or replace function tool_issues_not_double_out()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_condition text;
begin
  select condition into v_condition from tools where id = new.tool_id for update;
  if not found then
    raise exception 'That tool is no longer here.' using errcode = '23514';
  end if;
  if v_condition <> 'in_use' then
    raise exception 'This tool is not in use.' using errcode = '23514';
  end if;
  if exists (select 1 from tool_issues i
              where i.tool_id = new.tool_id and i.returned_on is null and i.id <> new.id) then
    raise exception 'This tool is already out. Take it back first.' using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists tool_issues_not_double_out on tool_issues;
create trigger tool_issues_not_double_out before insert on tool_issues
  for each row execute function tool_issues_not_double_out();
