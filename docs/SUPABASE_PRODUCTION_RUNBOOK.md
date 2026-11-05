# Supabase production runbook — the 15-minute cutover

Everything below is a **user action** (account ownership rule); this doc
exists so that when you do it, nothing else needs inventing. The sync layer,
schema, RLS, and Storage bucket are all tested against an identical local
stack — production is configuration, not new engineering.

## 1. Create the project (your account)

1. Sign up at https://supabase.com (free tier is sufficient to start; the
   hand-rolled outbox was chosen partly so we never depend on paid tiers).
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
code. Turn it back on once custom SMTP is configured; the app then tells
the person to confirm and sign in.

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

## Known limits to carry forward

- Pull never overwrites a record with an unsynced local edit; otherwise the
  last edit to reach the server wins.
- Voice-to-DPR needs internet (Sarvam) independent of sync.
- `grns`/MaterialReceipts and LabourAttendance remain deliberately unsynced
  (shape mismatches documented in `lib/sync/sync_mappers.dart`).
