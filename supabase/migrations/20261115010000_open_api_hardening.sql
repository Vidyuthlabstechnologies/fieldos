-- Open API hardening (security review of 20261115000000_open_api):
--  - the per-key limit is counted in one locking UPDATE, so parallel calls
--    cannot all read the same count and slip past 120 a minute;
--  - not_found, bad_cursor and unknown_resource come back as {"error": ...}
--    instead of raising, so those calls still count toward the limit (a
--    raise would roll the count back).
-- Same signature and grants as before.

-- One read through a key.
--   p_resource 'changes': the change feed after seq p_after (a number).
--   otherwise: rows of that resource ordered by id, after id p_after, or the
--   one row p_id; p_project narrows to one site.
-- Returns {"data": [...], "next": cursor or null}, or {"error": code} for a
-- counted call that found nothing. A bad or revoked key, or one over its
-- limit, raises invalid_key or rate_limited instead.
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
  -- Counted in one locking UPDATE, so parallel calls cannot all slip under
  -- the limit by reading the same count.
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
