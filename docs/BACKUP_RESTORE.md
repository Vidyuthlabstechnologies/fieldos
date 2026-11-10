# Backup and restore

This is part of item 5 of the weekly-close plan. Settings > Your data has two entries:

- **Back up this phone** makes one zip and opens the share sheet, so the
  file can go to Drive, a computer or a chat with yourself.
- **Restore a backup** picks such a zip, checks it, and replaces this
  phone's data the next time FieldOS opens.

Code: `fieldos_mobile/lib/data/backup.dart`. Screen actions:
`lib/features/settings/backup_actions.dart`.

## What is in a backup

- `fieldos.sqlite`: a consistent copy of the database. It is made with
  `VACUUM INTO`, so the app keeps running.
- `manifest.json`: the backup format, the schema version, when the backup
  was made, the row count of each main table, and the files.
- `files/`: every DPR photo, expense bill, delivery slip and document the
  records point to.

## How a restore is checked

Nothing live changes until every check passes. A restore is refused when:

- the file is not a zip, or has no manifest or database;
- the backup comes from a newer schema or format than the app;
- SQLite's `integrity_check` fails, or the database's `user_version`
  differs from the manifest;
- any table's row count differs from the manifest.

If a check fails, nothing is left behind.

Once the checks pass:

1. The files are written to a new folder of their own under the app's
   media folder.
2. The restored records are pointed at those files.
3. The database is staged as `fieldos.sqlite.restore`.

The staged database is swapped in before the database next opens (see
`appDatabasePath` and `applyStagedRestore`). The replaced database is
kept as `fieldos.sqlite.before-restore`.

## Notes

- A restore brings back the sign-in and sync state of the phone that made
  the backup. Its unsent changes are sent again, and the server takes them
  as upserts. Restore onto the same account.
- There is no server change.

## Tests

`test/backup_test.dart` checks two things:
- a backup made on one phone restores the same records and files on
  another;
- a damaged, incomplete or newer backup is refused and leaves nothing
  behind.
