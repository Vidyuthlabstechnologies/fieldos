-- fieldos_mobile's SyncEngine.subscribeToProjectDprEntries/subscribeToProjectIssues
-- (added alongside the ProjectDetailScreen realtime hookups) join their
-- channels successfully whether or not a table is in the publication --
-- the join itself doesn't fail. Without this, postgres_changes events for
-- dpr_entries/issues would simply never arrive, silently, exactly the
-- failure mode already documented in docs/AGENT_HANDOFF.md's gotchas for
-- tasks/projects. Add the table before shipping the subscription, not after.
alter publication supabase_realtime add table dpr_entries, issues;
