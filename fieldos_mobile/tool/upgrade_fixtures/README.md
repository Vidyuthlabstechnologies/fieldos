# Upgrade fixtures (issue #145)

`test/shipped_schema_upgrade_test.dart` opens the database each shipped
build created and upgrades it to today's schema. Every row must survive, and
the result must match a fresh install's schema exactly.

To add a fixture after a release that changes `schemaVersion`:

1. Check out the release commit in a worktree:
   `git worktree add /tmp/old <commit>`.
2. Copy `make_db_test.dart.template` to `/tmp/old/fieldos_mobile/test/zz_make_db_test.dart`.
3. Run `OUT_DB=/tmp/raw.sqlite flutter test test/zz_make_db_test.dart` there.
   The shipped code creates its own empty schema.
4. Run `python3 tool/upgrade_fixtures/seed.py /tmp/raw.sqlite /tmp/fieldos_vN.sqlite`.
   It puts one row in every table, with foreign keys pointing at real rows.
5. Run `gzip -9c /tmp/fieldos_vN.sqlite > test/fixtures/upgrade/fieldos_vN.sqlite.gz`,
   then add `N` to the list in the test.
