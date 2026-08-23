# Offline-First Flutter + Supabase Sync — Architecture Research

## Status (2026-08-23): schema + RLS built and verified, sync layer not started

`supabase/migrations/20260823000000_initial_schema.sql` implements the full schema below (30
tables mirroring `fieldos/models.py` + the mobile-only entities from
`fieldos_mobile/lib/data/tables.dart`) with RLS enabled and policies on every table. This has
been applied to a real local Supabase instance (`supabase start`, Docker-based) via `supabase db
reset` and verified with `supabase/rls_verification_test.sql` — a from-scratch test that seeds
two isolated fake companies and proves, with actual query output (not an assumption):

- A company's owner sees only their own company/project/task rows; an explicit cross-tenant
  probe (`select ... where id = '<other company's id>'`) returns 0 rows, not just "didn't
  appear in a list."
- Anonymous (`anon` role, no session at all) access is fully denied.
- A plain project member (`site_engineer`, not owner/PM) attempting to create a purchase order
  is **rejected** by RLS — and a control test on the same user immediately after, reading data
  they're genuinely entitled to, confirms the rejection was the role-gate working correctly,
  not a broken connection.

**A real bug this verification caught before it could ship**: the first version of the
migration enabled RLS on every table but never `GRANT`ed table-level access to the
`authenticated`/`anon` roles — Postgres checks table grants before RLS policies run at all, so
nobody, including legitimate members, could have accessed anything. Fixed in the migration
(a `do $$ ... $$` block granting `select, insert, update, delete` to `authenticated` per table,
after `revoke all` from both roles first).

**Not yet done**: no Supabase Auth wiring in the Flutter app (still the local pbkdf2 auth), no
sync protocol (the hand-rolled Drift outbox recommended above isn't implemented), no Realtime
subscriptions wired up, and nothing deployed to the actual Supabase cloud (still local-only —
deploying needs the user's own Supabase account, which isn't something this assistant creates
on someone's behalf). A handful of RLS mutation policies (quotes, work_orders, approvals) used
the safe default (plain project membership) rather than a confirmed exact role requirement from
`fieldos/routers/*.py` — flagged in the migration's own comments for follow-up, not silently
guessed.

**Provenance:** researched by the `hermes` agent CLI (nemotron-3-ultra-free via OpenCode Zen,
web tools) on 2026-08-23. Not yet independently re-verified beyond the source citations inline.

## Decision: hand-rolled Drift outbox + Supabase Realtime, not PowerSync

`supabase_flutter` itself has **no built-in offline cache or sync queue** — it's a thin
PostgREST/Auth/Realtime/Storage client. Three real options exist for the offline-first layer:
Brick (a Flutter package bundling local cache + queue), PowerSync (a managed Postgres↔Drift
sync service), or a hand-rolled outbox table.

**PowerSync was the most tempting option but has a real free-tier risk for this project**: its
free tier deactivates a project after 7 days of inactivity — a real risk for construction sites
with seasonal gaps in use, and $49/mo to avoid. **Recommendation: hand-rolled outbox.** Drift
stays the single source of truth and write path; a local `outbox` table queues local
inserts/updates/deletes; a background sync pushes queued changes to Supabase REST and pulls
remote changes via `postgres_changes` Realtime subscriptions, merging into Drift. Conflict
strategy: server-wins for reference data (BOQ, worker directory), client-wins for
user-generated data (DPR, attendance) — simpler than CRDTs, adequate here.

## RLS pattern: security-definer helper functions, not inline joins

The documented, performant pattern for "user can see rows for companies/projects they're a
member of" is a `security definer` Postgres function (e.g. `is_project_member(project_id)`)
wrapped as `(select public.is_project_member(project_id))` in each policy — the `security
definer` avoids RLS-recursion on the membership table itself, and the `select` wrapper caches
`auth.uid()` once per query instead of once per row (a real, documented performance
consideration, not just style).

## Auth: pbkdf2 → Supabase Auth is a clean cutover, not a migration

Supabase Auth (GoTrue) only supports migrating **bcrypt** password hashes, and only
Supabase-project-to-Supabase-project. There is no documented path to import this app's existing
pbkdf2 hashes. **Plan for a clean cutover**: existing local accounts set a new password once
(via a Supabase magic-link/reset flow on first sync), local `users`/`sessions` tables become
read-only history, and a `supabase_user_id` mapping column links old local records to the new
Supabase identity.

## Realtime capacity check for ~20 employees

Free tier: 200 concurrent Realtime connections, 2M messages/month. At ~20 users each active on
1-2 projects at a time (not all 10 simultaneously), real concurrent connection count lands
around 40 — comfortable headroom, not near the limit. Multiplexing one channel per user with an
`in.(...)` project-id filter, rather than one channel per project per user, keeps this safely
low regardless.

## Local development

`supabase init` / `supabase start` (Docker-based Postgres + Auth + Realtime + Storage +
Studio) is the current, actively-maintained way to develop and test schema/RLS changes without
a live cloud project — confirmed as the workflow this session is actually using.
