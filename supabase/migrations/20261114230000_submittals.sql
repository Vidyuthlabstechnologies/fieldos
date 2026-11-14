-- Submittals register (global gap 4): shop drawings, product data, samples,
-- mock-ups and method statements sent for the architect's or consultant's
-- review before the work or the order goes ahead. Same columns as the
-- phone's submittals table, in snake_case, so the site-execution sync
-- mapper covers it. Photos ride on site_execution_photos (parent_kind
-- 'submittal').
--
-- Rules the server keeps, whatever the phone does:
--  - raised as yourself; who raised it never changes;
--  - only the owner or a project manager records the review, as themselves;
--  - a submittal sent back (revise and resubmit, or rejected) goes back for
--    review only as the next round, with the decision cleared and the
--    earlier decisions kept in history, which only grows.

create table if not exists site_submittals (
  id uuid primary key,
  project_id uuid not null references projects(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 200),
  kind text not null default 'product_data'
    check (kind in ('shop_drawing', 'product_data', 'sample', 'mock_up', 'method_statement', 'other')),
  spec_section text check (char_length(spec_section) <= 40),
  from_party text check (char_length(from_party) <= 120),
  reviewer text check (char_length(reviewer) <= 120),
  required_by date,
  drawing_id uuid references site_drawings(id) on delete set null,
  task_id uuid,
  round int not null default 1 check (round between 1 and 99),
  status text not null default 'submitted'
    check (status in ('submitted', 'approved', 'approved_as_noted', 'revise_resubmit', 'rejected')),
  decision_note text check (char_length(decision_note) <= 1000),
  decided_by uuid,
  decided_at timestamptz,
  history text not null default '' check (char_length(history) <= 8000),
  raised_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  synced_at timestamptz not null default now()
);
create index if not exists site_submittals_project_idx on site_submittals (project_id);

alter table site_execution_photos drop constraint if exists site_execution_photos_parent_kind_check;
alter table site_execution_photos add constraint site_execution_photos_parent_kind_check
  check (parent_kind in ('defect', 'defect_fix', 'hold_point', 'rfi', 'submittal'));

create or replace function site_submittals_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  me uuid := (select auth.uid());
  manager boolean := coalesce(is_project_owner_or_pm(new.project_id), false);
begin
  if tg_op = 'INSERT' then
    if new.raised_by is distinct from me then
      raise exception 'Submittals are raised as yourself.' using errcode = '42501';
    end if;
    if new.status <> 'submitted' or new.round <> 1 or new.decided_by is not null or new.decided_at is not null
       or new.history <> '' then
      raise exception 'A new submittal starts as submitted, round 1.' using errcode = '42501';
    end if;
  else
    if new.project_id <> old.project_id or new.raised_by is distinct from old.raised_by then
      raise exception 'Who raised a submittal, and its site, cannot change.' using errcode = '42501';
    end if;
    if left(new.history, char_length(old.history)) <> old.history then
      raise exception 'A submittal''s review history is never rewritten.' using errcode = '42501';
    end if;
    if new.status is distinct from old.status or new.round <> old.round then
      if old.status = 'submitted' and new.round = old.round
         and new.status in ('approved', 'approved_as_noted', 'revise_resubmit', 'rejected') then
        if not manager then
          raise exception 'Only the owner or a project manager records a submittal review.' using errcode = '42501';
        end if;
        if new.decided_by is distinct from me or new.decided_at is null then
          raise exception 'Reviews are recorded as yourself.' using errcode = '42501';
        end if;
      elsif old.status in ('revise_resubmit', 'rejected') and new.status = 'submitted' and new.round = old.round + 1 then
        if new.decided_by is not null or new.decided_at is not null or new.decision_note is not null then
          raise exception 'A resubmitted submittal waits for a new review.' using errcode = '42501';
        end if;
        if char_length(new.history) <= char_length(old.history) then
          raise exception 'The earlier review is kept in the history.' using errcode = '42501';
        end if;
      else
        raise exception 'That is not a step a submittal can take.' using errcode = '42501';
      end if;
    elsif (new.decided_by, new.decided_at, new.decision_note) is distinct from (old.decided_by, old.decided_at, old.decision_note) then
      raise exception 'A review is recorded once; resubmit for a new one.' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
revoke all on function site_submittals_guard() from public, anon, authenticated;

drop trigger if exists site_submittals_stamp on site_submittals;
create trigger site_submittals_stamp before insert or update on site_submittals
  for each row execute function site_execution_stamp();
drop trigger if exists site_submittals_guard on site_submittals;
create trigger site_submittals_guard before insert or update on site_submittals
  for each row execute function site_submittals_guard();
drop trigger if exists site_submittals_log_sync_change on site_submittals;
create trigger site_submittals_log_sync_change after insert or update or delete on site_submittals
  for each row execute function log_sync_change();

alter table site_submittals enable row level security;
revoke all on table site_submittals from anon, authenticated;
grant select, insert, update on table site_submittals to authenticated;

drop policy if exists "site reads submittals" on site_submittals;
create policy "site reads submittals" on site_submittals for select
  to authenticated using ((select has_project_access(project_id)));
drop policy if exists "site adds submittals" on site_submittals;
create policy "site adds submittals" on site_submittals for insert
  to authenticated with check ((select has_project_access(project_id)));
drop policy if exists "site updates submittals" on site_submittals;
create policy "site updates submittals" on site_submittals for update
  to authenticated using ((select has_project_access(project_id)))
  with check ((select has_project_access(project_id)));
