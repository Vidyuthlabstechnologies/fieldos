## What this does

<!-- One or two sentences. -->

## Verified

- [ ] `flutter analyze` clean (mobile changes) — or `npx tsc --noEmit` (frontend) — or nothing extra needed (backend runs in CI)
- [ ] Ran the relevant test suite locally and it's green — **mobile sync-layer tests need `supabase start` running first; a green run with the stack down just means every test self-skipped, not that anything passed.** See `docs/AGENT_HANDOFF.md` → "How to verify anything."
- [ ] No file under `resources/` referenced, quoted, or committed
- [ ] No `.env`, API key, or secret committed
- [ ] If this touches `lib/data/tables.dart`: `schemaVersion` bumped and a migration step added (see `docs/AGENT_HANDOFF.md`'s gotchas — the default migrator only creates missing tables, it never alters existing ones)
- [ ] If this adds a Realtime subscription: the table is added to the `supabase_realtime` publication in a migration (a channel joins fine even when the table isn't published — events then just silently never arrive)

## Notes for the reviewer

<!-- Anything non-obvious, a deliberate shortcut taken and why, or a known
follow-up this doesn't attempt to close. -->

---
CI on this repo checks out the code but **branch protection isn't
available on the current plan** (private repo, free tier) — nothing
blocks a merge automatically, so the checklist above is the actual gate
until that changes. Check the Actions tab for this PR before merging, not
just after.
