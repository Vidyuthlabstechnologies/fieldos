/// Push/pull sync engine: local Drift outbox -> Supabase, and Supabase
/// Realtime -> local Drift. See docs/SUPABASE_SYNC_RESEARCH.md for why this
/// is a hand-rolled outbox rather than PowerSync (free-tier deactivation
/// risk) or Brick.
///
/// Uses the plain `supabase` package (SupabaseClient), not `supabase_flutter`
/// -- no Flutter/platform binding dependency, so this is testable with real
/// network calls against the local dev instance in `flutter test`'s Dart VM
/// runner. `supabase_flutter`'s extra pieces (session persistence across
/// app restarts, the `Supabase.instance` singleton) are a UI-layer concern
/// for whoever wires the Auth screens to this -- not needed here.
///
/// Only Project/Task are wired end to end so far (see
/// lib/sync/sync_mappers.dart's docstring) -- this proves the mechanism
/// correctly before mechanically extending it to the rest of the schema.
library;

import 'dart:convert';

import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'sync_mappers.dart';

class SyncPushResult {
  const SyncPushResult({required this.succeeded, required this.failed});
  final int succeeded;
  final int failed;
}

class SyncEngine {
  SyncEngine({required this.db, required this.client});

  final AppDatabase db;
  final SupabaseClient client;
  RealtimeChannel? _tasksChannel;
  RealtimeChannel? _projectsChannel;

  /// Drains the outbox in order. Stops (does not skip past) on the first
  /// failure within a run, to preserve per-record write ordering -- a
  /// later run will retry it. Each entry gets its own failure handling so
  /// one bad row doesn't lose track of how many others succeeded first.
  Future<SyncPushResult> pushPending() async {
    final entries = await db.syncOutboxDao.pending();
    var succeeded = 0;
    for (final entry in entries) {
      try {
        final data = jsonDecode(entry.payload) as Map<String, dynamic>;
        final table = client.from(entry.targetTable);
        switch (entry.operation) {
          case 'insert':
            await table.insert(data);
          case 'update':
            await table.update(data).eq('id', entry.recordId);
          case 'delete':
            await table.delete().eq('id', entry.recordId);
          default:
            throw StateError('Unknown outbox operation: ${entry.operation}');
        }
        await db.syncOutboxDao.markSynced(entry.id);
        succeeded++;
      } catch (e) {
        await db.syncOutboxDao.recordFailure(entry.id, e.toString());
        return SyncPushResult(succeeded: succeeded, failed: entries.length - succeeded);
      }
    }
    return SyncPushResult(succeeded: succeeded, failed: 0);
  }

  /// One-shot pull: fetches every project/task the current session's RLS
  /// allows and merges into local Drift. Useful for an initial sync or a
  /// manual "refresh" -- the Realtime subscriptions below are for ongoing
  /// live updates after that.
  Future<void> pullAll() async {
    final projectRows = await client.from('projects').select();
    for (final row in projectRows) {
      await db.projectDao.upsertFromRemote(projectFromSupabaseJson(row));
    }
    final taskRows = await client.from('tasks').select();
    for (final row in taskRows) {
      await db.taskDao.upsertFromRemote(taskFromSupabaseJson(row));
    }
  }

  /// Live updates for one project's tasks -- INSERT/UPDATE/DELETE on the
  /// `tasks` row for this project merge into Drift as they happen.
  Future<void> subscribeToProjectTasks(String projectId) async {
    await _tasksChannel?.unsubscribe();
    _tasksChannel = client
        .channel('tasks-$projectId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tasks',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'project_id', value: projectId),
          callback: (payload) async {
            if (payload.eventType == PostgresChangeEvent.delete) {
              return; // tasks have no local hard-delete path today; nothing to reconcile yet.
            }
            await db.taskDao.upsertFromRemote(taskFromSupabaseJson(payload.newRecord));
          },
        )
        .subscribe();
  }

  /// Live updates for the projects a user's company creates.
  Future<void> subscribeToCompanyProjects(String companyId) async {
    await _projectsChannel?.unsubscribe();
    _projectsChannel = client
        .channel('projects-$companyId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'projects',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'company_id', value: companyId),
          callback: (payload) async {
            if (payload.eventType == PostgresChangeEvent.delete) return;
            await db.projectDao.upsertFromRemote(projectFromSupabaseJson(payload.newRecord));
          },
        )
        .subscribe();
  }

  Future<void> dispose() async {
    if (_tasksChannel != null) await _tasksChannel!.unsubscribe();
    if (_projectsChannel != null) await _projectsChannel!.unsubscribe();
  }
}
