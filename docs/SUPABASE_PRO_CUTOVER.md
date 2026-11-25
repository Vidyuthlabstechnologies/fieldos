# Supabase Pro cut-over checklist

Production project `qybjzrrledxzhrbamdcq` (organization "FieldOS", Mumbai).
Checked read-only on 26 Nov 2026: **Free plan behaviour, no backups, no
point-in-time recovery**, 3 companies, 2 projects, 21 MB. Plan: turn on Pro
billing about a week later, then open to paying customers. This is the order
to do things in. Plan prices and limits change; confirm each number on the
billing page, not here.

## Before billing day (no cost, do now)

| # | Step | Who | Done |
|---|---|---|---|
| 1 | Add a second human to the Supabase organization as **Owner** (issue #239). One non-owner member is the biggest bus-factor risk. | owner | |
| 2 | Create the repo secret `BACKUP_PASSPHRASE`: `openssl rand -base64 36`. Save it in the password manager first. Settings > Secrets and variables > Actions. | owner | |
| 3 | Run the **db-backup** workflow once by hand. Check the run is green and that Dashboard > Storage > `db-backups` has a file. | owner + agent | |
| 4 | Do one **restore drill** into a scratch project or local stack (`SUPABASE_PRODUCTION_RUNBOOK.md`, "Restoring a backup"). A backup nobody has restored is a hope. | agent | |
| 5 | Review and merge the server-hardening PRs: **#252** (guard PO and request updates, one live PO per request) and **#253** (change history for wages, attendance marks, POs; the history screen labels). **Do not deploy them yet.** The phone-only PRs (#248 cube wording, #250 consent wording, #254 stalled photos) can ship in the next app build. | owner | |
| 6 | Pick the app-side build that ships with the wage change (1.8.1+26 is already built) and get it to every real tester on Play. | owner | |
| 7 | Decide the product questions in `CUSTOMER_REVIEW_2026-11.md` that affect launch: trial length, paywall order, phone-number sign-in. | owner | |

## Billing day

1. Dashboard > Organization FieldOS > Billing: upgrade to **Pro**. Leave the
   spend cap on, and set a usage alert email to info@mldynamic.com (issue #148 step 4).
2. Check backups started: `supabase backups list --remote=qybjzrrledxzhrbamdcq`
   should list daily backups within a day (today it returns `backups: []`).
3. Decide on **point-in-time recovery** (a paid add-on that also needs a
   larger compute size). With daily backups plus `db-backup`, you can lose up
   to about a day. PITR cuts that to minutes. Worth it once paying
   customers record wages and bills daily.
4. Auth > Providers/Email: switch on **leaked-password protection** (Pro).
   Raise the minimum password length above 6 (Auth > Policies).
5. **Custom SMTP** and email confirmation back on (issue #147). The built-in
   mailer is rate-limited and is not meant for production.
6. Storage: note the file-size limit and the storage quota; photos are what
   will grow.
7. Run `supabase db advisors --remote=qybjzrrledxzhrbamdcq`: no ERROR items,
   and the leaked-password warning gone.

## After billing day: deploy the hardening, with a safety net in place

Why after: a bad migration is exactly what backups are for. Take a manual
**db-backup** run first, then:

1. Run **supabase-deploy** (applies the merged migrations), then **isolation-check**.
2. Wage cut-over (`HANDOVER.md`, "Wage rates: the two-step cut-over"):
   raise `min_build_android/min_build_ios` to 26, wait a day, copy
   `supabase/deferred/20261125150001_revoke_workers_wage_read.sql` into
   `supabase/migrations/` with a new timestamp, deploy, run isolation-check,
   confirm as an engineer account that `select daily_wage from workers` is
   refused and a 1.8.1 phone still syncs. With 3 companies today this is
   cheap; it gets harder with every customer on an old build.
3. `edge functions`: **functions-deploy** / **ai-assistant-deploy** for any
   function change that was merged.
4. Tick issues #148 and #147, and update `HANDOVER.md`.

## Text that must change when Pro is on

- `website/privacy-policy.html` line 79 says deleted data may stay in
  automatic backups "for up to 30 days". Truth after this change: Supabase
  keeps its daily backups for a fixed number of days (check the plan), and
  `db-backup` keeps encrypted copies for 35 days. Write the longest of them.
  (The website deploys from the separate `fieldos-mldynamic` repo, and it is
  legal text: the owner or the lawyer edits it.)
- Terms and the CFO answers (RPO/RTO): with Pro daily backups and `db-backup`,
  the honest answer is RPO about 24 hours, RTO several hours by hand. With
  PITR, RPO is minutes. Do not publish a number you have not drilled.

## Still not covered even on Pro

- **Storage files** (photos, bills, selfies, documents) are not in database
  backups. A deleted or overwritten file is gone. Decide on a second copy
  (another provider's bucket, or a periodic download) before customers
  depend on bill photos as evidence.
- **Losing the Supabase project itself** takes the `db-backups` bucket with
  it. Keep a hand-downloaded copy somewhere else now and then.
