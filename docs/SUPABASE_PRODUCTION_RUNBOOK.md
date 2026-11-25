# Supabase production runbook — the 15-minute cutover

Everything below is a **user action** (account ownership rule); this doc
exists so that when you do it, nothing else needs inventing. The sync layer,
schema, RLS, and Storage bucket are all tested against an identical local
stack — production is configuration, not new engineering.

## 1. Create the project (your account)

1. Sign up at https://supabase.com. The Free plan is fine for building and
   closed testing, but it has **no backups**: move the project to Pro before
   the first paying customer (checklist: `SUPABASE_PRO_CUTOVER.md`).
2. New project → pick a region close to your sites (Mumbai for Hyderabad
   crews), set a strong DB password, save it.

## 2. Apply the schema + RLS + Storage

Either:

- **GitHub Actions (no tools to install):** add the repo secrets
  `SUPABASE_URL`, `SUPABASE_ACCESS_TOKEN` and `SUPABASE_DB_PASSWORD`
  (`tools/set_launch_secrets.sh` does all of them from one file; owner only),
  then run the **supabase-deploy** workflow from the Actions tab. The
  **launch-readiness** workflow afterwards confirms the tables are there.

- **CLI (keeps migrations canonical):**
  ```bash
  supabase link --project-ref <project-ref>
  supabase db push
  ```
  (`project-ref` is in the dashboard URL.) This applies every file in
  `supabase/migrations/` in order, including the storage bucket and its
  policies.

- **Dashboard:** SQL Editor → paste each migration file's contents in
  filename order → run.

Verify afterwards: Table Editor shows all ~31 tables; Storage shows the
private `documents` bucket.

## 3. Accounts: one per person

There is no shared account any more. Each person signs up from the app
(Team & sync, "Create account") with their own email. For launch, turn
"Confirm email" **off** in Authentication -> Providers -> Email (see
`docs/PLAY_STORE_LAUNCH.md` section 1): Supabase's built-in mailer sends
only a few emails an hour, and company data is already gated by the join
code. Turn it back on once custom SMTP is configured; the app then asks
for the code from the confirmation email.

**Emails carry codes, not links.** The app's "Forgot password?" (and the
sign-up confirmation, when it is on) asks the person to type the 6-digit
code from the email. Supabase's default emails send a link to the Site URL
instead, which is not the app. So:

1. Authentication -> Email Templates -> **Reset password**: subject "Your
   FieldOS password reset code", body = `supabase/templates/recovery.html`.
2. Same page, **Confirm signup**: subject "Your FieldOS code", body =
   `supabase/templates/confirmation.html`.
3. Authentication -> SMTP Settings: set up a real sender (for example
   Amazon SES or Resend, from `noreply@` a domain you own). Supabase's
   built-in mailer only delivers to the project's own team members, so
   without this nobody else gets a reset code.
4. Authentication -> URL Configuration: set the Site URL to the company
   website (it is only used by links, which these templates no longer
   have).

The local stack (`supabase start`) already uses these templates
(`supabase/config.toml`).

### Forgot PIN code email (Magic Link template)

The app's Forgot PIN ("Email me a code") sends a sign-in code with
`signInWithOtp` (no new accounts) and checks it as an `email` OTP, so
Supabase sends its **Magic Link** email, not the password reset one. No
other flow in the app or website sends that email. Nothing in the repo
in `supabase-deploy` pushes email templates (it only runs `supabase db
push`). Until the template is set, the hosted project sends Supabase's
default Magic Link email, a link with no code, and Forgot PIN by email
cannot work.

Easiest: run the **supabase-email-templates** workflow from the Actions
tab. It sets the subject and body below through the Management API and
fails if the saved template doesn't show the code. Or by hand, in the
dashboard:

1. Authentication -> Email Templates -> **Magic Link**.
2. Subject: `FieldOS verification code`.
3. Body: the whole of `supabase/templates/magic_link.html` (it shows
   `{{ .Token }}` as the sign-in code; keep that line).
4. Save. Then Authentication -> Providers -> Email: leave the Email
   provider on (the code needs it; "Confirm email" can stay off).
5. Check: on a test phone with the app locked, Forgot PIN -> "Email me a
   code". The email's subject is "FieldOS verification code" and the
   6-digit code in it unlocks the PIN reset.

The email can only reach people once SMTP is set up (step 3 above).

The owner taps "Put company on the cloud", which calls the
`ensure_company` RPC: it creates the company row, makes the caller its
owner, and returns a join code. Everyone else taps "Join with a code",
which calls `join_company` and adds them as a site engineer. The owner can
change roles and reset the code from the same screen
(`set_member_role`, `regenerate_join_code`). All of these are
security-definer functions granted to `authenticated` only
(`supabase/migrations/20261105000000_team_onboarding.sql`).

## 4. Point the app at it

The release build reads the project from compile-time defines; nothing is
hard-coded and no key is ever typed into the app:

```
flutter build appbundle --release \
  --dart-define=SUPABASE_URL=https://YOUR-REF.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR-ANON-KEY
```

In CI, add repo secrets `SUPABASE_URL` and `SUPABASE_ANON_KEY`;
`.github/workflows/release.yml` passes them through. Only the **anon** key
goes in the app; never the `service_role` key. A release build without
them runs offline-only and hides Team & sync.

## 5. Ship the release build

`flutter build apk --release` now signs with the real upload key
(`android/app/key.properties`, gitignored). **Back up both the keystore and
the passwords** — losing them after first Play upload means a new app
identity. For Play Store distribution you'll also want an AAB:
`flutter build appbundle --release`.

Play Console itself is your account/action (see AGENT_HANDOFF gaps #7).

## 6. First real-device smoke test

Follow the two-phone smoke test in `docs/PLAY_STORE_LAUNCH.md` section 6:
each phone signs in with its own email, B joins A's company by code.

## Backups and restore

Two layers, because a plan's backups alone are not enough:

1. **Supabase's own daily backups** (Pro plan; point-in-time recovery is an
   add-on). The Free plan has none: `supabase backups list --remote=<ref>`
   returning `backups: []` means you are on it.
2. **`db-backup` workflow** (`.github/workflows/db-backup.yml`, `tools/db_backup.py`):
   every day at 03:00 India time it dumps the database, encrypts it
   (AES-256) with the `BACKUP_PASSPHRASE` secret and stores it 35 days in the
   private `db-backups` bucket. Needs the secret `BACKUP_PASSPHRASE`
   (32+ random characters; keep a copy in the password manager, because
   without it nothing can be opened). It refuses to store an empty or
   cut-short dump, and fails the run, so a broken backup shows as a red run.

What they do **not** cover: Storage files (photos, bills, selfies, documents)
are in neither, and losing the whole Supabase project loses the
`db-backups` bucket with it. Download a backup by hand to the owner's own
storage now and then.

### Restoring a backup

Restore into a **new** project (or a local stack to look at the data). Never
restore over a live production project.

1. Get the file: Dashboard > Storage > `db-backups` > `YYYY/MM/DD/`, download it.
2. Open it. Check the hashes against `manifest.json` (a wrong passphrase
   produces garbage, and `tar` fails):
   ```bash
   export BACKUP_PASSPHRASE='...'
   openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -pass env:BACKUP_PASSPHRASE \
     -in fieldos-YYYYMMDDTHHMMSSZ.tar.gz.enc | tar xz
   shasum -a 256 schema.sql data.sql roles.sql   # compare with manifest.json
   ```
3. Make a fresh project and apply the migrations to it: `supabase link
   --project-ref <new-ref> && supabase db push --remote --yes` (locally:
   `supabase db reset --no-seed`). Do not load `schema.sql`; the migrations
   already built the schema, and `schema.sql` is there as a reference.
4. Empty what the migrations seeded (otherwise `app_config` collides), then
   load the data, stopping at the first error:
   ```bash
   psql "$DB_URL" -v ON_ERROR_STOP=1 -q -f tools/db_restore_clear.sql
   (echo "SET session_replication_role = replica;"; cat data.sql) | psql "$DB_URL" -v ON_ERROR_STOP=1 -q
   ```
5. Check: row counts of `companies`, `projects`, `tasks`, `site_expenses`,
   `auth.users` match the source; run the **isolation-check** workflow
   against the new project; sign in on a test phone.
6. Point the app at the new project only if the old one is truly gone
   (new `SUPABASE_URL` / `SUPABASE_ANON_KEY` build, then raise the minimum
   build). Photos and other Storage files have to come from elsewhere.

Tested on 26 Nov 2026 against a local stack: backup, decrypt, wipe, migrate,
clear, load; company, project, task, expense and user counts matched the
source exactly. Repeat this drill once on a scratch project after the first
real backup, and after any change to `tools/db_backup.py`.

## Known limits to carry forward

- Pull never overwrites a record with an unsynced local edit; otherwise the
  last edit to reach the server wins.
- Voice-to-DPR needs internet (Sarvam) independent of sync.
- `grns`/MaterialReceipts and LabourAttendance remain deliberately unsynced
  (shape mismatches documented in `lib/sync/sync_mappers.dart`).
