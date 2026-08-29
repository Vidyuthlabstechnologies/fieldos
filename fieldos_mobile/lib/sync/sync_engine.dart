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
import 'dart:io';

import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'sync_mappers.dart';

class SyncPushResult {
  const SyncPushResult({required this.succeeded, required this.failed});
  final int succeeded;
  final int failed;
}

class SyncEngine {
  /// Where downloaded document files are written. Injectable so Dart-VM
  /// tests can point at a temp dir -- [localDocumentsDirectory] needs
  /// path_provider's platform channels, which don't exist under
  /// TestWidgetsFlutterBinding.
  SyncEngine({required this.db, required this.client, Future<Directory> Function()? resolveDocumentsDirectory})
      : _resolveDocumentsDirectory = resolveDocumentsDirectory ?? localDocumentsDirectory;

  final AppDatabase db;
  final SupabaseClient client;
  final Future<Directory> Function() _resolveDocumentsDirectory;

  RealtimeChannel? _tasksChannel;
  RealtimeChannel? _projectsChannel;
  RealtimeChannel? _vendorsChannel;
  RealtimeChannel? _dprEntriesChannel;
  RealtimeChannel? _issuesChannel;

  /// Serializes push/pull so overlapping sync paths (periodic tick vs
  /// manual "Sync now" vs post-write flush) can't drain the same outbox
  /// entries twice -- the loser used to hit duplicate-id violations and
  /// mark already-succeeded entries as failed, leaving them to retry
  /// forever. A simple chained-Future mutex: each call awaits the previous
  /// one; Dart's single-threaded event loop makes that race-free.
  Future<void> _syncLock = Future.value();

  Future<T> _synchronized<T>(Future<T> Function() body) {
    final prev = _syncLock;
    final completer = Completer<void>();
    _syncLock = completer.future;
    return () async {
      try {
        await prev;
        return await body();
      } finally {
        completer.complete();
      }
    }();
  }

  /// Fired after a Realtime event has been upserted into Drift. SyncEngine
  /// stays plain Dart with no Flutter/Riverpod dependency (see this file's
  /// docstring -- that's what keeps it testable with real network calls in
  /// a Dart VM test), so it can't invalidate a Riverpod provider itself --
  /// this is the hook a UI layer uses to know local data just changed and
  /// react (e.g. `ref.invalidate(tasksProvider(projectId))`), without this
  /// class knowing Riverpod exists.
  void Function()? onTasksChanged;
  void Function()? onProjectsChanged;
  void Function()? onVendorsChanged;
  void Function()? onDprEntriesChanged;
  void Function()? onIssuesChanged;

  /// Drains the outbox in order. Stops (does not skip past) on the first
  /// failure within a run, to preserve per-record write ordering -- a
  /// later run will retry it. Each entry gets its own failure handling so
  /// one bad row doesn't lose track of how many others succeeded first.
  Future<SyncPushResult> pushPending() => _synchronized(() async {
        final entries = await db.syncOutboxDao.pending();
        var succeeded = 0;
        for (final entry in entries) {
          try {
            final data = jsonDecode(entry.payload) as Map<String, dynamic>;
            final table = client.from(entry.targetTable);
        if (entry.targetTable == 'documents' && entry.operation == 'insert') {
          // The file itself goes to Storage first; only after that upload
          // succeeds does the metadata row land in Postgres, so a visible
          // row always has a downloadable object behind it.
          final localPath = data.remove('_local_file_path') as String?;
          if (localPath == null) {
            throw StateError('documents outbox payload missing _local_file_path');
          }
          await client.storage
              .from('documents')
              .uploadBinary(data['file_path'] as String, File(localPath).readAsBytesSync(),
                  fileOptions: const FileOptions(upsert: true));
          await table.insert(data);
        } else {
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
        }
        await db.syncOutboxDao.markSynced(entry.id);
        succeeded++;
      } catch (e) {
        await db.syncOutboxDao.recordFailure(entry.id, e.toString());
        return SyncPushResult(succeeded: succeeded, failed: entries.length - succeeded);
      }
    }
    return SyncPushResult(succeeded: succeeded, failed: 0);
  });

  /// One-shot pull: fetches every project/task the current session's RLS
  /// allows and merges into local Drift. Useful for an initial sync or a
  /// manual "refresh" -- the Realtime subscriptions below are for ongoing
  /// live updates after that. Serialized with pushPending (see _synchronized).
  Future<void> pullAll() => _synchronized(() async {
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
    final vendorRows = await client.from('vendors').select();
    for (final row in vendorRows) {
      await db.supplierDao.upsertFromRemote(supplierFromSupabaseJson(row));
    }
    final estimationRows = await client.from('estimations').select();
    for (final row in estimationRows) {
      await db.estimationDao.upsertFromRemote(estimationFromSupabaseJson(row));
    }
    final costHeadRows = await client.from('cost_heads').select();
    for (final row in costHeadRows) {
      await db.estimationDao.upsertFromRemoteCostHead(costHeadFromSupabaseJson(row));
    }
    final measurementRows = await client.from('measurement_entries').select();
    for (final row in measurementRows) {
      await db.estimationDao.upsertFromRemoteMeasurement(measurementEntryFromSupabaseJson(row));
    }
    final steelRows = await client.from('steel_entries').select();
    for (final row in steelRows) {
      await db.estimationDao.upsertFromRemoteSteel(steelEntryFromSupabaseJson(row));
    }
    final requisitionRows = await client.from('purchase_requisitions').select();
    for (final row in requisitionRows) {
      await db.purchaseDao.upsertFromRemoteRequest(purchaseRequestFromSupabaseJson(row));
    }
    final purchaseOrderRows = await client.from('purchase_orders').select();
    for (final row in purchaseOrderRows) {
      await db.purchaseDao.upsertFromRemoteOrder(purchaseOrderFromSupabaseJson(row));
    }
    final documentRows = await client.from('documents').select();
    for (final row in documentRows) {
      final storagePath = row['file_path'] as String;
      // A visible row must have a downloadable object (push uploads the file
      // before inserting). A failure here is a real anomaly -- surfacing it
      // beats silently shipping a metadata row pointing at nothing.
      final bytes = await client.storage.from('documents').download(storagePath);
      final docsDir = await _resolveDocumentsDirectory();
      final safeName = (row['name'] as String).replaceAll(RegExp(r'[^\w.\-]'), '_');
      final localFile = File('${docsDir.path}/${row['id']}_$safeName');
      await localFile.writeAsBytes(bytes);
      await db.documentDao.upsertFromRemote(documentFromSupabaseJson(row, localPath: localFile.path));
    }
  });

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

  /// Live updates for a company's vendor directory (the Suppliers tab is
  /// company-scoped, like projects). See subscribeToProjectTasks's docstring
  /// for why this awaits the join.
  Future<void> subscribeToCompanyVendors(String companyId) async {
    await _vendorsChannel?.unsubscribe();
    final channel = client.channel('vendors-$companyId').onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'vendors',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'company_id', value: companyId),
          callback: (payload) async {
            if (payload.eventType == PostgresChangeEvent.delete) return;
            await db.supplierDao.upsertFromRemote(supplierFromSupabaseJson(payload.newRecord));
            onVendorsChanged?.call();
          },
        );
    _vendorsChannel = channel;
    await _awaitJoin(channel, label: 'vendors-$companyId');
  }

  /// Live updates for DPR entries in a project. See subscribeToProjectTasks's
  /// docstring for why this awaits the join.
  Future<void> subscribeToProjectDprEntries(String projectId) async {
    await _dprEntriesChannel?.unsubscribe();
    final channel = client.channel('dpr-entries-$projectId').onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'dpr_entries',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'project_id', value: projectId),
          callback: (payload) async {
            if (payload.eventType == PostgresChangeEvent.delete) return;
            await db.dprDao.upsertFromRemote(dprEntryFromSupabaseJson(payload.newRecord));
            onDprEntriesChanged?.call();
          },
        );
    _dprEntriesChannel = channel;
    await _awaitJoin(channel, label: 'dpr-entries-$projectId');
  }

  /// Live updates for issues in a project. See subscribeToProjectTasks's
  /// docstring for why this awaits the join.
  Future<void> subscribeToProjectIssues(String projectId) async {
    await _issuesChannel?.unsubscribe();
    final channel = client.channel('issues-$projectId').onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'issues',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'project_id', value: projectId),
          callback: (payload) async {
            if (payload.eventType == PostgresChangeEvent.delete) return;
            await db.issueDao.upsertFromRemote(issueFromSupabaseJson(payload.newRecord));
            onIssuesChanged?.call();
          },
        );
    _issuesChannel = channel;
    await _awaitJoin(channel, label: 'issues-$projectId');
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
    if (_vendorsChannel != null) await _vendorsChannel!.unsubscribe();
    if (_dprEntriesChannel != null) await _dprEntriesChannel!.unsubscribe();
    if (_issuesChannel != null) await _issuesChannel!.unsubscribe();
  }
}
