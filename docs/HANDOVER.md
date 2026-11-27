# FieldOS handover (current state)

**Read this first.** It is the one page kept current for whoever (person or
coding agent) takes the project over. Last updated 2026-11-27, app **1.8.3+28**,
phone database schema **45**, 77 Supabase migrations, all of them live on
production except those in `supabase/deferred/`.

Anything older that disagrees with this page is out of date. The older
`docs/AGENT_HANDOFF.md` and `docs/COMPLETION_PLAN.md` describe August 2026
and are kept only for history.

## What the product is

FieldOS is a construction-site app for Indian builders and contractors (and,
from the same code, US, Malaysia, UAE and UK markets). The **Flutter phone
app** (`fieldos_mobile/`, app id `com.mldynamic.fieldos`) is the product: it
works fully offline on a local Drift database and syncs through **Supabase**
(Postgres + RLS + a few edge functions, Mumbai region). Around it:

| Folder | What it is |
|---|---|
| `fieldos_mobile/` | The phone app (Android main, iOS supported). All active work. |
| `supabase/` | `migrations/` (applied in filename order), `functions/` (edge functions), `tests/` (SQL tests), `deferred/` (migrations written but NOT to be deployed yet). |
| `office/` | React + TypeScript office web app at `/office/` on the website (same Supabase project and RLS). |
| `website/` | Static marketing site, privacy policy, terms, owner dashboard. Deploys from the separate repo `varshinicb1/fieldos-mldynamic` on push (Netlify). |
| `fieldos/`, `frontend/`, `src-tauri/`, `api.py` | The older offline Windows desktop app (FastAPI + Next.js + Tauri). Static; not the product. |
| `tools/` | Operational scripts: isolation check, pilot check, log export, launch readiness, string generators. |
| `docs/` | Feature and operations docs (index: `docs/README.md`). |
| `resources/` | Gitignored client data. Never commit, log or quote it. |

Company: ML Dynamic Solutions Private Limited (Hyderabad). Support
info@mldynamic.com. Pricing: no free tier, 3-day trial, then a store
subscription; company plans are invoiced outside the stores. Prices never
appear in sales material or in the apps' company-plan screens.

## Working in the repo

Branches: `master` is the main branch. Work on a branch, open a PR, merge.
**No GitHub Actions run on push or PR** (issue #149): every workflow is
`workflow_dispatch`, started by hand from the Actions tab (or the API).

Local checks, from `fieldos_mobile/`:

```bash
flutter pub get
flutter analyze
flutter test                      # sync/cloud tests skip themselves without the local stack
```

To run the whole suite including the two-phone cloud tests, start the local
stack first: `supabase start` (repo root), then
`eval "$(supabase status -o env)"` as the `mobile.yml` workflow does. The
`mobile` workflow does exactly this on a runner and is the reference run.

Other checks: `deno test` in each `supabase/functions/*`; SQL tests in
`supabase/tests/` against a local Postgres (`psql -v ON_ERROR_STOP=1 -f ...`,
each ends with "... passed" and rolls itself back); `office/`:
`npm ci && npm run typecheck && npm run test:e2e` (needs the local stack);
backend: `pytest tests/` with the repo venv.

Conventions that bite (details in `AGENTS.md`):

- Labels are English keys translated through tables in `lib/l10n/`.
  `l10n_coverage_test` and `market_terms_test` fail when a label is missing
  in any language (five Indian + eight international). The site-operations
  tables are generated: edit `tools/siteops_strings/` (Hindi, Telugu, Tamil,
  Kannada, Marathi) and `tools/siteops_strings_intl/` (Spanish, Arabic,
  Malay, Urdu, Chinese, Malayalam, Polish, Romanian), then
  `python3 tools/gen_siteops_strings.py`.
- Never hard-code the rupee sign, GST, lakh or a date order: use `money()`,
  `fmtDate()`, `market` (`lib/core/market.dart`) and `market_terms.dart`.
- Every Drift `schemaVersion` bump needs an `if (from < N)` upgrade step and
  must pass `shipped_schema_upgrade_test`.
- A server-side rule is always enforced twice: on the phone and in an RLS
  policy or trigger. Never rely on the phone alone.
- Money visibility: owners, project managers and accounts see a site's
  expenses; engineers and others see only expenses they recorded. Wage rates
  likewise. Money received from the client (and the client's bills) is
  owner and project manager only, on the phone and in the server's policy.
- Sales and outreach material never states prices. No real call or WhatsApp
  to a prospect without the owner's OK.
- Never commit secrets. Names of every secret are listed below; values live
  only in GitHub secrets, Supabase function secrets and the owner's password
  manager.

## Environment, secrets and variables (names only)

GitHub **secrets**: `SUPABASE_URL`, `SUPABASE_ANON_KEY` (public anon key
only, never service_role), `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD`,
`REVENUECAT_ANDROID_KEY`, `REVENUECAT_IOS_KEY` (public SDK keys),
`REVENUECAT_SECRET_KEY`, `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS`,
`ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `PLAY_SERVICE_ACCOUNT_JSON`
(not set yet: see "Owner steps"), `ANTHROPIC_API_KEY`, `SARVAM_API_KEY`,
`GOOGLE_WEB_CLIENT_SECRET`, `GITHUB_ISSUES_TOKEN` (not set yet),
`SECRETS_WRITE_TOKEN`.

GitHub **variables**: `LINUX_RUNNER`, `GOOGLE_WEB_CLIENT_ID`, `TERMS_URL`,
`PRIVACY_POLICY_URL`, `UPLOAD_KEY_SHA1`, `AI_MODEL`, `AI_USD_INR`,
`AI_MONTHLY_BUDGET_INR`, `AI_DAILY_CHAT_CALLS`.

Edge-function environment: `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
`SUPABASE_SERVICE_ROLE_KEY` (injected by Supabase), `GITHUB_ISSUES_TOKEN`,
`GITHUB_REPOSITORY`, plus the AI keys copied by `ai-assistant-deploy`.

Build-time defines for the app: `FIELDOS_MARKET` (`in|us|my|ae|uk`),
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `REVENUECAT_*_KEY`, `GOOGLE_WEB_CLIENT_ID`,
`TERMS_URL`, `PRIVACY_POLICY_URL`. `launch-readiness` reports which are set.

Production: Supabase project `qybjzrrledxzhrbamdcq` (organization "FieldOS";
only one human member so far: issue #239). Google Cloud project `vidyuthlabs`.

## Runbooks

### Deploy a database change (Supabase)

1. Add `supabase/migrations/<yyyymmddhhmmss>_name.sql`. Make it idempotent
   (`create or replace`, `if not exists`) and additive. If it would break
   builds in the field, do NOT ship it as is: use the two-step pattern below.
2. Test it on a local stack (`supabase db reset`) and add a SQL test in
   `supabase/tests/` for any RLS or trigger rule.
3. Merge the PR. Run workflow **supabase-deploy** (applies every file the
   project lacks, never `seed.sql`). Then run **isolation-check** (two
   throwaway companies prove no cross-company reads or writes).
4. Edge functions: **functions-deploy** (small ones) or
   **ai-assistant-deploy** (AI assistant; run after supabase-deploy).
5. Tick the migration off in issue **#132** (one line each: file, PR, run
   links). Never open a new issue for a migration.
6. One-off settings that are not migrations: **supabase-prod-settings**
   (webhook sender URL, auth redirects, signup toggle, selfie purge).

### Raise the minimum app build (stop old builds syncing)

`update public.app_config set min_build_android = <build>, min_build_ios =
<build>, message = '<short reason>';` in the SQL editor (service role). Old
phones stop syncing, keep their data and show an Update banner. 0 turns it
off. Do this before any server change older builds cannot survive.

### Wage rates: the two-step cut-over

Goal: stop site members who may not see money from reading
`workers.daily_wage` through the API.

1. **Done, live:** `20261125150000_worker_wage_rates.sql` adds
   `worker_wage_rates()`, which returns rates only to owners, project
   managers and accounts. From build 26 (1.8.1) the phone pulls workers
   *without* the wage column, reads rates through the function, and clears
   rates it may not see. Older builds keep working unchanged.
2. **Done 27 Nov 2026** (`20261128120000_revoke_workers_wage_read.sql`,
   steps below were followed; production had no users on older builds):
   it revokes read of the whole `workers` table and grants every column except
   the wage. After it, any build below 26 gets `42501` on its workers pull.
   Do it only when: 1.8.1 is live on Play and customers have it
   (`select` active builds from `member_sync_status`/support), then (a)
   `update app_config set min_build_android = 26, min_build_ios = 26,
   message = 'Update FieldOS to keep syncing.'`, (b) wait a day for phones to
   see it, (c) copy the file into `supabase/migrations/` with a new
   timestamp, deploy, run isolation-check, (d) confirm as an engineer account
   that `select daily_wage from workers` is refused and that sync still
   works on a 1.8.1 phone. Any later column added to `workers` must also be
   granted: `grant select (col) on workers to authenticated;`.

### Release the Android app (Play)

The Play account is a personal account: production needs 12 testers opted in
for 14 days, so releases go to closed testing first.

1. Bump `version:` in `fieldos_mobile/pubspec.yaml` (`1.8.1+26`: the number
   after `+` is the versionCode and must rise every upload).
2. Run **mobile** (full tests against a local stack) on the branch; merge.
3. Run **play-upload** with track `build only`: builds the signed bundle and
   checks package name, versionCode and the upload-key SHA-1
   (`93:C0:C1:A6:14:D8:2E:C3:29:02:FF:C2:10:F0:9D:D8:18:7E:4D:A4`). Download
   the artifact; save it with SHA256SUMS in project files `launch/vX.Y.Z/`.
4. Upload to Play: with `PLAY_SERVICE_ACCOUNT_JSON` set, rerun play-upload
   with track `alpha`, status `draft`; otherwise drag the `.aab` into Play
   Console > Testing > Closed testing. Press "Send for review" there.
5. Never lose the upload keystore or its passwords: Play only accepts
   updates signed with the same key.
Details and the failure table: `docs/PLAY_STORE_LAUNCH.md` section 10.

### Other routine jobs

- `tools/pilot_check.py` (local, public key pair): a throwaway company walks
  every flow against production, then deletes itself. Run before onboarding.
- `db-backup` workflow: a daily encrypted copy of the database in the
  private `db-backups` bucket (35 days). Needs the secret `BACKUP_PASSPHRASE`;
  until it is set the run only warns. Restore steps and what it does not
  cover: `docs/SUPABASE_PRODUCTION_RUNBOOK.md`. Moving production to Pro
  (backups, leaked-password protection, SMTP): `docs/SUPABASE_PRO_CUTOVER.md`.
- `system-logs` workflow: copies Supabase logs to a private bucket every 6
  hours (one-year retention for CERT-In and DPDP). `tools/export_logs.py`.
- `bug-reports` / `report-to-github`: in-app bug reports become issues
  labelled `bug-report` (needs `GITHUB_ISSUES_TOKEN`).
- Account deletion: `account-cleanup` function plus `delete-account.html`.

## What was built recently

- 1.8.0 (PR #241): pre-construction tracker (approvals, GFC drawings,
  liaison time and cost), quality tests with 7/14/28-day cube reminders,
  safety breach log, security gate (frisk, breathalyser, punch) and the
  `security` and `quality_officer` site roles, stage checklists with
  on-site verification, four expense heads and finance privacy, value
  engineering, client milestones, client-supplied stock. Docs:
  `docs/SITE_EXECUTION.md`.
- 1.8.1: all 214 new labels in the eight international languages; wage rates
  pulled through `worker_wage_rates()` (step 1 above).
- Earlier: India compliance (consent records, selfies deleted after
  verification, grievance officer, 1-year logs: `docs/` and
  `compliance/india/` in project files), open API and webhooks
  (`docs/OPEN_API.md`), office web app, AI assistant (`docs/AI_ASSISTANT.md`),
  company plans (`docs/COMPANY_PLANS.md`), markets (`docs/MARKETS.md`).

## Open items

Owner (cannot be done from code):

- Supabase organization has one member who is not the company owner: issue
  **#239** (invite the owner as Owner). Highest risk on the list.
- Play: add repo secret `PLAY_SERVICE_ACCOUNT_JSON`; complete closed-test
  review with 12 testers for 14 days; Data safety and App content (issue
  #141, reviewer code); licence testers; RevenueCat iOS key and entitlement
  checks (issue #51).
- Repo secret `GITHUB_ISSUES_TOKEN` (fine-grained, Issues read/write), then
  run functions-deploy once.
- Supabase plan: Pro, backups, custom SMTP, email confirmation (issues #147,
  #148). Email sign-up off only after customers have 1.7.9 or newer (#228).
- Office web app redirect URL and Google origin (#216) were set by the
  settings workflow on 2026-11-23; close it after a sign-in check.

Decisions for the owner, deliberately not built:

- **AI face matching at the security gate.** It would process biometric
  data. The published privacy policy and the Play data-safety answers say
  selfies are deleted straight after verification and nothing is matched or
  stored. Building it needs a policy and consent change, a lawyer's view
  under the DPDP Act, and a Data-safety update. Tell an agent explicitly to
  proceed before starting.
- Real white-label (own app id, listing, domain) is not built; only PDF logo,
  colours and footer are. Pricing for it is a proposal only (project files
  `sales/pricing/`).
- Prices for international markets are not approved.

Bugs: none known and open in code. In-app reports arrive as issues labelled
`bug-report`. Issue #95 is a stale RevenueCat configuration report from an
early test build.

## Where things are decided or recorded

`AGENTS.md` (conventions and rules), `docs/SUPABASE_PRODUCTION_RUNBOOK.md`
(first-time Supabase setup), `docs/PLAY_STORE_LAUNCH.md`,
`docs/APP_STORE_LAUNCH.md`, `docs/INCIDENT_RESPONSE.md`,
`docs/BACKUP_RESTORE.md`, `docs/TROUBLESHOOTING.md`. Project files (shared
folder, not in git): `launch/vX/` signed bundles, `sales/`, `marketing/`,
`brand-kit/`, `compliance/`, `pilots/` (private logins).
