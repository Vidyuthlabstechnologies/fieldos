-- Real RLS isolation test. Not a claim -- run this and read the actual
-- output. Two fake companies, each with their own owner user and project;
-- proves a user authenticated as company A can see ONLY company A's data,
-- never company B's, when queried through RLS (role 'authenticated',
-- simulating a real Supabase JWT via request.jwt.claims). SET LOCAL only
-- takes effect inside an explicit transaction -- every authenticated block
-- below is wrapped in BEGIN/COMMIT for that reason (a first pass without
-- this wrapping silently no-op'd every SET LOCAL, which is exactly the
-- kind of bug this whole exercise exists to catch before trusting anything).

\echo '=== SETUP: bypass RLS (postgres role) to seed two isolated companies ==='
set role postgres;

insert into auth.users (id, email, encrypted_password, email_confirmed_at, aud, role)
values
  ('11111111-1111-1111-1111-111111111111', 'owner-a@test.local', 'x', now(), 'authenticated', 'authenticated'),
  ('22222222-2222-2222-2222-222222222222', 'owner-b@test.local', 'x', now(), 'authenticated', 'authenticated'),
  ('33333333-3333-3333-3333-333333333333', 'engineer-a@test.local', 'x', now(), 'authenticated', 'authenticated')
on conflict (id) do nothing;

insert into companies (id, name) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Company A'),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'Company B')
on conflict (id) do nothing;

insert into company_members (company_id, user_id, role) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'owner'),
  ('bbbbbbbb-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'owner'),
  ('aaaaaaaa-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', 'site_engineer')
on conflict do nothing;

insert into projects (id, company_id, name, status) values
  ('aaaaaaaa-0000-0000-0000-000000000010', 'aaaaaaaa-0000-0000-0000-000000000001', 'Project A1', 'active'),
  ('bbbbbbbb-0000-0000-0000-000000000010', 'bbbbbbbb-0000-0000-0000-000000000001', 'Project B1', 'active')
on conflict (id) do nothing;

insert into project_members (project_id, user_id, role) values
  ('aaaaaaaa-0000-0000-0000-000000000010', '33333333-3333-3333-3333-333333333333', 'site_engineer')
on conflict do nothing;

insert into tasks (project_id, title) values
  ('aaaaaaaa-0000-0000-0000-000000000010', 'Task belonging to A'),
  ('bbbbbbbb-0000-0000-0000-000000000010', 'Task belonging to B')
on conflict do nothing;

insert into vendors (id, company_id, name) values
  ('aaaaaaaa-0000-0000-0000-000000000020', 'aaaaaaaa-0000-0000-0000-000000000001', 'Test Vendor A')
on conflict (id) do nothing;

reset role;

\echo ''
\echo '=== TEST 1: authenticated as Company A owner -- must see ONLY A ==='
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

\echo '-- companies visible to A (expect exactly 1 row: Company A):'
select id, name from companies order by name;

\echo '-- projects visible to A (expect exactly 1 row: Project A1):'
select id, name from projects order by name;

\echo '-- tasks visible to A (expect exactly 1 row: Task belonging to A):'
select project_id, title from tasks order by title;

\echo '-- explicit cross-company probe: can A directly select Company B by id? (expect 0 rows):'
select id, name from companies where id = 'bbbbbbbb-0000-0000-0000-000000000001';

\echo '-- explicit cross-project probe: can A directly select Project B1 by id? (expect 0 rows):'
select id, name from projects where id = 'bbbbbbbb-0000-0000-0000-000000000010';
commit;

\echo ''
\echo '=== TEST 2: authenticated as Company B owner -- must see ONLY B ==='
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

\echo '-- companies visible to B (expect exactly 1 row: Company B):'
select id, name from companies order by name;

\echo '-- projects visible to B (expect exactly 1 row: Project B1):'
select id, name from projects order by name;

\echo '-- tasks visible to B (expect exactly 1 row: Task belonging to B):'
select project_id, title from tasks order by title;

\echo '-- explicit cross-company probe: can B directly select Company A by id? (expect 0 rows):'
select id, name from companies where id = 'aaaaaaaa-0000-0000-0000-000000000001';
commit;

\echo ''
\echo '=== TEST 3: unauthenticated (anon role, no JWT claim at all) -- must see NOTHING ==='
begin;
set local role anon;
\echo '-- companies visible to anon (expect 0 rows or a permission-denied error -- both mean isolation held):'
select id, name from companies;
commit;

\echo ''
\echo '=== TEST 4: mutation policy check -- a plain project member (site_engineer, not owner/PM) cannot create a purchase order ==='
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';
\echo '-- site_engineer attempting to create a purchase order (expect this INSERT to be REJECTED by RLS):'
insert into purchase_orders (project_id, vendor_id, created_by) values
  ('aaaaaaaa-0000-0000-0000-000000000010', 'aaaaaaaa-0000-0000-0000-000000000020', '33333333-3333-3333-3333-333333333333');
rollback;

\echo ''
\echo '=== TEST 5: control check -- the SAME site_engineer CAN read the project (proves TEST 4 rejection was the role-gate, not a broken connection) ==='
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';
\echo '-- projects visible to the site_engineer (expect exactly 1 row: Project A1):'
select id, name from projects order by name;
commit;

\echo ''
\echo '=== DONE ==='
