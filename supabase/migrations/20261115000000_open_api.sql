-- Open API (global gap 6): a company's owner makes API keys, and an ERP,
-- BI tool, Zapier or Make reads the company's site records with one, through
-- the public-api edge function. Read only.
--
--  - A key is shown once. Only its SHA-256 is kept; the owner sees its first
--    characters, name, when it was last used, and can revoke it.
--  - Every read goes through api_read(), which only the service role (the
--    edge function) may call. It finds the key's company and returns rows of
--    that company's sites only, from a fixed list of resources.
--  - The change feed reads sync_changes (already written for every row the
--    phones sync), so an integration can poll "what changed since seq N".
--  - 120 calls a minute per key.

create table if not exists company_api_keys (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 60),
  key_prefix text not null,
  key_hash text not null unique,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  revoked_at timestamptz,
  revoked_by uuid,
  window_start timestamptz not null default now(),
  window_calls int not null default 0
);
create index if not exists company_api_keys_company_idx on company_api_keys (company_id);

alter table company_api_keys enable row level security;
revoke all on table company_api_keys from anon, authenticated;
grant select (id, company_id, name, key_prefix, created_by, created_at, last_used_at, revoked_at, revoked_by)
  on table company_api_keys to authenticated;
drop policy if exists "owner sees api keys" on company_api_keys;
create policy "owner sees api keys" on company_api_keys for select
  to authenticated using (coalesce((select company_role(company_id)) = 'owner', false));

-- Makes a key for the company and returns it. The plain key is never stored.
create or replace function create_company_api_key(p_company_id uuid, p_name text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := (select auth.uid());
  plain text;
  row company_api_keys;
begin
  if me is null or coalesce(company_role(p_company_id) = 'owner', false) is not true then
    raise exception 'Only the company owner makes API keys.' using errcode = '42501';
  end if;
  if char_length(btrim(coalesce(p_name, ''))) not between 1 and 60 then
    raise exception 'Give the key a name, up to 60 characters.' using errcode = '22023';
  end if;
  if (select count(*) from company_api_keys where company_id = p_company_id and revoked_at is null) >= 10 then
    raise exception 'A company can have 10 keys in use. Revoke one first.' using errcode = '54000';
  end if;
  plain := 'fos_' || encode(extensions.gen_random_bytes(24), 'hex');
  insert into company_api_keys (company_id, name, key_prefix, key_hash, created_by)
  values (p_company_id, btrim(p_name), left(plain, 12), encode(extensions.digest(plain, 'sha256'), 'hex'), me)
  returning * into row;
  return jsonb_build_object('id', row.id, 'name', row.name, 'key_prefix', row.key_prefix, 'key', plain,
                            'created_at', row.created_at);
end $$;
revoke all on function create_company_api_key(uuid, text) from public, anon;
grant execute on function create_company_api_key(uuid, text) to authenticated;

create or replace function revoke_company_api_key(p_key_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  me uuid := (select auth.uid());
  cid uuid;
begin
  select company_id into cid from company_api_keys where id = p_key_id;
  if cid is null or me is null or coalesce(company_role(cid) = 'owner', false) is not true then
    raise exception 'Only the company owner revokes API keys.' using errcode = '42501';
  end if;
  update company_api_keys set revoked_at = coalesce(revoked_at, now()), revoked_by = coalesce(revoked_by, me)
   where id = p_key_id;
end $$;
revoke all on function revoke_company_api_key(uuid) from public, anon;
grant execute on function revoke_company_api_key(uuid) to authenticated;

-- What the API can read: resource name -> table. Nothing else is reachable.
create or replace function api_resources()
returns table (resource text, table_name text) language sql immutable as $$
  values
    ('projects', 'projects'),
    ('tasks', 'tasks'),
    ('issues', 'issues'),
    ('daily_reports', 'dpr_entries'),
    ('inspections', 'inspections'),
    ('approvals', 'approvals'),
    ('rfis', 'site_rfis'),
    ('submittals', 'site_submittals'),
    ('defects', 'site_defects'),
    ('drawings', 'site_drawings'),
    ('drawing_revisions', 'site_drawing_revisions'),
    ('hold_points', 'site_hold_points'),
    ('handover_units', 'site_handover_units'),
    ('constraints', 'site_task_constraints'),
    ('attendance', 'site_attendance'),
    ('material_receipts', 'site_material_receipts'),
    ('purchase_orders', 'purchase_orders'),
    ('expenses', 'site_expenses'),
    ('client_bills', 'site_client_bills'),
    ('supplier_invoices', 'site_supplier_invoices'),
    ('payments_received', 'site_payments_received')
$$;

-- One read through a key.
--   p_resource 'changes': the change feed after seq p_after (a number).
--   otherwise: rows of that resource ordered by id, after id p_after, or the
--   one row p_id; p_project narrows to one site.
-- Returns {"data": [...], "next": cursor or null}.
create or replace function api_read(
  p_key text, p_resource text, p_project uuid default null, p_id uuid default null,
  p_after text default null, p_limit int default 100)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  k company_api_keys;
  tbl text;
  lim int := least(greatest(coalesce(p_limit, 100), 1), 500);
  rows jsonb;
  after_seq bigint;
  after_id uuid;
begin
  select * into k from company_api_keys
   where key_hash = encode(extensions.digest(coalesce(p_key, ''), 'sha256'), 'hex') and revoked_at is null;
  if k.id is null then
    raise exception 'invalid_key' using errcode = '28000';
  end if;
  if k.window_start < now() - interval '1 minute' then
    update company_api_keys set window_start = now(), window_calls = 1, last_used_at = now() where id = k.id;
  elsif k.window_calls >= 120 then
    raise exception 'rate_limited' using errcode = '54000';
  else
    update company_api_keys set window_calls = window_calls + 1, last_used_at = now() where id = k.id;
  end if;

  if p_project is not null and not exists (select 1 from projects where id = p_project and company_id = k.company_id) then
    raise exception 'not_found' using errcode = 'P0002';
  end if;

  if p_resource = 'changes' then
    begin
      after_seq := coalesce(nullif(p_after, '')::bigint, 0);
    exception when others then
      raise exception 'bad_cursor' using errcode = '22023';
    end;
    select coalesce(jsonb_agg(x order by x.seq), '[]'::jsonb) into rows from (
      select c.seq, r.resource, c.row_id as id, case c.op when 'd' then 'deleted' else 'changed' end as op, c.changed_at
        from sync_changes c
        join api_resources() r on r.table_name = c.table_name
       where c.seq > after_seq
         and (c.company_id = k.company_id
              or c.project_id in (select id from projects where company_id = k.company_id))
         and (p_project is null or c.project_id = p_project)
       order by c.seq
       limit lim) x;
    return jsonb_build_object('data', rows,
      'next', case when jsonb_array_length(rows) = lim then rows->(lim - 1)->>'seq' end);
  end if;

  select r.table_name into tbl from api_resources() r where r.resource = p_resource;
  if tbl is null then
    raise exception 'unknown_resource' using errcode = '22023';
  end if;
  begin
    after_id := nullif(p_after, '')::uuid;
  exception when others then
    raise exception 'bad_cursor' using errcode = '22023';
  end;

  execute format(
    'select coalesce(jsonb_agg(to_jsonb(t) order by t.id), ''[]''::jsonb) from (
       select * from %I t
        where %s
          and ($2 is null or t.id = $2)
          and ($3 is null or t.id > $3)
        order by t.id
        limit $4) t',
    tbl,
    case when tbl = 'projects' then 't.company_id = $1 and ($5 is null or t.id = $5)'
         else 't.project_id in (select id from projects where company_id = $1) and ($5 is null or t.project_id = $5)' end)
    into rows using k.company_id, p_id, after_id, lim, p_project;

  if p_id is not null and jsonb_array_length(rows) = 0 then
    raise exception 'not_found' using errcode = 'P0002';
  end if;
  return jsonb_build_object('data', rows,
    'next', case when p_id is null and jsonb_array_length(rows) = lim then rows->(lim - 1)->>'id' end);
end $$;
revoke all on function api_read(text, text, uuid, uuid, text, int) from public, anon, authenticated;
grant execute on function api_read(text, text, uuid, uuid, text, int) to service_role;
revoke all on function api_resources() from public, anon, authenticated;
grant execute on function api_resources() to service_role;
