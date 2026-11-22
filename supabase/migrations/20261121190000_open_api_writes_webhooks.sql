-- Open API, part 2 (after 20261115000000_open_api + _hardening):
--
--  1. Key scopes. A key reads (as before) or reads and writes. Existing keys
--     stay read only.
--  2. Writes through api_write(): create and update tasks and issues, the
--     two records other tools most often push in (a planning tool's
--     activities, a helpdesk or snag app's tickets). Nothing else is
--     writable, and nothing can be deleted. Every write is logged in
--     api_audit_log with the key that made it, and an Idempotency-Key makes a
--     retried POST safe.
--  3. Webhooks. The owner (or a write key, for Zapier/Make "instant"
--     triggers) registers an https URL and the resources it wants. Every row
--     change the phones sync already lands in sync_changes; webhook_enqueue()
--     turns those into deliveries, and the webhook-dispatch edge function
--     sends them, signed with the webhook's secret, retrying with backoff.
--     A webhook failing for 3 days is switched off.
--
-- Every function here that a key can reach counts toward the same 120 calls
-- a minute as api_read().

-- 1. Scopes --------------------------------------------------------------

alter table company_api_keys add column if not exists scopes text[] not null default array['read'];
alter table company_api_keys drop constraint if exists company_api_keys_scopes_check;
alter table company_api_keys add constraint company_api_keys_scopes_check
  check (scopes <@ array['read', 'write'] and 'read' = any (scopes));
grant select (scopes) on table company_api_keys to authenticated;

-- Replaces the two-argument version; old app builds still call it with two
-- named arguments and get a read key.
drop function if exists create_company_api_key(uuid, text);
create or replace function create_company_api_key(p_company_id uuid, p_name text, p_scopes text[] default array['read'])
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := (select auth.uid());
  plain text;
  sc text[];
  row company_api_keys;
begin
  if me is null or coalesce(company_role(p_company_id) = 'owner', false) is not true then
    raise exception 'Only the company owner makes API keys.' using errcode = '42501';
  end if;
  if char_length(btrim(coalesce(p_name, ''))) not between 1 and 60 then
    raise exception 'Give the key a name, up to 60 characters.' using errcode = '22023';
  end if;
  if not (coalesce(p_scopes, array['read']) <@ array['read', 'write']) then
    raise exception 'A key can read, or read and write.' using errcode = '22023';
  end if;
  sc := case when 'write' = any (coalesce(p_scopes, '{}')) then array['read', 'write'] else array['read'] end;
  if (select count(*) from company_api_keys where company_id = p_company_id and revoked_at is null) >= 10 then
    raise exception 'A company can have 10 keys in use. Revoke one first.' using errcode = '54000';
  end if;
  plain := 'fos_' || encode(extensions.gen_random_bytes(24), 'hex');
  insert into company_api_keys (company_id, name, key_prefix, key_hash, created_by, scopes)
  values (p_company_id, btrim(p_name), left(plain, 12), encode(extensions.digest(plain, 'sha256'), 'hex'), me, sc)
  returning * into row;
  return jsonb_build_object('id', row.id, 'name', row.name, 'key_prefix', row.key_prefix, 'key', plain,
                            'scopes', to_jsonb(row.scopes), 'created_at', row.created_at);
end $$;
revoke all on function create_company_api_key(uuid, text, text[]) from public, anon;
grant execute on function create_company_api_key(uuid, text, text[]) to authenticated;

-- One counted call through a key: the locking UPDATE from the hardening
-- migration, shared by reads, writes and webhook calls. Raises invalid_key
-- or rate_limited; everything after it should return {"error": ...}
-- instead of raising, so the call stays counted.
create or replace function api_take_call(p_key text)
returns company_api_keys language plpgsql security definer set search_path = public as $$
declare
  k company_api_keys;
begin
  update company_api_keys
     set window_start = case when window_start < now() - interval '1 minute' then now() else window_start end,
         window_calls = case when window_start < now() - interval '1 minute' then 1 else window_calls + 1 end,
         last_used_at = now()
   where key_hash = encode(extensions.digest(coalesce(p_key, ''), 'sha256'), 'hex') and revoked_at is null
  returning * into k;
  if k.id is null then
    raise exception 'invalid_key' using errcode = '28000';
  end if;
  if k.window_calls > 120 then
    raise exception 'rate_limited' using errcode = '54000';
  end if;
  return k;
end $$;
revoke all on function api_take_call(text) from public, anon, authenticated;
grant execute on function api_take_call(text) to service_role;

-- api_read, unchanged in behaviour, now counting through api_take_call.
create or replace function api_read(
  p_key text, p_resource text, p_project uuid default null, p_id uuid default null,
  p_after text default null, p_limit int default 100)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  k company_api_keys := api_take_call(p_key);
  tbl text;
  lim int := least(greatest(coalesce(p_limit, 100), 1), 500);
  rows jsonb;
  after_seq bigint;
  after_id uuid;
begin
  if p_project is not null and not exists (select 1 from projects where id = p_project and company_id = k.company_id) then
    return jsonb_build_object('error', 'not_found');
  end if;

  if p_resource = 'changes' then
    begin
      after_seq := coalesce(nullif(p_after, '')::bigint, 0);
    exception when others then
      return jsonb_build_object('error', 'bad_cursor');
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
    return jsonb_build_object('error', 'unknown_resource');
  end if;
  begin
    after_id := nullif(p_after, '')::uuid;
  exception when others then
    return jsonb_build_object('error', 'bad_cursor');
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
    return jsonb_build_object('error', 'not_found');
  end if;
  return jsonb_build_object('data', rows,
    'next', case when p_id is null and jsonb_array_length(rows) = lim then rows->(lim - 1)->>'id' end);
end $$;
revoke all on function api_read(text, text, uuid, uuid, text, int) from public, anon, authenticated;
grant execute on function api_read(text, text, uuid, uuid, text, int) to service_role;

-- 2. Writes --------------------------------------------------------------

-- Who changed what through the API, for the owner (Settings > API keys).
create table if not exists api_audit_log (
  id bigserial primary key,
  company_id uuid not null references companies(id) on delete cascade,
  key_id uuid references company_api_keys(id) on delete set null,
  key_name text not null,
  action text not null check (action in ('create', 'update', 'webhook_create', 'webhook_delete')),
  resource text not null,
  row_id uuid,
  at timestamptz not null default now()
);
create index if not exists api_audit_log_company_idx on api_audit_log (company_id, at desc);
alter table api_audit_log enable row level security;
revoke all on table api_audit_log from anon, authenticated;
grant select on table api_audit_log to authenticated;
drop policy if exists "owner sees api audit" on api_audit_log;
create policy "owner sees api audit" on api_audit_log for select
  to authenticated using (coalesce((select company_role(company_id)) = 'owner', false));

-- A POST sent again with the same Idempotency-Key within a day gets the
-- first answer back instead of making a second row.
create table if not exists api_idempotency (
  key_id uuid not null references company_api_keys(id) on delete cascade,
  idem_key text not null,
  request_hash text not null,
  response jsonb not null,
  created_at timestamptz not null default now(),
  primary key (key_id, idem_key)
);
alter table api_idempotency enable row level security;
revoke all on table api_idempotency from anon, authenticated;

-- Writable fields: resource -> (field -> 'c' create only, 'cu' create and
-- update, plus '!' when required on create). Anything else is refused, so
-- ids, project moves and timestamps stay the server's.
create or replace function api_writable()
returns table (resource text, field text, mode text) language sql immutable as $$
  values
    ('tasks', 'project_id', 'c!'),
    ('tasks', 'title', 'cu!'),
    ('tasks', 'status', 'cu'),
    ('tasks', 'priority', 'cu'),
    ('tasks', 'progress', 'cu'),
    ('tasks', 'start_date', 'cu'),
    ('tasks', 'due_date', 'cu'),
    ('issues', 'project_id', 'c!'),
    ('issues', 'description', 'cu!'),
    ('issues', 'severity', 'cu'),
    ('issues', 'status', 'cu')
$$;
revoke all on function api_writable() from public, anon, authenticated;
grant execute on function api_writable() to service_role;

-- One write through a key. p_id null = create, else update that row.
-- Returns {"data": row} or {"error": code, "message": text}.
create or replace function api_write(
  p_key text, p_resource text, p_id uuid default null, p_body jsonb default '{}'::jsonb,
  p_idempotency_key text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  k company_api_keys := api_take_call(p_key);
  body jsonb := coalesce(p_body, '{}'::jsonb);
  creating boolean := p_id is null;
  req_hash text;
  prior api_idempotency;
  f text;
  missing text;
  pid uuid;
  result jsonb;
  row_id uuid;
begin
  if not ('write' = any (k.scopes)) then
    return jsonb_build_object('error', 'forbidden', 'message', 'This key can only read. The owner makes a key that can write in Settings, API keys.');
  end if;
  if p_resource not in (select w.resource from api_writable() w) then
    return jsonb_build_object('error', 'not_writable', 'message', 'Only tasks and issues can be written.');
  end if;
  if jsonb_typeof(body) <> 'object' then
    return jsonb_build_object('error', 'bad_request', 'message', 'Send a JSON object.');
  end if;

  if creating and p_idempotency_key is not null then
    if char_length(p_idempotency_key) not between 1 and 100 then
      return jsonb_build_object('error', 'bad_request', 'message', 'Idempotency-Key is 1 to 100 characters.');
    end if;
    req_hash := encode(extensions.digest(p_resource || ':' || body::text, 'sha256'), 'hex');
    select * into prior from api_idempotency
     where key_id = k.id and idem_key = p_idempotency_key and created_at > now() - interval '1 day';
    if prior.key_id is not null then
      if prior.request_hash <> req_hash then
        return jsonb_build_object('error', 'idempotency_conflict',
          'message', 'This Idempotency-Key was already used for a different request.');
      end if;
      return prior.response;
    end if;
  end if;

  select f2 into f from jsonb_object_keys(body) f2
   where f2 not in (select w.field from api_writable() w
                     where w.resource = p_resource and (creating or w.mode like 'cu%'))
   limit 1;
  if f is not null then
    return jsonb_build_object('error', 'bad_request', 'message', format('%s cannot be %s through the API.', f,
      case when creating then 'set' else 'changed' end));
  end if;
  if creating then
    select w.field into missing from api_writable() w
     where w.resource = p_resource and w.mode like '%!' and nullif(btrim(coalesce(body->>w.field, '')), '') is null
     limit 1;
    if missing is not null then
      return jsonb_build_object('error', 'bad_request', 'message', format('%s is required.', missing));
    end if;
  elsif body = '{}'::jsonb then
    return jsonb_build_object('error', 'bad_request', 'message', 'Nothing to change.');
  end if;

  begin
    if creating then
      pid := (body->>'project_id')::uuid;
      if not exists (select 1 from projects where id = pid and company_id = k.company_id) then
        return jsonb_build_object('error', 'not_found', 'message', 'No such site for this key.');
      end if;
    end if;

    if p_resource = 'tasks' then
      if creating then
        insert into tasks (project_id, title, status, priority, progress, start_date, due_date)
        values (pid, left(btrim(body->>'title'), 300),
                coalesce(body->>'status', 'todo'), coalesce(body->>'priority', 'normal'),
                coalesce((body->>'progress')::int, 0), (body->>'start_date')::date, (body->>'due_date')::date)
        returning to_jsonb(tasks.*), id into result, row_id;
      else
        update tasks t set
          title = case when body ? 'title' then left(btrim(body->>'title'), 300) else t.title end,
          status = case when body ? 'status' then body->>'status' else t.status end,
          priority = case when body ? 'priority' then body->>'priority' else t.priority end,
          progress = case when body ? 'progress' then (body->>'progress')::int else t.progress end,
          start_date = case when body ? 'start_date' then (body->>'start_date')::date else t.start_date end,
          due_date = case when body ? 'due_date' then (body->>'due_date')::date else t.due_date end,
          updated_at = now()
         where t.id = p_id and t.project_id in (select id from projects where company_id = k.company_id)
        returning to_jsonb(t.*), t.id into result, row_id;
      end if;
    else
      if creating then
        insert into issues (project_id, description, severity, status, resolved_at)
        values (pid, left(btrim(body->>'description'), 2000),
                coalesce(body->>'severity', 'medium'), coalesce(body->>'status', 'open'),
                case when body->>'status' in ('resolved', 'closed') then now() end)
        returning to_jsonb(issues.*), id into result, row_id;
      else
        update issues i set
          description = case when body ? 'description' then left(btrim(body->>'description'), 2000) else i.description end,
          severity = case when body ? 'severity' then body->>'severity' else i.severity end,
          status = case when body ? 'status' then body->>'status' else i.status end,
          resolved_at = case
            when not body ? 'status' then i.resolved_at
            when body->>'status' in ('resolved', 'closed') then coalesce(i.resolved_at, now())
            else null end
         where i.id = p_id and i.project_id in (select id from projects where company_id = k.company_id)
        returning to_jsonb(i.*), i.id into result, row_id;
      end if;
    end if;
  exception
    when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format
         or datetime_field_overflow or numeric_value_out_of_range or string_data_right_truncation then
      return jsonb_build_object('error', 'bad_request', 'message', 'A value is not allowed: ' || sqlerrm);
  end;

  if row_id is null then
    return jsonb_build_object('error', 'not_found', 'message', 'Nothing here for this key.');
  end if;
  insert into api_audit_log (company_id, key_id, key_name, action, resource, row_id)
  values (k.company_id, k.id, k.name, case when creating then 'create' else 'update' end, p_resource, row_id);
  result := jsonb_build_object('data', result);
  if req_hash is not null then
    insert into api_idempotency (key_id, idem_key, request_hash, response)
    values (k.id, p_idempotency_key, req_hash, result)
    on conflict (key_id, idem_key) do update
      set request_hash = excluded.request_hash, response = excluded.response, created_at = now();
  end if;
  return result;
end $$;
revoke all on function api_write(text, text, uuid, jsonb, text) from public, anon, authenticated;
grant execute on function api_write(text, text, uuid, jsonb, text) to service_role;

-- 3. Webhooks ------------------------------------------------------------

create table if not exists company_webhooks (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  url text not null check (char_length(url) <= 500),
  -- resource names from api_resources(), or '*' for all of them
  events text[] not null default array['*'] check (cardinality(events) between 1 and 30),
  description text check (description is null or char_length(description) <= 60),
  secret text not null,
  created_by uuid,
  created_by_key uuid references company_api_keys(id) on delete set null,
  created_at timestamptz not null default now(),
  cursor_seq bigint not null default 0,
  enabled boolean not null default true,
  disabled_reason text,
  failing_since timestamptz,
  last_success_at timestamptz,
  last_failure_at timestamptz
);
create index if not exists company_webhooks_company_idx on company_webhooks (company_id);
alter table company_webhooks enable row level security;
revoke all on table company_webhooks from anon, authenticated;
-- Never the secret: it is shown once, when made or rotated.
grant select (id, company_id, url, events, description, created_by, created_by_key, created_at, enabled,
              disabled_reason, failing_since, last_success_at, last_failure_at)
  on table company_webhooks to authenticated;
drop policy if exists "owner sees webhooks" on company_webhooks;
create policy "owner sees webhooks" on company_webhooks for select
  to authenticated using (coalesce((select company_role(company_id)) = 'owner', false));

create table if not exists company_webhook_deliveries (
  id uuid primary key default gen_random_uuid(),
  webhook_id uuid not null references company_webhooks(id) on delete cascade,
  company_id uuid not null references companies(id) on delete cascade,
  event_type text not null,
  row_id uuid,
  payload jsonb not null,
  status text not null default 'pending' check (status in ('pending', 'delivered', 'failed')),
  attempts int not null default 0,
  next_attempt_at timestamptz not null default now(),
  last_status int,
  last_error text,
  created_at timestamptz not null default now(),
  delivered_at timestamptz
);
create index if not exists company_webhook_deliveries_due_idx
  on company_webhook_deliveries (next_attempt_at) where status = 'pending';
create index if not exists company_webhook_deliveries_webhook_idx
  on company_webhook_deliveries (webhook_id, created_at desc);
create index if not exists company_webhook_deliveries_row_idx
  on company_webhook_deliveries (webhook_id, row_id) where status = 'pending' and attempts = 0;
alter table company_webhook_deliveries enable row level security;
revoke all on table company_webhook_deliveries from anon, authenticated;
grant select (id, webhook_id, company_id, event_type, row_id, status, attempts, next_attempt_at, last_status,
              last_error, created_at, delivered_at)
  on table company_webhook_deliveries to authenticated;
drop policy if exists "owner sees webhook deliveries" on company_webhook_deliveries;
create policy "owner sees webhook deliveries" on company_webhook_deliveries for select
  to authenticated using (coalesce((select company_role(company_id)) = 'owner', false));

-- An address the dispatcher may call: https on the normal port, a public
-- host name (no IP literal, no localhost or private suffix, no user:pass@).
-- The dispatcher also checks what the name resolves to before each send.
create or replace function webhook_url_ok(p_url text)
returns boolean language plpgsql immutable as $$
declare
  host text;
  port text;
begin
  if p_url is null or char_length(p_url) > 500 or p_url !~ '^https://[^/?#@\s\\]+(/[^\s]*)?$' then
    return false;
  end if;
  host := lower(substring(p_url from '^https://([^/?#:]+)'));
  port := substring(p_url from '^https://[^/?#:]+:([^/?#]*)');
  if port is not null and port <> '443' then return false; end if;
  if host is null or host !~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$' then
    return false;
  end if;
  if host ~ '^[0-9.]+$' or host ~ '\.(localhost|local|internal|intranet|lan|home|corp|private|arpa|test|invalid|example)$'
     or host in ('localhost', 'metadata.google.internal') then
    return false;
  end if;
  return true;
end $$;
revoke all on function webhook_url_ok(text) from public, anon;
grant execute on function webhook_url_ok(text) to authenticated, service_role;

create or replace function webhook_events_ok(p_events text[])
returns boolean language sql immutable as $$
  select p_events is not null and cardinality(p_events) between 1 and 30
     and not exists (select 1 from unnest(p_events) e
                      where e <> '*' and e not in (select resource from api_resources()));
$$;

-- Makes a webhook; returns its secret, shown once. p_key_id is set when a
-- key made it (through api_webhooks), otherwise the caller must be the owner.
create or replace function webhook_insert(p_company_id uuid, p_url text, p_events text[], p_description text,
                                          p_user uuid, p_key_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  w company_webhooks;
  ev text[] := case when '*' = any (coalesce(p_events, array['*'])) then array['*']
                    else (select array_agg(distinct e order by e) from unnest(p_events) e) end;
begin
  if not webhook_url_ok(btrim(coalesce(p_url, ''))) then
    raise exception 'The address must start with https:// and be a public web address.' using errcode = '22023';
  end if;
  if not webhook_events_ok(ev) then
    raise exception 'Pick what to send: all records, or some of %.', (select string_agg(resource, ', ') from api_resources())
      using errcode = '22023';
  end if;
  if (select count(*) from company_webhooks where company_id = p_company_id) >= 10 then
    raise exception 'A company can have 10 webhooks. Delete one first.' using errcode = '54000';
  end if;
  insert into company_webhooks (company_id, url, events, description, secret, created_by, created_by_key, cursor_seq)
  values (p_company_id, btrim(p_url), ev, nullif(left(btrim(coalesce(p_description, '')), 60), ''),
          'whsec_' || encode(extensions.gen_random_bytes(24), 'hex'), p_user, p_key_id,
          -- Starts from now, not from the company's whole history.
          (select coalesce(max(seq), 0) from sync_changes))
  returning * into w;
  return jsonb_build_object('id', w.id, 'url', w.url, 'events', to_jsonb(w.events), 'description', w.description,
                            'secret', w.secret, 'enabled', w.enabled, 'created_at', w.created_at);
end $$;
revoke all on function webhook_insert(uuid, text, text[], text, uuid, uuid) from public, anon, authenticated;

create or replace function webhook_owner_check(p_webhook_id uuid)
returns company_webhooks language plpgsql security definer set search_path = public as $$
declare
  w company_webhooks;
begin
  select * into w from company_webhooks where id = p_webhook_id;
  if w.id is null or (select auth.uid()) is null or coalesce(company_role(w.company_id) = 'owner', false) is not true then
    raise exception 'Only the company owner manages webhooks.' using errcode = '42501';
  end if;
  return w;
end $$;
revoke all on function webhook_owner_check(uuid) from public, anon, authenticated;

create or replace function create_company_webhook(p_company_id uuid, p_url text, p_events text[] default array['*'],
                                                  p_description text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if (select auth.uid()) is null or coalesce(company_role(p_company_id) = 'owner', false) is not true then
    raise exception 'Only the company owner manages webhooks.' using errcode = '42501';
  end if;
  return webhook_insert(p_company_id, p_url, p_events, p_description, (select auth.uid()), null);
end $$;

create or replace function delete_company_webhook(p_webhook_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform webhook_owner_check(p_webhook_id);
  delete from company_webhooks where id = p_webhook_id;
end $$;

-- Switching one back on starts from now: changes made while it was off are
-- not sent (the change feed still has them).
create or replace function set_company_webhook_enabled(p_webhook_id uuid, p_enabled boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform webhook_owner_check(p_webhook_id);
  update company_webhooks
     set enabled = coalesce(p_enabled, false),
         disabled_reason = case when coalesce(p_enabled, false) then null else 'Switched off by the owner' end,
         failing_since = null,
         cursor_seq = case when coalesce(p_enabled, false) and not enabled
                           then (select coalesce(max(seq), 0) from sync_changes) else cursor_seq end
   where id = p_webhook_id;
  if not coalesce(p_enabled, false) then
    update company_webhook_deliveries set status = 'failed', last_error = 'Webhook switched off'
     where webhook_id = p_webhook_id and status = 'pending';
  end if;
end $$;

create or replace function rotate_company_webhook_secret(p_webhook_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  s text := 'whsec_' || encode(extensions.gen_random_bytes(24), 'hex');
begin
  perform webhook_owner_check(p_webhook_id);
  update company_webhooks set secret = s where id = p_webhook_id;
  return s;
end $$;

-- Queues a "ping" event, sent on the next dispatch.
create or replace function send_company_webhook_test(p_webhook_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  w company_webhooks := webhook_owner_check(p_webhook_id);
  did uuid := gen_random_uuid();
begin
  if not w.enabled then
    raise exception 'Switch the webhook on first.' using errcode = '22023';
  end if;
  insert into company_webhook_deliveries (id, webhook_id, company_id, event_type, payload)
  values (did, w.id, w.company_id, 'ping', jsonb_build_object(
    'id', did, 'type', 'ping', 'created_at', now(), 'company_id', w.company_id,
    'data', jsonb_build_object('message', 'Test from FieldOS. Your webhook works.')));
  return did;
end $$;

revoke all on function create_company_webhook(uuid, text, text[], text), delete_company_webhook(uuid),
  set_company_webhook_enabled(uuid, boolean), rotate_company_webhook_secret(uuid), send_company_webhook_test(uuid)
  from public, anon;
grant execute on function create_company_webhook(uuid, text, text[], text), delete_company_webhook(uuid),
  set_company_webhook_enabled(uuid, boolean), rotate_company_webhook_secret(uuid), send_company_webhook_test(uuid)
  to authenticated;

-- Webhooks through a key (Zapier/Make subscribe and unsubscribe).
-- p_action: 'list', 'create' (p_body {url, events, description}), 'delete' (p_id).
create or replace function api_webhooks(p_key text, p_action text, p_id uuid default null,
                                        p_body jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  k company_api_keys := api_take_call(p_key);
  result jsonb;
  ev text[];
  gone uuid;
begin
  -- Even listing needs a write key: a Zapier or Make catch address is itself
  -- a credential, and a read key may sit with a BI vendor.
  if not ('write' = any (k.scopes)) then
    return jsonb_build_object('error', 'forbidden', 'message', 'Managing webhooks needs a key that can write.');
  end if;
  if p_action = 'list' then
    select coalesce(jsonb_agg(jsonb_build_object('id', id, 'url', url, 'events', to_jsonb(events),
             'description', description, 'enabled', enabled, 'disabled_reason', disabled_reason,
             'created_at', created_at, 'last_success_at', last_success_at, 'last_failure_at', last_failure_at)
             order by created_at), '[]'::jsonb)
      into result from company_webhooks where company_id = k.company_id;
    return jsonb_build_object('data', result);
  end if;
  if p_action = 'create' then
    if jsonb_typeof(coalesce(p_body, 'null'::jsonb)) <> 'object' then
      return jsonb_build_object('error', 'bad_request', 'message', 'Send a JSON object.');
    end if;
    begin
      ev := case
        when p_body->'events' is null then array['*']
        when jsonb_typeof(p_body->'events') = 'array'
          then array(select jsonb_array_elements_text(p_body->'events'))
        else null end;
      result := webhook_insert(k.company_id, p_body->>'url', ev, p_body->>'description', null, k.id);
    exception when sqlstate '22023' or sqlstate '54000' then
      return jsonb_build_object('error', 'bad_request', 'message', sqlerrm);
    end;
    insert into api_audit_log (company_id, key_id, key_name, action, resource, row_id)
    values (k.company_id, k.id, k.name, 'webhook_create', 'webhooks', (result->>'id')::uuid);
    return jsonb_build_object('data', result);
  end if;
  if p_action = 'delete' then
    delete from company_webhooks where id = p_id and company_id = k.company_id returning id into gone;
    if gone is null then
      return jsonb_build_object('error', 'not_found', 'message', 'Nothing here for this key.');
    end if;
    insert into api_audit_log (company_id, key_id, key_name, action, resource, row_id)
    values (k.company_id, k.id, k.name, 'webhook_delete', 'webhooks', gone);
    return jsonb_build_object('data', jsonb_build_object('id', gone, 'deleted', true));
  end if;
  return jsonb_build_object('error', 'bad_request', 'message', 'Unknown action.');
end $$;
revoke all on function api_webhooks(text, text, uuid, jsonb) from public, anon, authenticated;
grant execute on function api_webhooks(text, text, uuid, jsonb) to service_role;

-- Turns new sync_changes lines into deliveries for every switched-on
-- webhook, at most p_limit lines per webhook per call, leaving the last
-- p_settle_seconds for the next call (tests pass 0). A row that changes
-- again before its delivery is first tried is folded into that delivery, so
-- a burst of edits sends the latest state once. Returns deliveries queued.
drop function if exists webhook_enqueue(int);
create or replace function webhook_enqueue(p_limit int default 500, p_settle_seconds int default 10)
returns int language plpgsql security definer set search_path = public as $$
declare
  w company_webhooks;
  c record;
  last_seq bigint;
  obj jsonb;
  evt text;
  msg jsonb;
  did uuid;
  queued int := 0;
  head bigint;
  matched int;
  lim int := least(greatest(coalesce(p_limit, 500), 1), 5000);
begin
  -- One enqueuer at a time; a second caller just goes on to sending.
  if not pg_try_advisory_xact_lock(hashtext('fieldos_webhook_enqueue')) then
    return 0;
  end if;
  -- Lines up to here are read; a few seconds' lag lets transactions that
  -- took a lower seq commit first. Each webhook's cursor moves up to it even
  -- when none of the lines were its company's, so a quiet company never
  -- rescans everyone else's lines.
  select coalesce(max(seq), 0) into head from sync_changes where changed_at <= now() - make_interval(secs => greatest(coalesce(p_settle_seconds, 10), 0));
  for w in select * from company_webhooks where enabled order by id loop
    last_seq := w.cursor_seq;
    matched := 0;
    for c in
      select s.seq, s.row_id, s.op, s.project_id, s.changed_at, s.table_name, r.resource
        from sync_changes s
        join api_resources() r on r.table_name = s.table_name
       where s.seq > w.cursor_seq and s.seq <= head
         and (s.company_id = w.company_id
              or s.project_id in (select id from projects where company_id = w.company_id))
       order by s.seq
       limit lim
    loop
      matched := matched + 1;
      last_seq := c.seq;
      continue when not ('*' = any (w.events) or c.resource = any (w.events));
      obj := null;
      if c.op <> 'd' then
        execute format('select to_jsonb(t) from %I t where t.id = $1 and %s', c.table_name,
          case when c.table_name = 'projects' then 't.company_id = $2'
               else 't.project_id in (select id from projects where company_id = $2)' end)
          into obj using c.row_id, w.company_id;
      end if;
      evt := c.resource || case when c.op = 'd' or obj is null then '.deleted' else '.changed' end;
      did := null;
      select d.id into did from company_webhook_deliveries d
       where d.webhook_id = w.id and d.row_id = c.row_id and d.status = 'pending' and d.attempts = 0
       limit 1;
      msg := jsonb_build_object(
        'id', coalesce(did, gen_random_uuid()), 'type', evt, 'created_at', now(), 'company_id', w.company_id,
        'data', jsonb_build_object('resource', c.resource, 'id', c.row_id, 'project_id', c.project_id,
                                   'op', case when evt like '%.deleted' then 'deleted' else 'changed' end,
                                   'seq', c.seq, 'changed_at', c.changed_at, 'object', obj));
      if did is not null then
        update company_webhook_deliveries set event_type = evt, payload = msg where id = did;
      else
        insert into company_webhook_deliveries (id, webhook_id, company_id, event_type, row_id, payload)
        values ((msg->>'id')::uuid, w.id, w.company_id, evt, c.row_id, msg);
        queued := queued + 1;
      end if;
    end loop;
    if matched < lim then
      last_seq := greatest(last_seq, head);
    end if;
    if last_seq > w.cursor_seq then
      update company_webhooks set cursor_seq = last_seq where id = w.id;
    end if;
  end loop;

  -- Housekeeping, a little per call.
  delete from company_webhook_deliveries
   where id in (select id from company_webhook_deliveries
                 where status <> 'pending' and created_at < now() - interval '30 days' limit 1000);
  delete from api_idempotency where created_at < now() - interval '1 day';
  return queued;
end $$;

-- Hands the dispatcher up to p_limit due deliveries and leases them for
-- 2 minutes, so a second dispatcher running at once skips them.
create or replace function webhook_claim(p_limit int default 50)
returns table (id uuid, url text, secret text, event_type text, payload jsonb, attempts int)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
begin
  return query
  with due as (
    select d.id from company_webhook_deliveries d
      join company_webhooks w on w.id = d.webhook_id
     where d.status = 'pending' and d.next_attempt_at <= now() and w.enabled
     order by d.next_attempt_at
     limit least(greatest(coalesce(p_limit, 50), 1), 200)
     for update of d skip locked)
  update company_webhook_deliveries d
     set attempts = d.attempts + 1, next_attempt_at = now() + interval '2 minutes'
    from due, company_webhooks w
   where d.id = due.id and w.id = d.webhook_id
  returning d.id, w.url, w.secret, d.event_type, d.payload, d.attempts;
end $$;

-- What happened to one send. p_status: the HTTP status, or 0 when there
-- was no answer (timeout, refused, blocked address).
create or replace function webhook_report(p_delivery_id uuid, p_status int, p_error text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  d company_webhook_deliveries;
  -- wait after attempt n (1-based); 8 attempts over about a day and a half
  backoff interval[] := array['1 minute', '5 minutes', '30 minutes', '2 hours', '5 hours', '10 hours', '24 hours']::interval[];
begin
  select * into d from company_webhook_deliveries where id = p_delivery_id for update;
  if d.id is null or d.status <> 'pending' then return; end if;
  if p_status between 200 and 299 then
    update company_webhook_deliveries
       set status = 'delivered', delivered_at = now(), last_status = p_status, last_error = null
     where id = d.id;
    update company_webhooks set last_success_at = now(), failing_since = null where id = d.webhook_id;
    return;
  end if;
  update company_webhook_deliveries
     set last_status = p_status,
         last_error = left(coalesce(p_error, 'HTTP ' || p_status), 300),
         status = case when d.attempts >= 8 then 'failed' else 'pending' end,
         next_attempt_at = now() + backoff[least(greatest(d.attempts, 1), 7)]
   where id = d.id;
  update company_webhooks
     set last_failure_at = now(), failing_since = coalesce(failing_since, now())
   where id = d.webhook_id;
  update company_webhooks
     set enabled = false, disabled_reason = 'Failing for 3 days, so it was switched off'
   where id = d.webhook_id and enabled and failing_since < now() - interval '3 days';
  update company_webhook_deliveries set status = 'failed', last_error = 'Webhook switched off after failing for 3 days'
   where webhook_id = d.webhook_id and status = 'pending'
     and exists (select 1 from company_webhooks w where w.id = d.webhook_id and not w.enabled);
end $$;

revoke all on function webhook_enqueue(int, int), webhook_claim(int), webhook_report(uuid, int, text),
  webhook_events_ok(text[]) from public, anon, authenticated;
grant execute on function webhook_enqueue(int, int), webhook_claim(int), webhook_report(uuid, int, text)
  to service_role;

-- The clock. pg_cron runs webhook_tick() every minute: it queues new
-- deliveries in SQL, and only when something is due asks the
-- webhook-dispatch edge function (by pg_net) to send it. The function's
-- address is app_config.webhook_dispatch_url, set once per project:
--   update public.app_config
--      set webhook_dispatch_url = 'https://<project-ref>.supabase.co/functions/v1/webhook-dispatch';
-- Until it is set (and on a stack without pg_cron/pg_net) nothing is sent
-- by the clock; the app's "Send test" still calls the function itself.
alter table public.app_config add column if not exists webhook_dispatch_url text
  check (webhook_dispatch_url is null or webhook_dispatch_url ~ '^https?://');

create or replace function webhook_tick()
returns void language plpgsql security definer set search_path = public as $$
declare
  target text;
begin
  perform webhook_enqueue();
  select webhook_dispatch_url into target from app_config where id;
  if target is null or to_regnamespace('net') is null then return; end if;
  if exists (select 1 from company_webhook_deliveries d join company_webhooks w on w.id = d.webhook_id
              where d.status = 'pending' and d.next_attempt_at <= now() and w.enabled) then
    execute 'select net.http_post(url := $1, body := ''{}''::jsonb,
                                  headers := ''{"content-type": "application/json"}''::jsonb,
                                  timeout_milliseconds := 60000)' using target;
  end if;
end $$;
revoke all on function webhook_tick() from public, anon, authenticated;
grant execute on function webhook_tick() to service_role;

do $$
begin
  begin
    create extension if not exists pg_net with schema extensions;
  exception when others then
    raise notice 'pg_net not available (%); webhooks are sent only when webhook-dispatch is called', sqlerrm;
  end;
  begin
    create extension if not exists pg_cron;
  exception when others then
    raise notice 'pg_cron not available (%); webhooks are sent only when webhook-dispatch is called', sqlerrm;
  end;
  if to_regnamespace('cron') is not null then
    perform cron.unschedule(jobid) from cron.job where jobname = 'fieldos-webhook-tick';
    perform cron.schedule('fieldos-webhook-tick', '* * * * *', 'select public.webhook_tick()');
  end if;
end $$;
