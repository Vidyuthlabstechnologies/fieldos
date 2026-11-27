-- A shared portal code can be changed, and the people who joined with it removed.
--
-- A site client's, supplier's or sub-contractor's code was permanent: made once,
-- sent on WhatsApp, and good for ever. A homeowner forwarding it to a relative,
-- a supplier who has stopped trading with the builder, a sub-contractor whose
-- contract ended: the builder had no way to end their access except the
-- support desk.
--
-- reset_client_code / reset_supplier_code / reset_subcontractor_code (owner or
-- project manager of the company, like the functions that hand the code out):
--   * always replace the code, so the old one stops working for anyone new;
--   * with p_remove_access = true, also remove everyone who had joined, so
--     their portal sees nothing from the next sync on (what is already on their
--     phone stays there, as with a member who leaves a company).
-- They return the new code. Nothing else about the site, supplier or
-- sub-contractor changes. Idempotent. Tested in
-- supabase/tests/portal_code_reset_test.sql.

create or replace function reset_client_code(p_project_id uuid, p_remove_access boolean default false)
returns text language plpgsql security definer set search_path = public as $$
declare v_company uuid; v_code text;
begin
  select company_id into v_company from projects where id = p_project_id;
  if v_company is null or not is_company_owner_or_pm(v_company) then
    raise exception 'only the owner or a project manager can change a client code' using errcode = '42501';
  end if;
  v_code := new_portal_code();
  insert into client_codes (project_id, code) values (p_project_id, v_code)
    on conflict (project_id) do update set code = excluded.code, created_at = now();
  if coalesce(p_remove_access, false) then
    delete from client_users where project_id = p_project_id;
  end if;
  return v_code;
end $$;

create or replace function reset_supplier_code(p_vendor_id uuid, p_remove_access boolean default false)
returns text language plpgsql security definer set search_path = public as $$
declare v_company uuid; v_code text;
begin
  select company_id into v_company from vendors where id = p_vendor_id;
  if v_company is null or not is_company_owner_or_pm(v_company) then
    raise exception 'only the owner or a project manager can change a supplier code' using errcode = '42501';
  end if;
  v_code := new_portal_code();
  insert into supplier_codes (vendor_id, code) values (p_vendor_id, v_code)
    on conflict (vendor_id) do update set code = excluded.code, created_at = now();
  if coalesce(p_remove_access, false) then
    delete from supplier_users where vendor_id = p_vendor_id;
  end if;
  return v_code;
end $$;

create or replace function reset_subcontractor_code(p_subcontractor_id uuid, p_remove_access boolean default false)
returns text language plpgsql security definer set search_path = public as $$
declare v_company uuid; v_code text;
begin
  select company_id into v_company from subcontractors where id = p_subcontractor_id;
  if v_company is null or not is_company_owner_or_pm(v_company) then
    raise exception 'only the owner or a project manager can change a subcontractor code' using errcode = '42501';
  end if;
  v_code := new_portal_code();
  insert into subcontractor_codes (subcontractor_id, code) values (p_subcontractor_id, v_code)
    on conflict (subcontractor_id) do update set code = excluded.code, created_at = now();
  if coalesce(p_remove_access, false) then
    delete from subcontractor_users where subcontractor_id = p_subcontractor_id;
  end if;
  return v_code;
end $$;

revoke all on function reset_client_code(uuid, boolean), reset_supplier_code(uuid, boolean),
  reset_subcontractor_code(uuid, boolean) from public, anon;
grant execute on function reset_client_code(uuid, boolean), reset_supplier_code(uuid, boolean),
  reset_subcontractor_code(uuid, boolean) to authenticated;
