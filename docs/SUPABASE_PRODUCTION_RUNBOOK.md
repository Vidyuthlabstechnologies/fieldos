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

- **CLI (preferred, keeps migrations canonical):**
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

## 3. Create the shared account

The app signs every device into ONE shared company account (see
`lib/sync/cloud_sync_service.dart` — sign-in-first with sign-up fallback).
Create it once: Authentication → Users → Add user (email + password,
auto-confirm). Share those credentials with devices that should join the
company's synced data — same model as the local stack today.

## 4. Point the app at it

`lib/sync/sync_config.dart`'s `SyncConfig.production` currently has empty
URL/keys. Fill `url` + `anonKey` from Project Settings → API. **Never commit
a service_role key anywhere** — only the anon key belongs in the client;
RLS does the rest.

## 5. Ship the release build

`flutter build apk --release` now signs with the real upload key
(`android/app/key.properties`, gitignored). **Back up both the keystore and
the passwords** — losing them after first Play upload means a new app
identity. For Play Store distribution you'll also want an AAB:
`flutter build appbundle --release`.

Play Console itself is your account/action (see AGENT_HANDOFF gaps #7).

## 6. First real-device smoke test

Two devices (or one device + one browser via the dashboard): enable cloud
sync on both with the shared account, create a DPR on device A, watch it
appear on device B without manual refresh (Realtime tasks/vendors) or after
"Sync now" (everything else).

## Known limits to carry forward

- Pull is server-wins; two offline edits of the SAME record still need real
  conflict design before two people routinely edit concurrently.
- Voice-to-DPR needs internet (Sarvam) independent of sync.
- `grns`/MaterialReceipts and LabourAttendance remain deliberately unsynced
  (shape mismatches documented in `lib/sync/sync_mappers.dart`).
