-- is_company_owner_or_pm() returned NULL, not false, for someone with no
-- role in the company (company_role() finds no row). Inside RLS that is
-- harmless, but a function guard written `if not is_company_owner_or_pm(..)`
-- then skips its exception for an outsider, because `not NULL` is NULL.
-- That let any signed-in user ask for a subcontractor's or supplier's
-- access code knowing only its id. Always answer true or false.
create or replace function is_company_owner_or_pm(p_company_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(company_role(p_company_id) in ('owner', 'project_manager'), false);
$$;
