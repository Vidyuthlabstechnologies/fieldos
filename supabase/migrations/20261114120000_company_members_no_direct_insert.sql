-- Company membership is written only by the security-definer functions:
-- ensure_company (the creator becomes owner), join_company (the join code,
-- as a site engineer), set_member_role and remove_member (the owner), and
-- delete_my_account. The initial schema also left a table policy, "owner/pm
-- can add members", that let any owner or project manager insert a row for
-- any account with any role. A project manager could make a second account
-- of theirs the company's owner (then change roles, remove people, reset the
-- join code), and put anyone under the company's paid plan without the join
-- code. The app never inserts into company_members directly.
--
-- Test: supabase/tests/company_plans_test.sql.

drop policy if exists "owner/pm can add members" on company_members;
revoke insert, update, delete on table company_members from anon, authenticated;
