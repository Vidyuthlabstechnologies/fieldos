-- CRM: leads, their history and quotations (2026-11-10).
--
-- Enquiries before they are sites: who asked, for what, what was said on
-- each call or visit, the next follow-up, the quotes sent, and the reason
-- when one is lost. A won lead becomes a site on the phone (the project,
-- its budget lines from the accepted quote) through the tables that
-- already sync; here it only keeps the link.
--
-- Company-wide and commercial, so only the owner and project managers read
-- or write them. Site engineers never see the sales pipeline.
--
-- Change log: these rows carry company_id and no project_id. They get their
-- own small trigger function rather than a new branch in
-- log_sync_change(), which several stacked migrations replace; the
-- existing sync_changes policy already shows company-level lines to
-- company members, and the rows themselves are still filtered by the
-- policies below, so a site engineer fetches nothing.

create table if not exists crm_leads (
  id uuid primary key,
  company_id uuid not null references companies(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 200),
  phone text check (char_length(phone) <= 30),
  email text check (char_length(email) <= 120),
  location text check (char_length(location) <= 300),
  source text not null default 'other'
    check (source in ('referral', 'walk_in', 'website', 'social', 'builder', 'repeat', 'other')),
  work_type text check (char_length(work_type) <= 200),
  estimated_value numeric(14, 2) check (estimated_value is null or estimated_value >= 0),
  stage text not null default 'new'
    check (stage in ('new', 'contacted', 'site_visit', 'quoted', 'negotiation', 'won', 'lost')),
  lost_reason text check (char_length(lost_reason) <= 300),
  owner_id uuid references auth.users(id) on delete set null,
  next_follow_up timestamptz,
  notes text check (char_length(notes) <= 1000),
  project_id uuid references projects(id) on delete set null,
  created_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- A lost lead says why; that is the point of keeping it.
  check (stage <> 'lost' or char_length(coalesce(lost_reason, '')) > 0)
);
create index if not exists crm_leads_company_idx on crm_leads (company_id, stage);

create table if not exists crm_activities (
  id uuid primary key,
  company_id uuid not null references companies(id) on delete cascade,
  lead_id uuid not null references crm_leads(id) on delete cascade,
  kind text not null check (kind in ('call', 'visit', 'meeting', 'whatsapp', 'note', 'stage')),
  note text not null check (char_length(note) between 1 and 1000),
  by_user uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists crm_activities_lead_idx on crm_activities (lead_id, created_at);

create table if not exists crm_quotes (
  id uuid primary key,
  company_id uuid not null references companies(id) on delete cascade,
  lead_id uuid not null references crm_leads(id) on delete cascade,
  quote_number text not null check (char_length(quote_number) between 1 and 40),
  quote_date timestamptz not null,
  valid_until timestamptz,
  status text not null default 'draft' check (status in ('draft', 'sent', 'accepted', 'rejected')),
  lines jsonb not null default '[]'::jsonb check (jsonb_typeof(lines) = 'array'),
  gst_rate numeric(5, 2) not null default 18 check (gst_rate between 0 and 28),
  inter_state boolean not null default false,
  discount numeric(14, 2) not null default 0 check (discount >= 0),
  total numeric(14, 2) not null default 0 check (total >= 0),
  terms text check (char_length(terms) <= 2000),
  created_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists crm_quotes_lead_idx on crm_quotes (lead_id);
create unique index if not exists crm_quotes_number_idx on crm_quotes (company_id, quote_number);

-- The lead, the activity or the quote belongs to the company it says, and
-- a child to its lead's company: no writing into another company by
-- pointing at its lead.
create or replace function crm_check_lead_company()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from crm_leads l where l.id = new.lead_id and l.company_id = new.company_id) then
    raise exception 'lead belongs to another company' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function crm_check_lead_company() from public, anon, authenticated;

-- Who made a row is whoever is signed in, whatever the phone sent.
create or replace function crm_stamp_creator()
returns trigger language plpgsql as $$
begin
  if tg_table_name = 'crm_activities' then
    new.by_user := auth.uid();
  else
    new.created_by := auth.uid();
  end if;
  if new.created_at is null or new.created_at > now() + interval '5 minutes' then
    new.created_at := now();
  end if;
  return new;
end $$;

-- Two phones offline can pick the same next number; the second keeps its
-- quote and gets a suffix instead of failing the sync.
create or replace function crm_quotes_unique_number()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from crm_quotes q
              where q.company_id = new.company_id and q.quote_number = new.quote_number and q.id <> new.id) then
    new.quote_number := left(new.quote_number, 33) || '-' || left(replace(new.id::text, '-', ''), 6);
  end if;
  return new;
end $$;
revoke all on function crm_quotes_unique_number() from public, anon, authenticated;

-- An accepted quote is what the site was priced on; it is not rewritten.
create or replace function crm_quotes_keep_accepted()
returns trigger language plpgsql as $$
begin
  if old.status = 'accepted' and (new.lines is distinct from old.lines or new.total is distinct from old.total
      or new.discount is distinct from old.discount or new.gst_rate is distinct from old.gst_rate) then
    raise exception 'an accepted quote is not changed' using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists crm_leads_stamp on crm_leads;
create trigger crm_leads_stamp before insert on crm_leads for each row execute function crm_stamp_creator();
drop trigger if exists crm_activities_stamp on crm_activities;
create trigger crm_activities_stamp before insert on crm_activities for each row execute function crm_stamp_creator();
drop trigger if exists crm_quotes_stamp on crm_quotes;
create trigger crm_quotes_stamp before insert on crm_quotes for each row execute function crm_stamp_creator();
drop trigger if exists crm_activities_lead_company on crm_activities;
create trigger crm_activities_lead_company before insert or update on crm_activities
  for each row execute function crm_check_lead_company();
drop trigger if exists crm_quotes_lead_company on crm_quotes;
create trigger crm_quotes_lead_company before insert or update on crm_quotes
  for each row execute function crm_check_lead_company();
drop trigger if exists crm_quotes_unique_number on crm_quotes;
create trigger crm_quotes_unique_number before insert on crm_quotes
  for each row execute function crm_quotes_unique_number();
drop trigger if exists crm_quotes_keep_accepted on crm_quotes;
create trigger crm_quotes_keep_accepted before update on crm_quotes
  for each row execute function crm_quotes_keep_accepted();

-- --- Grants and row level security -----------------------------------------

alter table crm_leads enable row level security;
alter table crm_activities enable row level security;
alter table crm_quotes enable row level security;

revoke all on table crm_leads, crm_activities, crm_quotes from anon, authenticated;
grant select, insert, update, delete on table crm_leads, crm_quotes to authenticated;
-- The history is what was said: added, never edited.
grant select, insert on table crm_activities to authenticated;

do $$
declare t text;
begin
  foreach t in array array['crm_leads', 'crm_activities', 'crm_quotes'] loop
    execute format('drop policy if exists %I on %I', 'owner/pm read ' || t, t);
    execute format('create policy %I on %I for select to authenticated using ((select is_company_owner_or_pm(company_id)))',
                   'owner/pm read ' || t, t);
    execute format('drop policy if exists %I on %I', 'owner/pm add ' || t, t);
    execute format('create policy %I on %I for insert to authenticated with check ((select is_company_owner_or_pm(company_id)))',
                   'owner/pm add ' || t, t);
  end loop;
  foreach t in array array['crm_leads', 'crm_quotes'] loop
    execute format('drop policy if exists %I on %I', 'owner/pm edit ' || t, t);
    execute format('create policy %I on %I for update to authenticated using ((select is_company_owner_or_pm(company_id))) '
                   'with check ((select is_company_owner_or_pm(company_id)))', 'owner/pm edit ' || t, t);
    execute format('drop policy if exists %I on %I', 'owner/pm remove ' || t, t);
    execute format('create policy %I on %I for delete to authenticated using ((select is_company_owner_or_pm(company_id)))',
                   'owner/pm remove ' || t, t);
  end loop;
end $$;

-- A won lead keeps its site; it is not deleted from under the project.
drop policy if exists "owner/pm remove crm_leads" on crm_leads;
create policy "owner/pm remove crm_leads" on crm_leads for delete
  to authenticated using ((select is_company_owner_or_pm(company_id)) and project_id is null);

-- --- Change log (20261110020000_incremental_sync.sql) -----------------------

create or replace function log_crm_sync_change()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  r jsonb := to_jsonb(case when tg_op = 'DELETE' then old else new end);
begin
  insert into sync_changes (table_name, row_id, op, project_id, company_id)
  values (tg_table_name, (r->>'id')::uuid, case when tg_op = 'DELETE' then 'd' else 'u' end,
          null, (r->>'company_id')::uuid);
  return null;
end $$;
revoke all on function log_crm_sync_change() from public, anon, authenticated;

do $$
declare t text;
begin
  foreach t in array array['crm_leads', 'crm_activities', 'crm_quotes'] loop
    execute format('drop trigger if exists %I on %I', t || '_log_sync_change', t);
    execute format('create trigger %I after insert or update or delete on %I for each row execute function log_crm_sync_change()',
                   t || '_log_sync_change', t);
  end loop;
end $$;
