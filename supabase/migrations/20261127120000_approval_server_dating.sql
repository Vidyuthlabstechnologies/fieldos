-- Approval rules judge an item by when the SERVER got it, not by the date the
-- phone wrote on it.
--
-- A rule covers "items recorded after it was made, so setting one doesn't stop
-- last month's records" (20261110900000_approval_rules.sql). It decided that
-- from the item's created_at, which the phone supplies on insert. An engineer
-- could back-date a request or an expense to before the rule existed and the
-- rule would not apply to it.
--
-- received_at is stamped by the server when the row arrives, and cannot be set
-- or changed through the API. The two approval checks now use it. An item
-- recorded offline before a rule, and sent after it, is now held to the rule:
-- stricter, never looser. Rows that already exist keep their created_at, so
-- nothing already on the books is judged differently.
--
-- Additive and idempotent. Tested in supabase/tests/approval_dating_test.sql.

alter table site_expenses add column if not exists received_at timestamptz not null default now();
alter table purchase_requisitions add column if not exists received_at timestamptz not null default now();

-- Existing rows: when they were made, as the phone said then. Triggers are
-- off for this one statement pair (it is a backfill, not an edit, and must not
-- touch edited_at or the change history).
set session_replication_role = replica;
update site_expenses set received_at = created_at where received_at > created_at and created_at < now() - interval '1 minute';
update purchase_requisitions set received_at = created_at where received_at > created_at and created_at < now() - interval '1 minute';
reset session_replication_role;

create or replace function stamp_received_at()
returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.received_at := now();
  else
    new.received_at := old.received_at;
  end if;
  return new;
end $$;
revoke all on function stamp_received_at() from public, anon, authenticated;

drop trigger if exists site_expenses_stamp_received on site_expenses;
create trigger site_expenses_stamp_received before insert or update on site_expenses
  for each row execute function stamp_received_at();
drop trigger if exists purchase_requisitions_stamp_received on purchase_requisitions;
create trigger purchase_requisitions_stamp_received before insert or update on purchase_requisitions
  for each row execute function stamp_received_at();

create or replace function site_close_reviews_need_chain()
returns trigger language plpgsql security definer set search_path = public as $$
declare amt numeric; made timestamptz;
begin
  if new.decision = 'approved' and new.item_kind = 'expense' then
    select amount, received_at into amt, made from site_expenses where id = new.item_id::uuid;
    if not approval_chain_complete('expense', new.item_id::uuid, new.project_id, amt, made) then
      raise exception 'this expense still needs its approvals';
    end if;
  end if;
  return new;
end $$;
revoke all on function site_close_reviews_need_chain() from public, anon, authenticated;

create or replace function purchase_orders_need_chain()
returns trigger language plpgsql security definer set search_path = public as $$
declare amt numeric; made timestamptz;
begin
  if new.requisition_id is not null then
    select estimated_cost, received_at into amt, made from purchase_requisitions where id = new.requisition_id;
    if not approval_chain_complete('purchase_request', new.requisition_id, new.project_id, amt, made) then
      raise exception 'this purchase request still needs its approvals';
    end if;
  end if;
  return new;
end $$;
revoke all on function purchase_orders_need_chain() from public, anon, authenticated;
