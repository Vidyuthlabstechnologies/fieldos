# Open API

REST and webhooks for a company's own integrations: accounts software, ERP,
BI dashboards, planning tools, Zapier or Make. Built in global gap 6
(`/mnt/project-files/strategy/global-gap-analysis.md`).

- Read every site record (21 resources) and a change feed.
- Create and update **tasks** and **issues** with a key that can write.
- **Webhooks**: FieldOS calls your https address, signed, as soon as a record
  changes; retried for about a day and a half.
- A machine-readable description: `GET /v1/openapi.json` (OpenAPI 3.1, no
  key needed; copy in [`docs/openapi.json`](openapi.json)). Import it into
  Postman, Insomnia, Zapier's or Make's app builders, or a code generator.

## Keys

The company **owner** makes keys in the app: Settings > API keys. A key looks
like `fos_` followed by 48 hex characters. It is shown once; the server keeps
only its SHA-256, and the owner sees its first 12 characters, its name, when
it was last used, whether it can write, and can revoke it. Up to 10 keys in
use per company.

| Scope | Can |
|---|---|
| read (default) | read the company's sites and records and the change feed |
| read and write | the above, plus create and update tasks and issues, and list, add or delete webhooks |

A key only ever sees its own company. Keys made before scopes existed are
read only. Every write is logged with the key's name; the owner sees the
latest under "Changed through the API" on the API keys screen.

## Calling it

```
https://<project>.supabase.co/functions/v1/public-api/v1/<resource>
Authorization: Bearer fos_...        (or  x-api-key: fos_...)
```

### Read

| Path | Returns |
|---|---|
| `GET /v1` | the list of resources (also checks the key) |
| `GET /v1/<resource>` | `{"data": [...], "next": "<id>" or null}`, ordered by id |
| `GET /v1/<resource>/<id>` | `{"data": {...}}` |
| `GET /v1/changes` | the change feed: `{"data": [{"seq", "resource", "id", "op", "changed_at"}], "next"}` |

Query parameters: `project_id` (one site), `after` (the `next` from the
previous page), `limit` (1 to 500, default 100).

Resources: `projects`, `tasks`, `issues`, `daily_reports`, `inspections`,
`approvals`, `rfis`, `submittals`, `defects`, `drawings`,
`drawing_revisions`, `hold_points`, `handover_units`, `constraints`,
`attendance`, `material_receipts`, `purchase_orders`, `expenses`,
`client_bills`, `supplier_invoices`, `payments_received`. Each row is the
server row as the phones sync it (snake_case columns).

### Write (keys that can write)

| Call | Body |
|---|---|
| `POST /v1/tasks` | `project_id`, `title` (required); `status` (`todo`, `in_progress`, `done`, `blocked`), `priority` (`high`, `normal`, `low`), `progress` (0-100), `start_date`, `due_date` (`YYYY-MM-DD`) |
| `PATCH /v1/tasks/<id>` | any of the above except `project_id` |
| `POST /v1/issues` | `project_id`, `description` (required); `severity` (`low`, `medium`, `high`, `critical`), `status` (`open`, `in_progress`, `resolved`, `closed`) |
| `PATCH /v1/issues/<id>` | any of the above except `project_id`; `resolved`/`closed` sets `resolved_at` |

Send `Content-Type: application/json`. POST answers 201, PATCH 200, both with
`{"data": <the row>}`. Any other field (ids, timestamps, a different site) is
refused with 400 naming it, so a typo never silently does nothing. Nothing
can be deleted through the API.

**Retries**: send `Idempotency-Key: <your id>` (1 to 100 characters) with a
POST. Sent again within a day with the same body, the first answer comes back
and no second row is made; with a different body it is 409
`idempotency_conflict`.

Rows written through the API reach the team's phones on their next sync, like
a change made on another phone. A phone that changed the same row offline and
syncs later wins, as it does between two phones.

```bash
curl -X POST "$BASE/v1/tasks" \
  -H "Authorization: Bearer $FIELDOS_KEY" -H "Content-Type: application/json" \
  -H "Idempotency-Key: primavera-act-1042" \
  -d '{"project_id": "…", "title": "Pour 3rd floor slab", "due_date": "2026-12-05"}'
```

### Keeping a copy in step (polling)

1. Page through each resource once.
2. Remember the last `seq` of `/v1/changes`, then poll `/v1/changes?after=<seq>`.
   For each entry with `op: "changed"`, fetch `/v1/<resource>/<id>`; for
   `"deleted"`, drop it.

Webhooks (below) save the polling.

## Webhooks

The owner adds them in the app (Settings > Webhooks), or a write key adds
them through the API (all webhook calls need a write key), which is how Zapier and Make "instant" triggers
subscribe and unsubscribe:

| Call | |
|---|---|
| `GET /v1/webhooks` | the company's webhooks |
| `POST /v1/webhooks` | `{"url": "https://…", "events": ["approvals", "client_bills"], "description": "Zapier"}`; `events` defaults to `["*"]` (everything). Answer 201 has the `secret`, shown only this once. |
| `DELETE /v1/webhooks/<id>` | unsubscribe |

Up to 10 per company. The address must be `https://` on the normal port, a
public host name (no IP address, `localhost`, `.local`, `.internal` and the
like, no `user:pass@`). Before every send the dispatcher also checks what the
name resolves to and refuses private, loopback and link-local addresses, and
it never follows redirects.

### What arrives

```http
POST /your/path
Content-Type: application/json
FieldOS-Event-Id: 6f1c…           (same on every retry: drop repeats by it)
FieldOS-Event-Type: tasks.changed
FieldOS-Signature: t=1763740800,v1=5d41…

{
  "id": "6f1c…", "type": "tasks.changed", "created_at": "…", "company_id": "…",
  "data": {"resource": "tasks", "id": "…", "project_id": "…", "op": "changed",
           "seq": 81234, "changed_at": "…", "object": { …the row… }}
}
```

`type` is `<resource>.changed`, `<resource>.deleted` (then `object` is null),
or `ping` (the app's "Send a test"). If a row changes several times before
its event is first sent, you get one event with the latest row. Events can
arrive out of order: compare `data.seq`.

**Check the signature**: `v1` is the hex HMAC-SHA256 of `"<t>.<raw body>"`
with the webhook's `whsec_…` secret. Reject a `t` more than 5 minutes old.

```js
const [, t, v1] = /t=(\d+),v1=([0-9a-f]+)/.exec(req.headers["fieldos-signature"]);
const want = crypto.createHmac("sha256", secret).update(`${t}.${rawBody}`).digest("hex");
const ok = crypto.timingSafeEqual(Buffer.from(v1), Buffer.from(want)) && Date.now() / 1000 - t < 300;
```

**Answer 2xx within 10 seconds.** Anything else (including a redirect) is
retried after 1, 5 and 30 minutes, then 2, 5, 10 and 24 hours: 8 tries. A
webhook failing for 3 days in a row is switched off; the owner sees why and
switches it back on (it then starts from that moment; the change feed still
has what was missed). The owner can also send a test, see the last 20
deliveries and make a new secret (the old one stops at once).

### How sending works

No server of ours runs in the background. Every minute pg_cron runs
`webhook_tick()`: it turns new `sync_changes` lines into deliveries in SQL,
and only when one is due asks the `webhook-dispatch` edge function (through
pg_net) to send them. The function's address is set once per Supabase
project:

```sql
update public.app_config
   set webhook_dispatch_url = 'https://<project-ref>.supabase.co/functions/v1/webhook-dispatch';
```

Until it is set nothing is sent by the clock (the app's "Send a test" still
calls the function itself).

## Errors

`{"error": "<code>", "message": "..."}` with: 401 `invalid_key`,
403 `forbidden` (a read key tried to write), 429 `rate_limited`
(120 calls a minute per key, shared by reads, writes and webhook calls;
`retry-after: 60`), 404 `not_found` / `unknown_resource`,
400 `bad_cursor` / `bad_request` (the message names the field),
405 `not_writable` or a wrong method, 409 `idempotency_conflict`,
413 body over 32 KB, 415 not JSON.

## How it is built

- `supabase/migrations/20261115000000_open_api.sql` (+ `_hardening`):
  `company_api_keys`, `create_company_api_key` / `revoke_company_api_key`
  (owner only), `api_resources()` (the fixed list) and `api_read()`, which only
  the service role may call.
- `supabase/migrations/20261121190000_open_api_writes_webhooks.sql`: key
  `scopes`; `api_take_call()` (the one locking rate-limit count every call
  goes through); `api_write()` with the fixed field list `api_writable()`,
  `api_audit_log` and `api_idempotency`; `company_webhooks` (secret never
  granted to the app), `company_webhook_deliveries`, the owner functions
  (`create_company_webhook`, `set_company_webhook_enabled`,
  `rotate_company_webhook_secret`, `send_company_webhook_test`,
  `delete_company_webhook`), `api_webhooks()` for keys, and the service-role
  queue: `webhook_enqueue`, `webhook_claim` (leases due deliveries with
  `skip locked`, so two senders never double-send), `webhook_report`
  (backoff, giving up, switching off), `webhook_tick` + the pg_cron job.
- `supabase/functions/public-api/`: routing and error mapping (`core.ts`,
  tested by `core_test.ts`), the OpenAPI description (`openapi.ts`; `deno task
  openapi` rewrites `docs/openapi.json`, and a test checks they match).
- `supabase/functions/webhook-dispatch/`: signing, address checks and sending
  (`core.ts`, `core_test.ts`); `local_test.ts` runs a write through to a
  signed delivery against the local stack (`LOCAL_STACK=1 deno test -A
  local_test.ts`).
- Both functions are deployed with `--no-verify-jwt` by `functions-deploy.yml`.
- Phone: `lib/features/settings/api_keys_screen.dart`,
  `lib/features/settings/webhooks_screen.dart` (labels in
  `lib/l10n/strings_integrations.dart`).
- Tests: `fieldos_mobile/test/open_api_cycle_test.dart` (local stack: two
  companies, owner only, paging, change feed, revoke, writes and isolation,
  phones pulling API writes, webhook queue, retries and giving up),
  `test/api_keys_screen_test.dart`, `test/webhooks_screen_test.dart`.

Later: writes for more records (payments received, supplier invoice status)
once an ERP pilot says which, and a Zapier/Make app built on
`openapi.json`.
