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

import 'package:drift/drift.dart' show Variable;
import 'package:http/http.dart' show ClientException;
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'sync_mappers.dart';

class SyncPushResult {
  const SyncPushResult({required this.succeeded, required this.failed});
  final int succeeded;
  final int failed;
}

/// The server answered, but the write changed nothing: an update or delete
/// that matched zero rows. Kept in the outbox (and shown in Team & sync once
/// parked) instead of being marked sent.
class SyncNotAppliedException implements Exception {
  SyncNotAppliedException(this.table, this.recordId, this.reason);
  final String table;
  final String recordId;
  final String reason;
  @override
  String toString() => 'Not applied on the server ($table $recordId): $reason';
}

/// No answer from the server at all (offline, timeout, TLS cut). Such a
/// failure says nothing about the write, so it never counts toward parking.
bool isTransientSyncError(Object e) =>
    e is SocketException ||
    e is TimeoutException ||
    e is HandshakeException ||
    e is HttpException ||
    e is ClientException ||
    (e is StorageException && (e.statusCode == null || (int.tryParse(e.statusCode!) ?? 0) >= 500)) ||
    (e is PostgrestException && e.code != null && RegExp(r'^5\d\d$').hasMatch(e.code!));

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
  RealtimeChannel? _messagesChannel;

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
  void Function()? onMessagesChanged;

  /// Fired (before the local upsert) for a row in [notifiableTables] that
  /// this device had never seen -- a colleague's new issue, approval
  /// request or chat message. The app layer decides whether it deserves an
  /// on-device notification (e.g. not on the very first full pull).
  void Function(String table, Map<String, dynamic> row)? onRemoteRowCreated;

  /// The local (pbkdf2) account id this device's rows were written with.
  ///
  /// Every `*_by` / `*_id` user column in Postgres references
  /// `auth.users(id)`, but locally those columns hold the local account's
  /// own id -- a different UUID. Pushing them unchanged violated the
  /// foreign key on the very first DPR/issue/approval a real user synced.
  /// Push rewrites local -> Supabase user id; pull rewrites it back, so the
  /// device's "my DPRs" filters keep matching its own rows. Colleagues'
  /// ids pass through untouched (they have no local account to map to).
  String? localUserId;

  static const userIdColumns = {
    'created_by', 'requested_by', 'approved_by', 'uploaded_by', 'received_by',
    'inspector_id', 'approver_id', 'assignee_id', 'sender_id', 'user_id', 'recorded_by', 'edited_by',
  };

  Map<String, dynamic> _toRemoteIds(Map<String, dynamic> data) =>
      _swapUserIds(data, from: localUserId, to: client.auth.currentUser?.id);

  Map<String, dynamic> _toLocalIds(Map<String, dynamic> row) =>
      _swapUserIds(row, from: client.auth.currentUser?.id, to: localUserId);

  static Map<String, dynamic> _swapUserIds(Map<String, dynamic> row, {String? from, String? to}) {
    if (from == null || to == null || from == to) return row;
    final out = Map<String, dynamic>.of(row);
    for (final column in userIdColumns) {
      if (out[column] == from) out[column] = to;
    }
    return out;
  }

  /// Drains the outbox, oldest first.
  ///
  /// Every write is safe to replay. A response lost after the server
  /// committed used to leave the entry queued; the replayed insert then hit
  /// a duplicate id and failed forever, so a write the server had accepted
  /// looked unsent. Now:
  ///  - insert: a duplicate-id answer is checked against the server; if the
  ///    row with this id is there, the write had already landed and the
  ///    entry is done. Any other unique clash is a real rejection.
  ///  - update/delete: the server says which rows it touched. Zero rows is
  ///    NOT success (row-level security hides a row the caller may no
  ///    longer change, e.g. after a role was taken away); the entry stays
  ///    queued with the reason, and is parked after [syncOutboxMaxRetries]
  ///    so Team & sync shows it. A delete of a row that is already gone is
  ///    done.
  ///
  /// A rejected entry no longer stops the drain. Later writes to the same
  /// record, and writes whose payload points at it (a task of a project
  /// the server refused), wait for the next run so per-record order holds;
  /// unrelated work goes through. A network failure stops the run without
  /// counting against the entry: being offline must never park a write.
  Future<SyncPushResult> pushPending() => _synchronized(() async {
        final entries = await db.syncOutboxDao.pending();
        var succeeded = 0;
        final blocked = <String>{};
        for (final entry in entries) {
          final payload = jsonDecode(entry.payload) as Map<String, dynamic>;
          if (blocked.contains(entry.recordId) ||
              payload.values.any((v) => v is String && v != entry.recordId && blocked.contains(v))) {
            blocked.add(entry.recordId);
            continue;
          }
          try {
            await _pushOne(entry, _toRemoteIds(payload));
            await db.syncOutboxDao.markSynced(entry.id);
            succeeded++;
          } catch (e) {
            if (isTransientSyncError(e)) {
              await db.syncOutboxDao.noteTransientFailure(entry.id, e.toString());
              break;
            }
            await db.syncOutboxDao.recordFailure(entry.id, e.toString());
            blocked.add(entry.recordId);
          }
        }
        return SyncPushResult(succeeded: succeeded, failed: entries.length - succeeded);
      });

  /// Tables whose rows carry a file in Storage, and the column holding its
  /// object path ({projectId}/...). Push uploads the file before the row,
  /// so a visible row always has a downloadable object behind it.
  static const fileColumns = {
    'documents': 'file_path',
    'dpr_photos': 'photo_path',
    'expense_attachments': 'file_path',
  };

  /// The Storage bucket every synced file lives in. Its policies key access
  /// off the object path's first folder (the project id).
  static const filesBucket = 'documents';

  Future<void> _pushOne(SyncOutboxData entry, Map<String, dynamic> data) async {
    final table = client.from(entry.targetTable);
    final fileColumn = fileColumns[entry.targetTable];
    final localPath = data.remove('_local_file_path') as String?;
    if (fileColumn != null && entry.operation == 'insert') {
      if (localPath == null) throw StateError('${entry.targetTable} outbox payload missing _local_file_path');
      final file = File(localPath);
      if (!file.existsSync()) {
        throw StateError('The file for this ${entry.targetTable} row is no longer on the phone: $localPath');
      }
      // upsert: a replay after a lost response re-sends the same bytes to
      // the same path instead of failing on "already exists".
      await client.storage
          .from(filesBucket)
          .uploadBinary(data[fileColumn] as String, file.readAsBytesSync(), fileOptions: const FileOptions(upsert: true));
    }
    switch (entry.operation) {
      case 'insert':
        try {
          await table.insert(data);
        } on PostgrestException catch (e) {
          if (e.code != '23505' || !await _visibleOnServer(entry.targetTable, entry.recordId)) rethrow;
        }
        if (entry.targetTable == 'site_expenses') await _takeServerVoucher(entry.recordId);
      case 'upsert':
        await table.upsert(data);
      case 'update':
        final touched = await table.update(data).eq('id', entry.recordId).select('id');
        if (touched.isEmpty) {
          throw SyncNotAppliedException(entry.targetTable, entry.recordId,
              await _visibleOnServer(entry.targetTable, entry.recordId)
                  ? 'the server refused the change (no permission to edit it any more)'
                  : 'the record is gone from the server or no longer shared with you');
        }
      case 'delete':
        final touched = await table.delete().eq('id', entry.recordId).select('id');
        if (touched.isEmpty && await _visibleOnServer(entry.targetTable, entry.recordId)) {
          throw SyncNotAppliedException(
              entry.targetTable, entry.recordId, 'the server refused to delete it (no permission)');
        }
      default:
        throw StateError('Unknown outbox operation: ${entry.operation}');
    }
  }

  /// The server numbers vouchers (20261110000000_server_voucher_numbers.sql);
  /// show its number straight away instead of the phone's provisional one.
  Future<void> _takeServerVoucher(String expenseId) async {
    final row = await client.from('site_expenses').select('voucher_no').eq('id', expenseId).maybeSingle();
    final n = row?['voucher_no'];
    if (n is num) await db.expenseDao.setServerVoucher(expenseId, n.toInt());
  }

  Future<bool> _visibleOnServer(String table, String id) async =>
      (await client.from(table).select('id').eq('id', id).maybeSingle()) != null;

  /// One-shot pull: fetches every row the current session's RLS allows and
  /// merges into local Drift. Useful for an initial sync or a manual
  /// "refresh" -- the Realtime subscriptions below are for ongoing live
  /// updates after that. Serialized with pushPending (see _synchronized).
  ///
  /// Two guarantees on top of a plain server-wins merge:
  ///  - A row this device has edited but not yet pushed (still in the
  ///    outbox, pending or parked after failures) is never overwritten. A
  ///    failed push used to be followed straight away by this pull, which
  ///    replaced the unsynced local edit with the older server copy --
  ///    silent data loss on any flaky connection.
  ///  - Every table is paged ([pullPageSize] rows per request). PostgREST
  ///    caps an unpaged select at 1,000 rows by default, so a company's
  ///    1,001st DPR or task simply never reached a second phone.
  Future<void> pullAll() => _synchronized(() async {
    final dirty = await db.syncOutboxDao.dirtyKeys();

    Future<void> pull(String table, Future<void> Function(Map<String, dynamic> row) upsert) async {
      for (final row in await _fetchAll(table)) {
        if (dirty.contains(SyncOutboxDao.key(table, row['id'] as String))) continue;
        await _notifyIfNew(table, row);
        await upsert(row);
      }
    }

    await pull('projects', (r) => db.projectDao.upsertFromRemote(projectFromSupabaseJson(r)));
    await pull('tasks', (r) => db.taskDao.upsertFromRemote(taskFromSupabaseJson(r)));
    await pull('dpr_entries', (r) => db.dprDao.upsertFromRemote(dprEntryFromSupabaseJson(r)));
    await pull('issues', (r) => db.issueDao.upsertFromRemote(issueFromSupabaseJson(r)));
    await pull('workers', (r) => db.workerDao.upsertFromRemote(workerFromSupabaseJson(r)));
    await pull('equipment', (r) => db.equipmentDao.upsertFromRemote(equipmentFromSupabaseJson(r)));
    await pull('equipment_logs', (r) => db.equipmentDao.upsertLogFromRemote(equipmentLogFromSupabaseJson(r)));
    await pull('inspections', (r) => db.inspectionDao.upsertFromRemote(inspectionFromSupabaseJson(r)));
    await pull('inspection_items', (r) => db.inspectionDao.upsertItemFromRemote(inspectionItemFromSupabaseJson(r)));
    await pull('subcontractors', (r) => db.subcontractorDao.upsertFromRemote(subcontractorFromSupabaseJson(r)));
    await pull('work_orders', (r) => db.workOrderDao.upsertFromRemoteWorkOrder(workOrderFromSupabaseJson(r)));
    await pull('approvals', (r) => db.approvalDao.upsertFromRemote(approvalFromSupabaseJson(r)));
    await pull('vendors', (r) => db.supplierDao.upsertFromRemote(supplierFromSupabaseJson(r)));
    await pull('estimations', (r) => db.estimationDao.upsertFromRemote(estimationFromSupabaseJson(r)));
    await pull('cost_heads', (r) => db.estimationDao.upsertFromRemoteCostHead(costHeadFromSupabaseJson(r)));
    await pull('measurement_entries',
        (r) => db.estimationDao.upsertFromRemoteMeasurement(measurementEntryFromSupabaseJson(r)));
    await pull('steel_entries', (r) => db.estimationDao.upsertFromRemoteSteel(steelEntryFromSupabaseJson(r)));
    await pull('purchase_requisitions',
        (r) => db.purchaseDao.upsertFromRemoteRequest(purchaseRequestFromSupabaseJson(r)));
    await pull('purchase_orders', (r) => db.purchaseDao.upsertFromRemoteOrder(purchaseOrderFromSupabaseJson(r)));
    await pull('project_messages', (r) => db.messageDao.upsertFromRemote(projectMessageFromSupabaseJson(r)));
    await pull('site_attendance', (r) => db.attendanceDao.upsertFromRemote(attendanceFromSupabaseJson(r)));
    await pull('site_expenses', (r) => db.expenseDao.upsertFromRemote(siteExpenseFromSupabaseJson(r)));
    await pull('site_material_receipts',
        (r) => db.materialDao.upsertReceiptFromRemote(materialReceiptFromSupabaseJson(r)));
    await pull('site_material_usage', (r) => db.materialDao.upsertUsageFromRemote(materialUsageFromSupabaseJson(r)));
    await pull('site_payments_received', (r) => db.paymentDao.upsertFromRemote(paymentReceivedFromSupabaseJson(r)));
    await pull('site_client_bills', (r) => db.billDao.upsertFromRemote(clientBillFromSupabaseJson(r)));
    await pull('site_attendance_marks',
        (r) => db.attendanceDao.upsertMarkFromRemote(attendanceMarkFromSupabaseJson(r)));
    await pull('site_notes', (r) => db.noteDao.upsertFromRemote(projectNoteFromSupabaseJson(r)));
    await pull('documents', (row) async {
      final docsDir = await _resolveDocumentsDirectory();
      final safeName = (row['name'] as String).replaceAll(RegExp(r'[^\w.\-]'), '_');
      final localFile = File('${docsDir.path}/${row['id']}_$safeName');
      // Document rows are immutable once uploaded (same id = same bytes), so
      // a file already on disk is not downloaded again on every pull -- that
      // re-fetched every attachment every 5 minutes over mobile data.
      if (!localFile.existsSync()) {
        // A visible row must have a downloadable object (push uploads the
        // file before inserting). A failure here is a real anomaly --
        // surfacing it beats silently shipping a row pointing at nothing.
        final bytes = await client.storage.from('documents').download(row['file_path'] as String);
        await localFile.writeAsBytes(bytes);
      }
      await db.documentDao.upsertFromRemote(documentFromSupabaseJson(row, localPath: localFile.path));
    });
  });

  /// Rows per PostgREST request when pulling. Below the server's default
  /// 1,000-row cap so a full page is never mistaken for the last one.
  static const pullPageSize = 500;

  Future<List<Map<String, dynamic>>> _fetchAll(String table) async {
    final out = <Map<String, dynamic>>[];
    var from = 0;
    while (true) {
      final rows = await client.from(table).select().order('id').range(from, from + pullPageSize - 1);
      out.addAll(rows.map(_toLocalIds));
      if (rows.length < pullPageSize) break;
      from += pullPageSize;
    }
    return out;
  }

  /// Tables whose arrival from a colleague is worth an on-device alert.
  static const notifiableTables = {'issues', 'approvals', 'project_messages'};

  Future<void> _notifyIfNew(String table, Map<String, dynamic> row) async {
    final callback = onRemoteRowCreated;
    if (callback == null || !notifiableTables.contains(table)) return;
    final exists = await db
        .customSelect('SELECT 1 FROM $table WHERE id = ?', variables: [Variable<String>(row['id'] as String)])
        .getSingleOrNull();
    if (exists == null) callback(table, row);
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
            final row = _toLocalIds(payload.newRecord);
            if (!await _acceptRealtime('tasks', row)) return;
            await db.taskDao.upsertFromRemote(taskFromSupabaseJson(row));
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
            final row = _toLocalIds(payload.newRecord);
            if (!await _acceptRealtime('projects', row)) return;
            await db.projectDao.upsertFromRemote(projectFromSupabaseJson(row));
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
            final row = _toLocalIds(payload.newRecord);
            if (!await _acceptRealtime('vendors', row)) return;
            await db.supplierDao.upsertFromRemote(supplierFromSupabaseJson(row));
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
            final row = _toLocalIds(payload.newRecord);
            if (!await _acceptRealtime('dpr_entries', row)) return;
            await db.dprDao.upsertFromRemote(dprEntryFromSupabaseJson(row));
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
            final row = _toLocalIds(payload.newRecord);
            if (!await _acceptRealtime('issues', row)) return;
            await db.issueDao.upsertFromRemote(issueFromSupabaseJson(row));
            onIssuesChanged?.call();
          },
        );
    _issuesChannel = channel;
    await _awaitJoin(channel, label: 'issues-$projectId');
  }

  /// Same two rules as [pullAll] for a single live row: never clobber an
  /// unpushed local edit; report a colleague's brand-new notifiable row.
  Future<bool> _acceptRealtime(String table, Map<String, dynamic> row) async {
    final dirty = await db.syncOutboxDao.dirtyKeys();
    if (dirty.contains(SyncOutboxDao.key(table, row['id'] as String))) return false;
    await _notifyIfNew(table, row);
    return true;
  }

  /// Live team chat for one project. See subscribeToProjectTasks's
  /// docstring for why this awaits the join.
  Future<void> subscribeToProjectMessages(String projectId) async {
    await _messagesChannel?.unsubscribe();
    final channel = client.channel('messages-$projectId').onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'project_messages',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'project_id', value: projectId),
          callback: (payload) async {
            final row = _toLocalIds(payload.newRecord);
            if (!await _acceptRealtime('project_messages', row)) return;
            await db.messageDao.upsertFromRemote(projectMessageFromSupabaseJson(row));
            onMessagesChanged?.call();
          },
        );
    _messagesChannel = channel;
    await _awaitJoin(channel, label: 'messages-$projectId');
  }

  Future<void> unsubscribeFromProjectMessages() async {
    await _messagesChannel?.unsubscribe();
    _messagesChannel = null;
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
    if (_messagesChannel != null) await _messagesChannel!.unsubscribe();
  }
}
