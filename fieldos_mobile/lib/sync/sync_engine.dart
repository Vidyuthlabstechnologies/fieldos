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
/// See lib/sync/sync_mappers.dart's docstring for which tables are wired
/// end to end so far, and which are deliberately not (yet).
library;

import 'dart:async';
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

  /// Fired after a Realtime event has been upserted into Drift. SyncEngine
  /// stays plain Dart with no Flutter/Riverpod dependency (see this file's
  /// docstring -- that's what keeps it testable with real network calls in
  /// a Dart VM test), so it can't invalidate a Riverpod provider itself --
  /// this is the hook a UI layer uses to know local data just changed and
  /// react (e.g. `ref.invalidate(tasksProvider(projectId))`), without this
  /// class knowing Riverpod exists.
  void Function()? onTasksChanged;
  void Function()? onProjectsChanged;

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
    final dprRows = await client.from('dpr_entries').select();
    for (final row in dprRows) {
      await db.dprDao.upsertFromRemote(dprEntryFromSupabaseJson(row));
    }
    final issueRows = await client.from('issues').select();
    for (final row in issueRows) {
      await db.issueDao.upsertFromRemote(issueFromSupabaseJson(row));
    }
    final workerRows = await client.from('workers').select();
    for (final row in workerRows) {
      await db.workerDao.upsertFromRemote(workerFromSupabaseJson(row));
    }
    final equipmentRows = await client.from('equipment').select();
    for (final row in equipmentRows) {
      await db.equipmentDao.upsertFromRemote(equipmentFromSupabaseJson(row));
    }
    final inspectionRows = await client.from('inspections').select();
    for (final row in inspectionRows) {
      await db.inspectionDao.upsertFromRemote(inspectionFromSupabaseJson(row));
    }
    final subcontractorRows = await client.from('subcontractors').select();
    for (final row in subcontractorRows) {
      await db.subcontractorDao.upsertFromRemote(subcontractorFromSupabaseJson(row));
    }
    final workOrderRows = await client.from('work_orders').select();
    for (final row in workOrderRows) {
      await db.workOrderDao.upsertFromRemoteWorkOrder(workOrderFromSupabaseJson(row));
    }
    final approvalRows = await client.from('approvals').select();
    for (final row in approvalRows) {
      await db.approvalDao.upsertFromRemote(approvalFromSupabaseJson(row));
    }
  }

  /// Live updates for one project's tasks -- INSERT/UPDATE/DELETE on the
  /// `tasks` row for this project merge into Drift as they happen.
  ///
  /// Waits for the server to actually confirm the channel join before
  /// returning. `.subscribe()` itself fires the join off in the background
  /// and returns immediately -- a caller that (like a test creating data
  /// right after subscribing, or a screen navigating fast) acts before that
  /// join round-trip completes could otherwise miss the very first events
  /// with no error at all. A failed join is surfaced as a real exception,
  /// not silently ignored.
  Future<void> subscribeToProjectTasks(String projectId) async {
    await _tasksChannel?.unsubscribe();
    final channel = client.channel('tasks-$projectId').onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tasks',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'project_id', value: projectId),
          callback: (payload) async {
            if (payload.eventType == PostgresChangeEvent.delete) {
              return; // tasks have no local hard-delete path today; nothing to reconcile yet.
            }
            await db.taskDao.upsertFromRemote(taskFromSupabaseJson(payload.newRecord));
            onTasksChanged?.call();
          },
        );
    _tasksChannel = channel;
    await _awaitJoin(channel, label: 'tasks-$projectId');
  }

  /// Live updates for the projects a user's company creates. See
  /// subscribeToProjectTasks's docstring for why this awaits the join.
  Future<void> subscribeToCompanyProjects(String companyId) async {
    await _projectsChannel?.unsubscribe();
    final channel = client.channel('projects-$companyId').onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'projects',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'company_id', value: companyId),
          callback: (payload) async {
            if (payload.eventType == PostgresChangeEvent.delete) return;
            await db.projectDao.upsertFromRemote(projectFromSupabaseJson(payload.newRecord));
            onProjectsChanged?.call();
          },
        );
    _projectsChannel = channel;
    await _awaitJoin(channel, label: 'projects-$companyId');
  }

  Future<void> _awaitJoin(RealtimeChannel channel, {required String label}) {
    final completer = Completer<void>();
    channel.subscribe((status, error) {
      if (completer.isCompleted) return;
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          completer.complete();
        case RealtimeSubscribeStatus.channelError:
        case RealtimeSubscribeStatus.timedOut:
        case RealtimeSubscribeStatus.closed:
          completer.completeError(StateError('Realtime channel "$label" failed to join: $status ($error)'));
      }
    });
    return completer.future;
  }

  Future<void> dispose() async {
    if (_tasksChannel != null) await _tasksChannel!.unsubscribe();
    if (_projectsChannel != null) await _projectsChannel!.unsubscribe();
  }
}
