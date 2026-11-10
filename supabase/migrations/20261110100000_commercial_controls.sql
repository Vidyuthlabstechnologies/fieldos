-- Commercial controls (app schema v16, 2026-11-10): FOS-201 to FOS-204.
--
-- One chain a commercial manager can follow from what was agreed to what
-- was paid:
--
--   work order (agreed quantity and rate, the baseline)
--     -> work claim (a subcontractor's completed quantity, with photos)
--     -> work certification (the engineer's accepted / rejected quantity)
--     -> variation (a scope change, e.g. the claim's quantity beyond the
--        order) -> variation decision (approved or rejected, once)
--     -> cost code (original budget, approved changes, commitments,
--        actuals, cost to complete)
--   and commercial exception actions (who owns an exception, by when,
--   and what was decided).
--
-- Rules the server enforces, so a phone that is offline, out of date or
-- tampered with can't break them:
--  - Claims, certifications, variation decisions and exception actions
--    are insert-only: the record of who claimed, accepted, rejected and
--    approved what cannot be rewritten.
--  - The same quantity can't be certified twice: a claim's accepted plus
--    rejected quantity never exceeds what was claimed, and a work order's
--    accepted quantity never exceeds its agreed quantity plus approved
--    variations (checked under a row lock on the work order, so two
--    engineers syncing at once can't both take the last 20 m2).
--  - Only the owner or a project manager decides a variation, edits
--    budgets, or resolves an exception.
--  - A subcontractor gets restricted access: they join with a code the
--    owner or PM gives them (subcontractor_users), are NOT company
--    members, and see only their own firm's work orders, claims and the
--    outcome of those claims. They can submit claims and nothing else.

-- --- Work orders get a quantity, unit and rate ------------------------------

create table if not exists cost_codes (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  code text not null check (char_length(code) between 1 and 30),
  name text not null check (char_length(name) between 1 and 200),
  original_budget numeric(14, 2) not null default 0 check (original_budget >= 0),
  -- Still to be bought or let beyond what is already committed.
  uncommitted_estimate numeric(14, 2) not null default 0 check (uncommitted_estimate >= 0),
  sort_order int not null default 0,
  created_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (project_id, code)
);
create index if not exists cost_codes_project_idx on cost_codes (project_id);

alter table work_orders add column if not exists unit text check (char_length(unit) <= 20);
alter table work_orders add column if not exists contract_qty numeric(14, 3) check (contract_qty is null or contract_qty >= 0);
alter table work_orders add column if not exists rate numeric(14, 2) check (rate is null or rate >= 0);
alter table work_orders add column if not exists cost_code_id uuid references cost_codes(id) on delete set null;
alter table purchase_orders add column if not exists cost_code_id uuid references cost_codes(id) on delete set null;
alter table site_expenses add column if not exists cost_code_id uuid references cost_codes(id) on delete set null;

-- The baseline stays as agreed. An approved variation adds to the order
-- (the phone shows both); changing the agreed quantity or rate itself
-- once work has been certified would rewrite history, so it is refused.
create or replace function work_orders_keep_baseline()
returns trigger language plpgsql as $$
begin
  if (new.contract_qty is distinct from old.contract_qty or new.rate is distinct from old.rate
      or new.agreed_amount is distinct from old.agreed_amount)
     and exists (select 1 from work_certifications c where c.work_order_id = new.id) then
    raise exception 'work order % already has certified work; record a variation instead', new.id
      using errcode = 'P0001';
  end if;
  return new;
end $$;

-- --- Subcontractor access ---------------------------------------------------

create table if not exists subcontractor_users (
  subcontractor_id uuid not null references subcontractors(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (subcontractor_id, user_id)
);
create index if not exists subcontractor_users_user_idx on subcontractor_users (user_id);
alter table subcontractor_users enable row level security;
revoke all on table subcontractor_users from anon, authenticated;
grant select on table subcontractor_users to authenticated;
drop policy if exists "see your own subcontractor links" on subcontractor_users;
create policy "see your own subcontractor links" on subcontractor_users for select
  to authenticated using (user_id = (select auth.uid())
    or (select is_company_owner_or_pm((select company_id from subcontractors s where s.id = subcontractor_id))));

-- The code a subcontractor types in. Kept off the synced subcontractors
-- columns on purpose: only the owner or PM asks for it.
create table if not exists subcontractor_codes (
  subcontractor_id uuid primary key references subcontractors(id) on delete cascade,
  code text not null unique,
  created_at timestamptz not null default now()
);
alter table subcontractor_codes enable row level security;
revoke all on table subcontractor_codes from anon, authenticated;

create or replace function is_my_subcontractor(p_subcontractor_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (select 1 from subcontractor_users
                  where subcontractor_id = p_subcontractor_id and user_id = (select auth.uid()));
$$;

create or replace function is_my_work_order(p_work_order_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (select 1 from work_orders w join subcontractor_users su on su.subcontractor_id = w.subcontractor_id
                  where w.id = p_work_order_id and su.user_id = (select auth.uid()));
$$;

create or replace function is_subcontractor_on_project(p_project_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (select 1 from work_orders w join subcontractor_users su on su.subcontractor_id = w.subcontractor_id
                  where w.project_id = p_project_id and su.user_id = (select auth.uid()));
$$;
revoke all on function is_my_subcontractor(uuid), is_my_work_order(uuid), is_subcontractor_on_project(uuid)
  from public, anon;
grant execute on function is_my_subcontractor(uuid), is_my_work_order(uuid), is_subcontractor_on_project(uuid)
  to authenticated;

-- Owner or PM: the code for one subcontractor (made the first time).
create or replace function subcontractor_access_code(p_subcontractor_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_company uuid;
  v_code text;
begin
  select company_id into v_company from subcontractors where id = p_subcontractor_id;
  if v_company is null or not is_company_owner_or_pm(v_company) then
    raise exception 'only the owner or a project manager can share a subcontractor code' using errcode = '42501';
  end if;
  select code into v_code from subcontractor_codes where subcontractor_id = p_subcontractor_id;
  if v_code is null then
    loop
      v_code := new_join_code();
      exit when not exists (select 1 from subcontractor_codes where code = v_code)
                and not exists (select 1 from companies where join_code = v_code);
    end loop;
    insert into subcontractor_codes (subcontractor_id, code) values (p_subcontractor_id, v_code);
  end if;
  return v_code;
end $$;
revoke all on function subcontractor_access_code(uuid) from public, anon;
grant execute on function subcontractor_access_code(uuid) to authenticated;

-- A subcontractor's phone. Same limits as join_company (10 wrong codes an
-- hour, an error object instead of a raise so the attempt is counted).
create or replace function join_as_subcontractor(p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^0-9A-Za-z]', '', 'g'));
  v_sub subcontractors%rowtype;
  v_company companies%rowtype;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if (select count(*) from join_attempts
      where user_id = v_uid and attempted_at > now() - interval '1 hour') >= 10 then
    return json_build_object('error', 'too_many_attempts');
  end if;
  select s.* into v_sub from subcontractors s join subcontractor_codes c on c.subcontractor_id = s.id
   where c.code = v_code;
  if not found then
    insert into join_attempts (user_id) values (v_uid);
    return json_build_object('error', 'invalid_join_code');
  end if;
  select * into v_company from companies where id = v_sub.company_id;
  insert into subcontractor_users (subcontractor_id, user_id) values (v_sub.id, v_uid)
  on conflict do nothing;
  return json_build_object('subcontractor_id', v_sub.id, 'subcontractor_name', v_sub.name,
                           'company_id', v_company.id, 'company_name', v_company.name);
end $$;
revoke all on function join_as_subcontractor(text) from public, anon;
grant execute on function join_as_subcontractor(text) to authenticated;

-- The sites a subcontractor works on, by name only: the projects table
-- carries the client and money columns they must not see.
create or replace function subcontractor_sites()
returns table (id uuid, company_id uuid, name text)
language sql security definer set search_path = public stable as $$
  select distinct p.id, p.company_id, p.name
    from projects p
    join work_orders w on w.project_id = p.id
    join subcontractor_users su on su.subcontractor_id = w.subcontractor_id
   where su.user_id = (select auth.uid());
$$;
revoke all on function subcontractor_sites() from public, anon;
grant execute on function subcontractor_sites() to authenticated;

drop policy if exists "subcontractors read their own firm" on subcontractors;
create policy "subcontractors read their own firm" on subcontractors for select
  to authenticated using ((select is_my_subcontractor(id)));

drop policy if exists "subcontractors read their own work orders" on work_orders;
create policy "subcontractors read their own work orders" on work_orders for select
  to authenticated using ((select is_my_subcontractor(subcontractor_id)));

-- --- Claims and certification (FOS-201) -------------------------------------

create table if not exists work_claims (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  work_order_id uuid not null references work_orders(id) on delete cascade,
  qty numeric(14, 3) not null check (qty > 0),
  -- Where on site (block, floor, grid) and what was done.
  location text check (char_length(location) <= 120),
  note text check (char_length(note) <= 300),
  submitted_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  synced_at timestamptz not null default now()
);
create index if not exists work_claims_order_idx on work_claims (work_order_id, created_at);
create index if not exists work_claims_project_idx on work_claims (project_id);

create table if not exists variations (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  work_order_id uuid references work_orders(id) on delete set null,
  cost_code_id uuid references cost_codes(id) on delete set null,
  title text not null check (char_length(title) between 1 and 200),
  origin text not null check (origin in ('claim_over_order', 'client_instruction', 'design_change',
                                         'site_condition', 'other')),
  source_claim_id uuid references work_claims(id) on delete set null,
  qty numeric(14, 3) check (qty is null or qty >= 0),
  unit text check (char_length(unit) <= 20),
  estimated_cost numeric(14, 2) not null default 0,
  schedule_days int not null default 0 check (schedule_days between -365 and 3650),
  owner_id uuid references auth.users(id),
  note text check (char_length(note) <= 500),
  raised_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  synced_at timestamptz not null default now()
);
create index if not exists variations_project_idx on variations (project_id, created_at);
create index if not exists variations_order_idx on variations (work_order_id);

create table if not exists variation_decisions (
  id uuid primary key,
  variation_id uuid not null unique references variations(id) on delete cascade,
  project_id uuid not null references projects(id) on delete cascade,
  decision text not null check (decision in ('approved', 'rejected')),
  approved_qty numeric(14, 3) check (approved_qty is null or approved_qty >= 0),
  approved_cost numeric(14, 2),
  note text check (char_length(note) <= 300),
  decided_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  synced_at timestamptz not null default now(),
  check (decision = 'approved' or (approved_qty is null and approved_cost is null))
);
create index if not exists variation_decisions_project_idx on variation_decisions (project_id);

create table if not exists work_certifications (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  work_order_id uuid not null references work_orders(id) on delete cascade,
  claim_id uuid not null references work_claims(id) on delete cascade,
  accepted_qty numeric(14, 3) not null default 0 check (accepted_qty >= 0),
  rejected_qty numeric(14, 3) not null default 0 check (rejected_qty >= 0),
  -- The variation this certification raised for the quantity beyond the
  -- order, or the approved variation it certifies against.
  variation_id uuid references variations(id) on delete set null,
  note text check (char_length(note) <= 300),
  certified_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  synced_at timestamptz not null default now(),
  check (accepted_qty + rejected_qty > 0 or variation_id is not null)
);
create index if not exists work_certifications_order_idx on work_certifications (work_order_id);
create index if not exists work_certifications_claim_idx on work_certifications (claim_id);

drop trigger if exists work_orders_keep_baseline on work_orders;
create trigger work_orders_keep_baseline before update on work_orders
  for each row execute function work_orders_keep_baseline();

-- The two quantity rules, under a lock on the work order.
create or replace function work_certifications_check()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_order work_orders%rowtype;
  v_claim work_claims%rowtype;
  v_claim_done numeric;
  v_order_done numeric;
  v_limit numeric;
begin
  select * into v_order from work_orders where id = new.work_order_id for update;
  select * into v_claim from work_claims where id = new.claim_id;
  if v_claim.work_order_id is distinct from new.work_order_id or v_order.project_id is distinct from new.project_id then
    raise exception 'certification does not match its claim and work order' using errcode = '23514';
  end if;
  if v_order.contract_qty is null then
    raise exception 'work order % has no agreed quantity to certify against', new.work_order_id using errcode = '23514';
  end if;
  select coalesce(sum(accepted_qty + rejected_qty), 0) into v_claim_done
    from work_certifications where claim_id = new.claim_id;
  if v_claim_done + new.accepted_qty + new.rejected_qty > v_claim.qty + 0.0005 then
    raise exception 'claim % is already certified: % of % decided', new.claim_id, v_claim_done, v_claim.qty
      using errcode = '23514';
  end if;
  select coalesce(sum(accepted_qty), 0) into v_order_done
    from work_certifications where work_order_id = new.work_order_id;
  select v_order.contract_qty + coalesce(sum(d.approved_qty), 0) into v_limit
    from variations v join variation_decisions d on d.variation_id = v.id
   where v.work_order_id = new.work_order_id and d.decision = 'approved';
  if v_order_done + new.accepted_qty > v_limit + 0.0005 then
    raise exception 'work order % would be certified beyond its agreed quantity (% + % > %)',
      new.work_order_id, v_order_done, new.accepted_qty, v_limit using errcode = '23514';
  end if;
  return new;
end $$;
revoke all on function work_certifications_check() from public, anon, authenticated;

drop trigger if exists work_certifications_check on work_certifications;
create trigger work_certifications_check before insert on work_certifications
  for each row execute function work_certifications_check();

-- A decision keeps the time it was made on the phone (it may sync hours
-- later), never in the future; the server's own clock goes in synced_at.
create or replace function commercial_stamp()
returns trigger language plpgsql as $$
begin
  new.synced_at := now();
  if new.created_at is null or new.created_at > now() + interval '5 minutes' then
    new.created_at := now();
  end if;
  return new;
end $$;

create table if not exists commercial_attachments (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  parent_kind text not null check (parent_kind in ('claim', 'certification', 'variation')),
  parent_id uuid not null,
  file_path text not null check (char_length(file_path) <= 300),
  mime_type text not null check (char_length(mime_type) <= 100),
  uploaded_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now(),
  check (split_part(file_path, '/', 1) = project_id::text)
);
create index if not exists commercial_attachments_parent_idx on commercial_attachments (parent_id);
create index if not exists commercial_attachments_project_idx on commercial_attachments (project_id);

create table if not exists commercial_exception_actions (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  -- kind:record id, e.g. overdue_certification:<claim id>.
  exception_key text not null check (char_length(exception_key) between 3 and 120),
  action text not null check (action in ('assigned', 'resolved', 'reopened')),
  owner_id uuid references auth.users(id),
  due_on date,
  note text check (char_length(note) <= 300),
  -- What the exception looked like when it was resolved; if it changes
  -- (an overrun grows) it comes back.
  fingerprint text check (char_length(fingerprint) <= 200),
  acted_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  synced_at timestamptz not null default now()
);
create index if not exists commercial_exception_actions_project_idx
  on commercial_exception_actions (project_id, exception_key, created_at);

do $$
declare t text;
begin
  foreach t in array array['work_claims', 'work_certifications', 'variations', 'variation_decisions',
                           'commercial_exception_actions'] loop
    execute format('drop trigger if exists %I on %I', t || '_stamp', t);
    execute format('create trigger %I before insert on %I for each row execute function commercial_stamp()',
                   t || '_stamp', t);
  end loop;
end $$;

-- --- Grants and row level security -----------------------------------------

alter table cost_codes enable row level security;
alter table work_claims enable row level security;
alter table work_certifications enable row level security;
alter table variations enable row level security;
alter table variation_decisions enable row level security;
alter table commercial_attachments enable row level security;
alter table commercial_exception_actions enable row level security;

revoke all on table cost_codes, work_claims, work_certifications, variations, variation_decisions,
  commercial_attachments, commercial_exception_actions from anon, authenticated;
grant select, insert, update, delete on table cost_codes to authenticated;
grant select, insert on table work_claims, work_certifications, variations, variation_decisions,
  commercial_exception_actions to authenticated;
grant select, insert, delete on table commercial_attachments to authenticated;

-- Cost codes: the site reads them; the owner or a PM sets budgets.
drop policy if exists "site reads cost codes" on cost_codes;
create policy "site reads cost codes" on cost_codes for select
  to authenticated using ((select has_project_access(project_id)));
drop policy if exists "owner/pm add cost codes" on cost_codes;
create policy "owner/pm add cost codes" on cost_codes for insert
  to authenticated with check ((select is_project_owner_or_pm(project_id)));
drop policy if exists "owner/pm edit cost codes" on cost_codes;
create policy "owner/pm edit cost codes" on cost_codes for update
  to authenticated using ((select is_project_owner_or_pm(project_id)))
  with check ((select is_project_owner_or_pm(project_id)));
drop policy if exists "owner/pm remove cost codes" on cost_codes;
create policy "owner/pm remove cost codes" on cost_codes for delete
  to authenticated using ((select is_project_owner_or_pm(project_id)));

-- Claims: the site and the claiming subcontractor read them; the
-- subcontractor (or an engineer on their behalf) adds them as themselves.
drop policy if exists "site and subcontractor read claims" on work_claims;
create policy "site and subcontractor read claims" on work_claims for select
  to authenticated using ((select has_project_access(project_id)) or (select is_my_work_order(work_order_id)));
drop policy if exists "claims are added as yourself" on work_claims;
create policy "claims are added as yourself" on work_claims for insert
  to authenticated with check (
    submitted_by = (select auth.uid())
    and project_id = (select w.project_id from work_orders w where w.id = work_order_id)
    and ((select has_project_access(project_id)) or (select is_my_work_order(work_order_id))));

-- Certifications: the subcontractor sees the outcome of their claims; only
-- people on the site certify.
drop policy if exists "site and subcontractor read certifications" on work_certifications;
create policy "site and subcontractor read certifications" on work_certifications for select
  to authenticated using ((select has_project_access(project_id)) or (select is_my_work_order(work_order_id)));
drop policy if exists "site certifies as yourself" on work_certifications;
create policy "site certifies as yourself" on work_certifications for insert
  to authenticated with check (certified_by = (select auth.uid()) and (select has_project_access(project_id)));

-- Variations: anyone on the site raises one; the owner or a PM decides.
drop policy if exists "site reads variations" on variations;
create policy "site reads variations" on variations for select
  to authenticated using ((select has_project_access(project_id)));
drop policy if exists "site raises variations" on variations;
create policy "site raises variations" on variations for insert
  to authenticated with check (raised_by = (select auth.uid()) and (select has_project_access(project_id)));

drop policy if exists "site reads variation decisions" on variation_decisions;
create policy "site reads variation decisions" on variation_decisions for select
  to authenticated using ((select has_project_access(project_id)));
drop policy if exists "owner/pm decide variations" on variation_decisions;
create policy "owner/pm decide variations" on variation_decisions for insert
  to authenticated with check (
    decided_by = (select auth.uid())
    and (select is_project_owner_or_pm(project_id))
    and project_id = (select v.project_id from variations v where v.id = variation_id));

-- Photos: a claim's photos are the subcontractor's too.
create or replace function commercial_parent_visible(p_kind text, p_parent uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select p_kind = 'claim' and exists (select 1 from work_claims c where c.id = p_parent and is_my_work_order(c.work_order_id));
$$;
revoke all on function commercial_parent_visible(text, uuid) from public, anon;
grant execute on function commercial_parent_visible(text, uuid) to authenticated;

drop policy if exists "site and subcontractor read commercial photos" on commercial_attachments;
create policy "site and subcontractor read commercial photos" on commercial_attachments for select
  to authenticated using ((select has_project_access(project_id)) or (select commercial_parent_visible(parent_kind, parent_id)));
drop policy if exists "site and subcontractor add commercial photos" on commercial_attachments;
create policy "site and subcontractor add commercial photos" on commercial_attachments for insert
  to authenticated with check ((select has_project_access(project_id)) or (select commercial_parent_visible(parent_kind, parent_id)));
drop policy if exists "uploader or owner/pm removes commercial photos" on commercial_attachments;
create policy "uploader or owner/pm removes commercial photos" on commercial_attachments for delete
  to authenticated using (uploaded_by = (select auth.uid()) or (select is_project_owner_or_pm(project_id)));

drop policy if exists "site reads exception actions" on commercial_exception_actions;
create policy "site reads exception actions" on commercial_exception_actions for select
  to authenticated using ((select has_project_access(project_id)));
drop policy if exists "site assigns, owner/pm resolve" on commercial_exception_actions;
create policy "site assigns, owner/pm resolve" on commercial_exception_actions for insert
  to authenticated with check (
    acted_by = (select auth.uid())
    and (select has_project_access(project_id))
    and (action = 'assigned' or (select is_project_owner_or_pm(project_id))));

-- Storage: a subcontractor uploads and reads claim photos under the site's
-- folder ({projectId}/claims/...), where has_project_access says no.
drop policy if exists "subcontractors upload claim photos" on storage.objects;
create policy "subcontractors upload claim photos" on storage.objects for insert
  to authenticated with check (
    bucket_id = 'documents' and (storage.foldername(name))[2] = 'claims'
    and (select is_subcontractor_on_project(((storage.foldername(name))[1])::uuid)));
drop policy if exists "subcontractors read claim photos" on storage.objects;
create policy "subcontractors read claim photos" on storage.objects for select
  to authenticated using (
    bucket_id = 'documents' and (storage.foldername(name))[2] = 'claims'
    and (select is_subcontractor_on_project(((storage.foldername(name))[1])::uuid)));

-- --- Change log (20261110020000_incremental_sync.sql) -----------------------

-- A subcontractor learns about changes to their own work orders, claims,
-- certifications and claim photos (the row fetch is still filtered by the
-- tables' own policies, so they only get their own rows).
drop policy if exists "members read their changes" on sync_changes;
create policy "members read their changes" on sync_changes for select
  to authenticated using (
    (project_id is not null and (select has_project_access(project_id)))
    or (company_id is not null and (project_id is null or (table_name = 'projects' and op = 'd'))
        and (select is_company_member(company_id)))
    or (project_id is not null
        and table_name in ('work_orders', 'work_claims', 'work_certifications', 'commercial_attachments')
        and (select is_subcontractor_on_project(project_id))));

do $$
declare t text;
begin
  foreach t in array array['cost_codes', 'work_claims', 'work_certifications', 'variations', 'variation_decisions',
                           'commercial_attachments', 'commercial_exception_actions'] loop
    execute format('drop trigger if exists %I on %I', t || '_log_sync_change', t);
    execute format('create trigger %I after insert or update or delete on %I for each row execute function log_sync_change()',
                   t || '_log_sync_change', t);
  end loop;
end $$;
