# Open API

Read-only REST for a company's own integrations: accounts software, ERP,
BI dashboards, Zapier or Make. Built in global gap 6
(`/mnt/project-files/strategy/global-gap-analysis.md`).

## Keys

The company **owner** makes keys in the app: Settings > API keys. A key looks
like `fos_` followed by 48 hex characters. It is shown once; the server keeps
only its SHA-256, and the owner sees its first 12 characters, its name, when
it was last used, and can revoke it. Up to 10 keys in use per company.
A key reads that company's sites only and can change nothing.

## Calling it

```
GET https://<project>.supabase.co/functions/v1/public-api/v1/<resource>
Authorization: Bearer fos_...        (or  x-api-key: fos_...)
```

| Path | Returns |
|---|---|
| `/v1` | the list of resources (also checks the key) |
| `/v1/<resource>` | `{"data": [...], "next": "<id>" or null}`, ordered by id |
| `/v1/<resource>/<id>` | `{"data": {...}}` |
| `/v1/changes` | the change feed: `{"data": [{"seq", "resource", "id", "op", "changed_at"}], "next"}` |

Query parameters: `project_id` (one site), `after` (the `next` from the
previous page), `limit` (1 to 500, default 100).

Resources: `projects`, `tasks`, `issues`, `daily_reports`, `inspections`,
`approvals`, `rfis`, `submittals`, `defects`, `drawings`,
`drawing_revisions`, `hold_points`, `handover_units`, `constraints`,
`attendance`, `material_receipts`, `purchase_orders`, `expenses`,
`client_bills`, `supplier_invoices`, `payments_received`. Each row is the
server row as the phones sync it (snake_case columns).

### Keeping a copy in step

1. Page through each resource once.
2. Remember the last `seq` of `/v1/changes`, then poll `/v1/changes?after=<seq>`.
   For each entry with `op: "changed"`, fetch `/v1/<resource>/<id>`; for
   `"deleted"`, drop it.

This is how a Zapier or Make "new or updated record" trigger polls.

### Errors

`{"error": "<code>", "message": "..."}` with: 401 `invalid_key`,
429 `rate_limited` (120 calls a minute per key, `retry-after: 60`),
404 `not_found` / `unknown_resource`, 400 `bad_cursor` / `bad_request`,
405 for anything but GET.

## How it is built

- `supabase/migrations/20261115000000_open_api.sql`: `company_api_keys`,
  `create_company_api_key` / `revoke_company_api_key` (owner only),
  `api_resources()` (the fixed list) and `api_read()`, which only the service
  role may call. It checks the key, counts the call, and reads only rows of
  the key's company (projects by `company_id`, the rest by `project_id` in
  the company's projects). The change feed is `sync_changes`, filtered the
  same way.
- `supabase/functions/public-api/`: routing and error mapping (`core.ts`,
  tested by `core_test.ts`), deployed with `--no-verify-jwt` by
  `functions-deploy.yml` because callers use a company key, not a sign-in.
- Phone: `lib/features/settings/api_keys_screen.dart`.
- Tests: `fieldos_mobile/test/open_api_cycle_test.dart` (local stack: two
  companies, owner only, paging, change feed, revoke) and
  `test/api_keys_screen_test.dart`.

Later: webhooks pushed on approvals and bills (built on the same change
feed), and write endpoints.
