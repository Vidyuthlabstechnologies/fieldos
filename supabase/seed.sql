-- FieldOS RLS Verification Seed Script
-- Run with: psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/seed.sql
-- This script tests that RLS properly isolates data between companies.

-- ============================================================================
-- SETUP: Create two test users in auth.users (Supabase local allows direct insert)
-- ============================================================================

-- User A (Company A owner)
insert into auth.users (id, email, encrypted_password, email_confirmed_at, raw_user_meta_data, created_at, updated_at, role, aud)
values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'owner-a@test.com', 'dummy-hash', now(), '{"name": "Owner A"}', now(), now(), 'authenticated', 'authenticated')
on conflict (id) do nothing;

-- User B (Company B owner)
insert into auth.users (id, email, encrypted_password, email_confirmed_at, raw_user_meta_data, created_at, updated_at, role, aud)
values
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'owner-b@test.com', 'dummy-hash', now(), '{"name": "Owner B"}', now(), now(), 'authenticated', 'authenticated')
on conflict (id) do nothing;

-- User C (Company A project member, site_engineer) - NOT a company member
insert into auth.users (id, email, encrypted_password, email_confirmed_at, raw_user_meta_data, created_at, updated_at, role, aud)
values
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'engineer-a@test.com', 'dummy-hash', now(), '{"name": "Engineer A"}', now(), now(), 'authenticated', 'authenticated')
on conflict (id) do nothing;

-- User D (Company B project member, site_engineer) - NOT a company member
insert into auth.users (id, email, encrypted_password, email_confirmed_at, raw_user_meta_data, created_at, updated_at, role, aud)
values
    ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'engineer-b@test.com', 'dummy-hash', now(), '{"name": "Engineer B"}', now(), now(), 'authenticated', 'authenticated')
on conflict (id) do nothing;

-- ============================================================================
-- CREATE COMPANIES & MEMBERSHIPS
-- ============================================================================

-- Company A
insert into companies (id, name)
values ('11111111-1111-1111-1111-111111111111', 'Company A Construction')
on conflict (id) do nothing;

insert into company_members (id, company_id, user_id, role)
values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'owner')
on conflict (company_id, user_id) do nothing;

-- Company B
insert into companies (id, name)
values ('22222222-2222-2222-2222-222222222222', 'Company B Builders')
on conflict (id) do nothing;

insert into company_members (id, company_id, user_id, role)
values
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'owner')
on conflict (company_id, user_id) do nothing;

-- ============================================================================
-- CREATE PROJECTS
-- ============================================================================

-- Company A's project
insert into projects (id, company_id, name, client_name, status)
values ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', 'Project Alpha', 'Client Alpha', 'active')
on conflict (id) do nothing;

insert into project_members (id, project_id, user_id, role)
values
    ('cccccccc-cccc-cccc-cccc-ccccccccc001', '33333333-3333-3333-3333-333333333333', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'owner'),
    ('cccccccc-cccc-cccc-cccc-ccccccccc002', '33333333-3333-3333-3333-333333333333', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'site_engineer')
on conflict (project_id, user_id) do nothing;

-- Company B's project
insert into projects (id, company_id, name, client_name, status)
values ('44444444-4444-4444-4444-444444444444', '22222222-2222-2222-2222-222222222222', 'Project Beta', 'Client Beta', 'active')
on conflict (id) do nothing;

insert into project_members (id, project_id, user_id, role)
values
    ('dddddddd-dddd-dddd-dddd-ddddddddd001', '44444444-4444-4444-4444-444444444444', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'owner'),
    ('dddddddd-dddd-dddd-dddd-ddddddddd002', '44444444-4444-4444-4444-444444444444', 'dddddddd-dddd-dddd-dddd-dddddddddddd', 'site_engineer')
on conflict (project_id, user_id) do nothing;

-- ============================================================================
-- INSERT TEST DATA FOR EACH PROJECT
-- ============================================================================

-- Tasks for Project Alpha (Company A)
insert into tasks (id, project_id, title, status)
values
    ('55555555-5555-5555-5555-555555555555', '33333333-3333-3333-3333-333333333333', 'Task A-1', 'todo'),
    ('55555555-5555-5555-5555-555555555556', '33333333-3333-3333-3333-333333333333', 'Task A-2', 'in_progress')
on conflict (id) do nothing;

-- Tasks for Project Beta (Company B)
insert into tasks (id, project_id, title, status)
values
    ('66666666-6666-6666-6666-666666666666', '44444444-4444-4444-4444-444444444444', 'Task B-1', 'todo'),
    ('66666666-6666-6666-6666-666666666667', '44444444-4444-4444-4444-444444444444', 'Task B-2', 'done')
on conflict (id) do nothing;

-- DPR Entries for Project Alpha
insert into dpr_entries (id, project_id, created_by, entry_date, work_summary, manpower_count)
values
    ('77777777-7777-7777-7777-777777777777', '33333333-3333-3333-3333-333333333333', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '2026-08-20', 'Foundation work completed', 10),
    ('77777777-7777-7777-7777-777777777778', '33333333-3333-3333-3333-333333333333', 'cccccccc-cccc-cccc-cccc-cccccccccccc', '2026-08-21', 'Column reinforcement', 8)
on conflict (id) do nothing;

-- DPR Entries for Project Beta
insert into dpr_entries (id, project_id, created_by, entry_date, work_summary, manpower_count)
values
    ('88888888-8888-8888-8888-888888888888', '44444444-4444-4444-4444-444444444444', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '2026-08-20', 'Slab pouring', 15),
    ('88888888-8888-8888-8888-888888888889', '44444444-4444-4444-4444-444444444444', 'dddddddd-dddd-dddd-dddd-dddddddddddd', '2026-08-21', 'Brickwork started', 12)
on conflict (id) do nothing;

-- Workers for Project Alpha
insert into workers (id, project_id, name, role, daily_wage)
values
    ('99999999-9999-9999-9999-999999999991', '33333333-3333-3333-3333-333333333333', 'Worker A1', 'mason', 500.00),
    ('99999999-9999-9999-9999-999999999992', '33333333-3333-3333-3333-333333333333', 'Worker A2', 'helper', 350.00)
on conflict (id) do nothing;

-- Workers for Project Beta
insert into workers (id, project_id, name, role, daily_wage)
values
    ('99999999-9999-9999-9999-999999999993', '44444444-4444-4444-4444-444444444444', 'Worker B1', 'carpenter', 550.00),
    ('99999999-9999-9999-9999-999999999994', '44444444-4444-4444-4444-444444444444', 'Worker B2', 'electrician', 600.00)
on conflict (id) do nothing;

-- Vendors for Company A
insert into vendors (id, company_id, name, contact_person, phone)
values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa10', '11111111-1111-1111-1111-111111111111', 'Vendor A1', 'Contact A1', '9876543210')
on conflict (id) do nothing;

-- Vendors for Company B
insert into vendors (id, company_id, name, contact_person, phone)
values
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb10', '22222222-2222-2222-2222-222222222222', 'Vendor B1', 'Contact B1', '9876543211')
on conflict (id) do nothing;

-- ============================================================================
-- RESEED COMPLETE. `supabase db reset` runs this automatically every time,
-- so local dev always has a realistic two-company dataset to work against.
-- For a from-scratch RLS isolation proof (not relying on this seed data),
-- see supabase/rls_verification_test.sql.
-- ============================================================================