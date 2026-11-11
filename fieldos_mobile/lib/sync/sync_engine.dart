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

import 'package:drift/drift.dart' show Value, Variable;
import 'package:http/http.dart' show ClientException;
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'app_version_gate.dart';
import 'site_execution_sync.dart';
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

/// The write's table is not on this backend yet: a newer migration adds
/// it. The entry waits (it never counts toward parking) until it is.
class SyncWaitingForServerException implements Exception {
  const SyncWaitingForServerException(this.table);
  final String table;
  @override
  String toString() => 'Waiting for a server update ($table is not on the server yet)';
}

class _NothingToSend implements Exception {
  const _NothingToSend();
}

/// PostgREST: table/relation missing (PGRST205, or Postgres 42P01).
bool isMissingTableError(PostgrestException e) => e.code == 'PGRST205' || e.code == '42P01';

/// The column PostgREST says it cannot find (PGRST204: "Could not find
/// the 'distance_m' column of 'site_attendance' in the schema cache"), or
/// null for any other error.
String? missingColumnOf(PostgrestException e) {
  if (e.code != 'PGRST204' && e.code != '42703') return null;
  return RegExp(r"'([^']+)' column").firstMatch(e.message)?.group(1) ??
      RegExp(r'column "?([A-Za-z0-9_]+)"? (of relation \S+ )?does not exist').firstMatch(e.message)?.group(1);
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
  SyncEngine(
      {required this.db, required this.client, Future<Directory> Function()? resolveDocumentsDirectory, this.versionGate})
      : _resolveDocumentsDirectory = resolveDocumentsDirectory ?? localDocumentsDirectory;

  final AppDatabase db;
  final SupabaseClient client;

  /// When set, a build older than the server's minimum (issue #146) stops
  /// before touching the server: [pushPending] and [pullAll] throw
  /// [AppUpdateRequired] and the outbox stays as it is on the phone.
  final AppVersionGate? versionGate;
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
    'decided_by', 'submitted_by', 'holder_id', 'certified_by', 'raised_by', 'owner_id', 'acted_by', 'measured_by', 'by_user',
    'sent_by', 'issued_by', 'taken_by', 'reviewed_by', 'supervisor_id', 'backup_id', 'updated_by', 'changed_by',
    ...siteExecutionUserColumns,
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
  Future<SyncPushResult> pushPending() async {
    await versionGate?.requireSupported();
    return _pushPending();
  }

  Future<SyncPushResult> _pushPending() => _synchronized(() async {
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
            if (e is SyncWaitingForServerException) {
              // The table is not on this backend yet (its migration is still
              // to be applied). Keep the write, never count it toward
              // parking, and let unrelated work through.
              await db.syncOutboxDao.noteTransientFailure(entry.id, e.toString());
              blocked.add(entry.recordId);
              continue;
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
    'site_receipt_attachments': 'file_path',
    'commercial_attachments': 'file_path',
    'attendance_photos': 'file_path',
    'site_drawing_revisions': 'file_path',
    'site_execution_photos': 'file_path',
  };

  /// The Storage bucket every synced file lives in. Its policies key access
  /// off the object path's first folder (the project id).
  static const filesBucket = 'documents';

  /// Tables this backend answered "does not exist" for, and until when
  /// to stop trying them (so a waiting photo is not re-uploaded on every
  /// sync). Cleared by time, so a migration applied later is picked up.
  final Map<String, DateTime> _missingTablesUntil = {};
  static const missingTableRecheck = Duration(minutes: 30);

  Future<void> _pushOne(SyncOutboxData entry, Map<String, dynamic> data) async {
    final until = _missingTablesUntil[entry.targetTable];
    if (until != null && DateTime.now().isBefore(until)) {
      throw SyncWaitingForServerException(entry.targetTable);
    }
    try {
      await _pushOneUnguarded(entry, data);
    } on PostgrestException catch (e) {
      if (!isMissingTableError(e)) rethrow;
      _missingTablesUntil[entry.targetTable] = DateTime.now().add(missingTableRecheck);
      throw SyncWaitingForServerException(entry.targetTable);
    }
  }

  /// Runs [write] with [data]; when the backend lacks a column a newer
  /// migration adds (PGRST204), drops that column and tries again. The
  /// row's core fields still reach the team; the extra detail (a GPS
  /// distance, a cost code) stays on the phone.
  static Future<T> _dropMissingColumns<T>(
      Map<String, dynamic> data, Future<T> Function(Map<String, dynamic> data) write) async {
    for (var i = 0;; i++) {
      try {
        return await write(data);
      } on PostgrestException catch (e) {
        final column = missingColumnOf(e);
        if (column == null || !data.containsKey(column) || column == 'id' || i >= 20) rethrow;
        data = Map.of(data)..remove(column);
      }
    }
  }

  Future<void> _pushOneUnguarded(SyncOutboxData entry, Map<String, dynamic> data) async {
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
          await _dropMissingColumns(data, (d) => table.insert(d));
        } on PostgrestException catch (e) {
          if (e.code != '23505' || !await _visibleOnServer(entry.targetTable, entry.recordId)) rethrow;
        }
        if (entry.targetTable == 'site_expenses') await _takeServerVoucher(entry.recordId);
      case 'upsert':
        await _dropMissingColumns(data, (d) => table.upsert(d));
      case 'update':
        final List<dynamic> touched;
        try {
          touched = await _dropMissingColumns(data, (d) {
            // Every changed column is one this backend does not have yet:
            // nothing to send. The phone keeps the change.
            if (d.keys.every((k) => k == 'id')) throw const _NothingToSend();
            return table.update(d).eq('id', entry.recordId).select('id');
          });
        } on _NothingToSend {
          return;
        }
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
        final objectPath = fileColumn == null ? null : data[fileColumn] as String?;
        if (objectPath != null) {
          // The row is gone; the file behind it is only storage cost now.
          try {
            await client.storage.from(filesBucket).remove([objectPath]);
          } catch (_) {}
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

  /// Pull: the first time (per account) every row the session's RLS
  /// allows, after that only what the server's change log
  /// (20261110020000_incremental_sync.sql) lists since the last pull,
  /// including deletes. Sites no longer shared are removed from the phone.
  /// The Realtime subscriptions below are for live updates in between.
  /// Serialized with pushPending (see _synchronized).
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
  ///  - Unsent work and the local-only sample site are never removed.
  Future<void> pullAll() async {
    await versionGate?.requireSupported();
    return _pullAll();
  }

  Future<void> _pullAll() => _synchronized(() async {
        final dirty = await db.syncOutboxDao.dirtyKeys();
        final keep = {...dirty.map((k) => k.substring(k.indexOf(':') + 1)), ...await db.syncOutboxDao.localOnlyIds()};
        final cursorKey = 'sync_cursor:${client.auth.currentUser?.id}';
        final cursor = int.tryParse(await db.settingsDao.get(cursorKey) ?? '');
        // A backend without 20261110020000_incremental_sync.sql yet: full
        // pulls, as before, until it is deployed.
        final floor = await _rpcIntOrNull('sync_changes_floor');
        if (floor == null) {
          await _pullEverything(dirty, keep);
        } else if (cursor != null && cursor >= floor) {
          final next = await _pullChanges(cursor, dirty, keep);
          await db.settingsDao.set(cursorKey, '$next');
        } else {
          // Lines logged while the full pull runs are applied again next
          // time, which is harmless (every apply is an upsert or a delete).
          final head = await _rpcInt('sync_changes_head');
          await _pullEverything(dirty, keep);
          await db.settingsDao.set(cursorKey, '$head');
        }
        final portalSites = await _pullSubcontractorSites();
        await _dropProjectsNoLongerShared({...keep, ...portalSites});
        await _exchangeSyncStatus();
      });

  /// Tells the server this phone just synced (and how much is still
  /// waiting on it), then reads when every teammate's phone last did. The
  /// manager's "Report not received · last synced at 2:10 pm" comes from
  /// here: without it, a report saved offline and a report never written
  /// look the same. A backend without 20261110200000_daily_site_close.sql
  /// yet is skipped.
  Future<void> _exchangeSyncStatus() async {
    final raw = await db.settingsDao.get('cloud_linked_companies');
    if (raw == null || raw.isEmpty) return;
    final linked = (jsonDecode(raw) as List).cast<String>();
    final pending = await db.syncOutboxDao.pendingCount();
    try {
      for (final companyId in linked) {
        try {
          await client.rpc('report_sync_status', params: {'p_company_id': companyId, 'p_pending': pending});
        } on PostgrestException catch (e) {
          // Removed from the company: the pull takes its data off this
          // phone; there is no status to report.
          if (e.code == '42501') continue;
          rethrow;
        }
        final rows = await client.from('member_sync_status').select().eq('company_id', companyId);
        await db.dayCloseDao.replaceSyncStatus(
            companyId, [for (final r in rows) memberSyncStatusFromSupabaseJson(_toLocalIds(r))]);
      }
    } on PostgrestException catch (e) {
      if (!_isMissingOnServer(e)) rethrow;
    }
  }

  /// A subcontractor can't read the projects table (it carries the client
  /// and money columns), so the sites they work on come by name only.
  /// Existing rows (an account that is also on the company) are left as
  /// they are.
  Future<Set<String>> _pullSubcontractorSites() async {
    final List rows;
    try {
      rows = await client.rpc('subcontractor_sites') as List;
    } on PostgrestException catch (e) {
      if (_isMissingOnServer(e)) return const {};
      rethrow;
    }
    final out = <String>{};
    for (final r in rows.cast<Map>()) {
      final id = r['id'] as String;
      out.add(id);
      if (await db.projectDao.byId(id) != null) continue;
      await db.projectDao.upsertFromRemote(ProjectsCompanion.insert(
          id: id, companyId: r['company_id'] as String, name: r['name'] as String, status: const Value('active')));
    }
    return out;
  }

  /// How each pulled table lands in Drift, parents before children.
  late final Map<String, Future<void> Function(Map<String, dynamic> row)> _upserters = {
        'projects': (r) => db.projectDao.upsertFromRemote(projectFromSupabaseJson(r)),
        'site_access': (r) => db.siteTeamDao.upsertAccessFromRemote(siteAccessFromSupabaseJson(r)),
        'project_members': (r) => db.siteTeamDao.upsertMemberFromRemote(projectMemberFromSupabaseJson(r)),
        'tasks': (r) => db.taskDao.upsertFromRemote(taskFromSupabaseJson(r)),
        'dpr_entries': (r) => db.dprDao.upsertFromRemote(dprEntryFromSupabaseJson(r)),
        'issues': (r) => db.issueDao.upsertFromRemote(issueFromSupabaseJson(r)),
        'workers': (r) => db.workerDao.upsertFromRemote(workerFromSupabaseJson(r)),
        'equipment': (r) => db.equipmentDao.upsertFromRemote(equipmentFromSupabaseJson(r)),
        'equipment_logs': (r) => db.equipmentDao.upsertLogFromRemote(equipmentLogFromSupabaseJson(r)),
        'inspections': (r) => db.inspectionDao.upsertFromRemote(inspectionFromSupabaseJson(r)),
        'inspection_items': (r) => db.inspectionDao.upsertItemFromRemote(inspectionItemFromSupabaseJson(r)),
        'subcontractors': (r) => db.subcontractorDao.upsertFromRemote(subcontractorFromSupabaseJson(r)),
        'work_orders': (r) => db.workOrderDao.upsertFromRemoteWorkOrder(workOrderFromSupabaseJson(r)),
        'approvals': (r) => db.approvalDao.upsertFromRemote(approvalFromSupabaseJson(r)),
        'vendors': (r) => db.supplierDao.upsertFromRemote(supplierFromSupabaseJson(r)),
        'estimations': (r) => db.estimationDao.upsertFromRemote(estimationFromSupabaseJson(r)),
        'cost_heads': (r) => db.estimationDao.upsertFromRemoteCostHead(costHeadFromSupabaseJson(r)),
        'measurement_entries': (r) => db.estimationDao.upsertFromRemoteMeasurement(measurementEntryFromSupabaseJson(r)),
        'steel_entries': (r) => db.estimationDao.upsertFromRemoteSteel(steelEntryFromSupabaseJson(r)),
        'purchase_requisitions': (r) => db.purchaseDao.upsertFromRemoteRequest(purchaseRequestFromSupabaseJson(r)),
        'purchase_orders': (r) => db.purchaseDao.upsertFromRemoteOrder(purchaseOrderFromSupabaseJson(r)),
        'project_messages': (r) => db.messageDao.upsertFromRemote(projectMessageFromSupabaseJson(r)),
        'site_attendance': (r) => db.attendanceDao.upsertFromRemote(attendanceFromSupabaseJson(r)),
        'site_expenses': (r) => db.expenseDao.upsertFromRemote(siteExpenseFromSupabaseJson(r)),
        'site_material_receipts': (r) => db.materialDao.upsertReceiptFromRemote(materialReceiptFromSupabaseJson(r)),
        'site_material_usage': (r) => db.materialDao.upsertUsageFromRemote(materialUsageFromSupabaseJson(r)),
        'site_payments_received': (r) => db.paymentDao.upsertFromRemote(paymentReceivedFromSupabaseJson(r)),
        'site_client_bills': (r) => db.billDao.upsertFromRemote(clientBillFromSupabaseJson(r)),
        'site_attendance_marks': (r) => db.attendanceDao.upsertMarkFromRemote(attendanceMarkFromSupabaseJson(r)),
        'site_notes': (r) => db.noteDao.upsertFromRemote(projectNoteFromSupabaseJson(r)),
        'dpr_photos': (r) async {
      final mine = await db.dprDao.photoById(r['id'] as String);
      if (mine != null && File(mine.photoPath).existsSync()) return;
      final local = await _downloadFile(r['photo_path'] as String, r['id'] as String);
      if (local != null) await db.dprDao.upsertPhotoFromRemote(dprPhotoFromSupabaseJson(r, localPath: local));
    },
        'expense_attachments': (r) async {
      final mine = await db.expenseDao.attachmentById(r['id'] as String);
      if (mine != null && File(mine.filePath).existsSync()) return;
      final local = await _downloadFile(r['file_path'] as String, r['id'] as String);
      if (local != null) await db.expenseDao.upsertAttachmentFromRemote(expenseAttachmentFromSupabaseJson(r, localPath: local));
    },
        'site_receipt_attachments': (r) async {
      final mine = await db.materialDao.slipById(r['id'] as String);
      if (mine != null && File(mine.filePath).existsSync()) return;
      final local = await _downloadFile(r['file_path'] as String, r['id'] as String);
      if (local != null) await db.materialDao.upsertSlipFromRemote(receiptAttachmentFromSupabaseJson(r, localPath: local));
    },
        'site_close_reviews': (r) => db.closeDao.upsertFromRemote(closeReviewFromSupabaseJson(r)),
        'cost_codes': (r) => db.commercialDao.upsertCostCode(costCodeFromSupabaseJson(r)),
        'work_claims': (r) => db.commercialDao.upsertClaim(workClaimFromSupabaseJson(r)),
        'variations': (r) => db.commercialDao.upsertVariation(variationFromSupabaseJson(r)),
        'variation_decisions': (r) => db.commercialDao.upsertDecision(variationDecisionFromSupabaseJson(r)),
        'work_certifications': (r) => db.commercialDao.upsertCertification(workCertificationFromSupabaseJson(r)),
        'commercial_exception_actions': (r) =>
            db.commercialDao.upsertExceptionAction(exceptionActionFromSupabaseJson(r)),
        'site_close_settings': (r) => db.dayCloseDao.upsertSettingsFromRemote(siteCloseSettingFromSupabaseJson(r)),
        'site_day_events': (r) => db.dayCloseDao.upsertEventFromRemote(siteDayEventFromSupabaseJson(r)),
        'site_cash_moves': (r) => db.cashBookDao.upsertFromRemote(cashMoveFromSupabaseJson(r)),
        'site_floor_progress': (r) => db.floorProgressDao.upsertFromRemote(floorProgressFromSupabaseJson(r)),
        'entry_history': (r) => db.entryHistoryDao.upsertFromRemote(entryHistoryFromSupabaseJson(r)),
        'commercial_attachments': (r) async {
      final mine = await db.commercialDao.attachmentById(r['id'] as String);
      if (mine != null && File(mine.filePath).existsSync()) return;
      final local = await _downloadFile(r['file_path'] as String, r['id'] as String);
      if (local != null) {
        await db.commercialDao.upsertAttachment(commercialAttachmentFromSupabaseJson(r, localPath: local));
      }
    },
        for (final t in siteExecutionTables.keys)
          t: (r) async {
            if (!siteExecutionFileFolders.containsKey(t)) {
              return db.siteExecutionDao.upsertFromRemote(t, executionFromRemote(t, r));
            }
            final mine = await db
                .customSelect('SELECT file_path AS f FROM ${siteExecutionTables[t]} WHERE id = ?',
                    variables: [Variable<String>(r['id'] as String)])
                .getSingleOrNull();
            final kept = mine?.read<String>('f');
            final local = kept != null && File(kept).existsSync()
                ? kept
                : await _downloadFile(r['file_path'] as String, r['id'] as String);
            if (local != null) await db.siteExecutionDao.upsertFromRemote(t, executionFromRemote(t, r, localPath: local));
          },
        'crm_leads': (r) => db.crmDao.upsertLeadFromRemote(crmLeadFromSupabaseJson(r)),
        'crm_activities': (r) => db.crmDao.upsertActivityFromRemote(crmActivityFromSupabaseJson(r)),
        'crm_quotes': (r) => db.crmDao.upsertQuoteFromRemote(crmQuoteFromSupabaseJson(r)),
        'stores': (r) => db.warehouseDao.upsertStoreFromRemote(storeFromSupabaseJson(r)),
        'stock_moves': (r) => db.warehouseDao.upsertMoveFromRemote(stockMoveFromSupabaseJson(r)),
        'tools': (r) => db.warehouseDao.upsertToolFromRemote(toolFromSupabaseJson(r)),
        'tool_issues': (r) => db.warehouseDao.upsertIssueFromRemote(toolIssueFromSupabaseJson(r)),
        'staff_members': (r) => db.payrollDao.upsertStaffFromRemote(staffMemberFromSupabaseJson(r)),
        'staff_advances': (r) => db.payrollDao.upsertAdvanceFromRemote(staffAdvanceFromSupabaseJson(r)),
        'payroll_lines': (r) => db.payrollDao.upsertLineFromRemote(payrollLineFromSupabaseJson(r)),
        'site_supplier_quotes': (r) => db.supplierQuoteDao.upsertFromRemote(supplierQuoteFromSupabaseJson(r)),
        'staff_attendance': (r) => db.staffAttendanceDao.upsertFromRemote(staffAttendanceFromSupabaseJson(r)),
        'attendance_photos': (r) async {
      final mine = await db.staffAttendanceDao.photoById(r['id'] as String);
      if (mine != null && File(mine.filePath).existsSync()) return;
      final local = await _downloadFile(r['file_path'] as String, r['id'] as String);
      if (local != null) {
        await db.staffAttendanceDao.upsertPhotoFromRemote(attendancePhotoFromSupabaseJson(r, localPath: local));
      }
    },
        'site_work_measurements': (r) =>
            db.billingRecordsDao.upsertMeasurementFromRemote(workMeasurementFromSupabaseJson(r)),
        'site_work_measurement_decisions': (r) =>
            db.billingRecordsDao.upsertDecisionFromRemote(measurementDecisionFromSupabaseJson(r)),
        'site_bill_allocations': (r) => db.billingRecordsDao.upsertAllocationFromRemote(billAllocationFromSupabaseJson(r)),
        'site_supplier_invoices': (r) =>
            db.billingRecordsDao.upsertSupplierInvoiceFromRemote(supplierInvoiceFromSupabaseJson(r)),
        'site_approval_rules': (r) => db.approvalChainDao.upsertRuleFromRemote(approvalRuleFromSupabaseJson(r)),
        'site_approval_steps': (r) => db.approvalChainDao.upsertStepFromRemote(approvalStepFromSupabaseJson(r)),
        'documents': (row) async {
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
    },
      };

  Future<int> _rpcInt(String fn) async => ((await client.rpc(fn)) as num).toInt();

  Future<int?> _rpcIntOrNull(String fn) async {
    try {
      return await _rpcInt(fn);
    } on PostgrestException catch (e) {
      if (_isMissingOnServer(e)) return null;
      rethrow;
    }
  }

  /// A function or table a newer migration adds, not deployed on this
  /// backend yet (PostgREST: PGRST202 function, PGRST205 table).
  static bool _isMissingOnServer(PostgrestException e) =>
      e.code == 'PGRST202' || e.code == 'PGRST205' || e.code == '42P01' || e.code == '42883';

  Future<void> _apply(String table, Map<String, dynamic> row, Set<String> dirty) async {
    if (dirty.contains(SyncOutboxDao.key(table, row['id'] as String))) return;
    await _notifyIfNew(table, row);
    final kept = await _keepLocalOnlyColumns(table, row);
    if (kept != null) {
      try {
        return await _upserters[table]!(kept);
      } catch (_) {
        // A kept value the mapper cannot read: apply the server row as is.
      }
    }
    await _upserters[table]!(row);
  }

  /// Per table, this phone's columns the backend's rows do not carry (its
  /// newer migrations are not applied yet), worked out from the first row.
  final Map<String, Set<String>> _columnsServerLacks = {};

  /// When the backend lacks some of this phone's columns (a GPS distance, a
  /// selfie, a cost code), the server row would wipe them here on every
  /// pull. Returns [row] with the phone's own values for those columns, or
  /// null when there is nothing to keep.
  Future<Map<String, dynamic>?> _keepLocalOnlyColumns(String table, Map<String, dynamic> row) async {
    final local = localTableNames[table];
    if (local == null) return null;
    var lacks = _columnsServerLacks[table];
    if (lacks == null) {
      final columns = await db.customSelect('SELECT name FROM pragma_table_info(?)', variables: [Variable<String>(local)]).get();
      lacks = _columnsServerLacks[table] = {
        for (final c in columns)
          if (!row.containsKey(c.read<String>('name'))) c.read<String>('name')
      };
    }
    if (lacks.isEmpty) return null;
    final mine = await db
        .customSelect('SELECT * FROM $local WHERE id = ?', variables: [Variable<String>(row['id'] as String)])
        .getSingleOrNull();
    if (mine == null) return null;
    Map<String, dynamic>? out;
    for (final c in lacks) {
      final v = mine.data[c];
      if (v == null || row.containsKey(c)) continue;
      (out ??= Map.of(row))[c] = v;
    }
    return out;
  }

  /// First sync on this phone (or for this account), or a cursor older than
  /// the change log: every visible row, then local rows of those sites that
  /// the server no longer has are removed.
  Future<void> _pullEverything(Set<String> dirty, Set<String> keep) async {
    final seen = <String, Set<String>>{};
    for (final table in _upserters.keys) {
      final List<Map<String, dynamic>> rows;
      try {
        rows = await _fetchAll(table);
      } on PostgrestException catch (e) {
        if (!_isMissingOnServer(e)) rethrow;
        continue; // not on this backend yet; nothing to reconcile either
      }
      seen[table] = {for (final r in rows) r['id'] as String};
      for (final row in rows) {
        await _apply(table, row, dirty);
      }
    }
    final sites = seen['projects'] ?? const <String>{};
    if (sites.isEmpty) return;
    final marks = List.filled(sites.length, '?').join(',');
    for (final MapEntry(key: remote, value: local) in localTableNames.entries) {
      if (!_projectScoped.contains(remote) || !seen.containsKey(remote)) continue;
      final rows = await db
          .customSelect('SELECT id FROM $local WHERE project_id IN ($marks)',
              variables: [for (final s in sites) Variable<String>(s)])
          .get();
      for (final r in rows) {
        final id = r.read<String>('id');
        if (!seen[remote]!.contains(id) && !keep.contains(id)) await _deleteLocal(remote, id);
      }
    }
  }

  /// Only what changed since [cursor]: changed rows fetched by id, deleted
  /// ones removed. Returns the new cursor.
  Future<int> _pullChanges(int cursor, Set<String> dirty, Set<String> keep) async {
    final last = <String, ({String table, String op})>{};
    var next = cursor;
    while (true) {
      final page = await client
          .from('sync_changes')
          .select('seq, table_name, row_id, op')
          .gt('seq', next)
          .order('seq')
          .limit(pullPageSize);
      for (final c in page) {
        next = (c['seq'] as num).toInt();
        last['${c['table_name']}:${c['row_id']}'] = (table: c['table_name'] as String, op: c['op'] as String);
      }
      if (page.length < pullPageSize) break;
    }
    if (last.isEmpty) return next;

    final changed = <String, List<String>>{};
    final deleted = <({String table, String id})>[];
    for (final MapEntry(:key, :value) in last.entries) {
      final id = key.substring(key.indexOf(':') + 1);
      if (!_upserters.containsKey(value.table)) continue;
      if (value.op == 'd') {
        deleted.add((table: value.table, id: id));
      } else {
        (changed[value.table] ??= []).add(id);
      }
    }
    for (final table in _upserters.keys) {
      final ids = changed[table];
      if (ids == null) continue;
      for (var i = 0; i < ids.length; i += 100) {
        final chunk = ids.sublist(i, i + 100 > ids.length ? ids.length : i + 100);
        final rows = (await client.from(table).select().inFilter('id', chunk)).map(_toLocalIds).toList();
        final found = <String>{};
        for (final row in rows) {
          found.add(row['id'] as String);
          await _apply(table, row, dirty);
        }
        // Changed, but not readable now: deleted since, or no longer
        // shared with this account (e.g. money-in after a role change).
        for (final id in chunk) {
          if (!found.contains(id)) deleted.add((table: table, id: id));
        }
      }
    }
    // Children before parents.
    final order = _upserters.keys.toList();
    deleted.sort((a, b) => order.indexOf(b.table).compareTo(order.indexOf(a.table)));
    for (final d in deleted) {
      if (keep.contains(d.id) || dirty.contains(SyncOutboxDao.key(d.table, d.id))) continue;
      await _deleteLocal(d.table, d.id);
    }
    return next;
  }

  /// A site this account can no longer see (taken off it, removed from the
  /// company, or the site was deleted) is removed from the phone, with
  /// everything under it. Only sites of companies this phone syncs, and
  /// never one with unsent work or the local-only sample site.
  Future<void> _dropProjectsNoLongerShared(Set<String> keep) async {
    // Same setting as CloudLinks (cloud_sync_providers.dart).
    final raw = await db.settingsDao.get('cloud_linked_companies');
    if (raw == null || raw.isEmpty) return;
    final linked = (jsonDecode(raw) as List).cast<String>();
    if (linked.isEmpty) return;
    final visible = {for (final r in await _fetchIds('projects')) r};
    final marks = List.filled(linked.length, '?').join(',');
    final local = await db
        .customSelect('SELECT id FROM projects WHERE company_id IN ($marks)',
            variables: [for (final c in linked) Variable<String>(c)])
        .get();
    for (final r in local) {
      final id = r.read<String>('id');
      if (!visible.contains(id) && !keep.contains(id)) await _deleteLocal('projects', id);
    }
  }

  Future<List<String>> _fetchIds(String table) async {
    final out = <String>[];
    var from = 0;
    while (true) {
      final rows = await client.from(table).select('id').order('id').range(from, from + pullPageSize - 1);
      out.addAll(rows.map((r) => r['id'] as String));
      if (rows.length < pullPageSize) break;
      from += pullPageSize;
    }
    return out;
  }

  /// Server table -> this phone's Drift table.
  static const localTableNames = {
    ...siteExecutionTables,
    'projects': 'projects',
    'tasks': 'tasks',
    'dpr_entries': 'dpr_entries',
    'dpr_photos': 'dpr_photos',
    'issues': 'issues',
    'workers': 'workers',
    'equipment': 'equipment',
    'equipment_logs': 'equipment_logs',
    'inspections': 'inspections',
    'inspection_items': 'inspection_items',
    'subcontractors': 'subcontractors',
    'work_orders': 'work_orders',
    'approvals': 'approvals',
    'vendors': 'suppliers',
    'estimations': 'estimations',
    'cost_heads': 'cost_heads',
    'measurement_entries': 'measurement_entries',
    'steel_entries': 'steel_entries',
    'purchase_requisitions': 'purchase_requests',
    'purchase_orders': 'purchase_orders',
    'project_messages': 'project_messages',
    'site_attendance': 'labour_attendance',
    'site_expenses': 'site_expenses',
    'site_material_receipts': 'material_receipts',
    'site_material_usage': 'material_usage',
    'site_payments_received': 'payments_received',
    'site_client_bills': 'client_bills',
    'site_attendance_marks': 'attendance_marks',
    'site_notes': 'project_notes',
    'documents': 'documents',
    'expense_attachments': 'expense_attachments',
    'site_receipt_attachments': 'receipt_attachments',
    'site_close_reviews': 'close_reviews',
    'cost_codes': 'cost_codes',
    'work_claims': 'work_claims',
    'work_certifications': 'work_certifications',
    'variations': 'variations',
    'variation_decisions': 'variation_decisions',
    'commercial_attachments': 'commercial_attachments',
    'commercial_exception_actions': 'exception_actions',
    'crm_leads': 'crm_leads',
    'crm_activities': 'crm_activities',
    'crm_quotes': 'crm_quotes',
    'stores': 'stores',
    'stock_moves': 'stock_moves',
    'tools': 'tools',
    'tool_issues': 'tool_issues',
    'staff_members': 'staff_members',
    'staff_advances': 'staff_advances',
    'payroll_lines': 'payroll_lines',
    'site_supplier_quotes': 'supplier_quotes',
    'project_members': 'project_members',
    'site_access': 'site_access',
    'site_work_measurements': 'work_measurements',
    'site_work_measurement_decisions': 'work_measurement_decisions',
    'site_bill_allocations': 'bill_allocations',
    'site_supplier_invoices': 'supplier_invoices',
    'site_approval_rules': 'approval_rules',
    'site_approval_steps': 'approval_steps',
    'site_close_settings': 'site_close_settings',
    'site_day_events': 'site_day_events',
    'site_cash_moves': 'cash_moves',
    'site_floor_progress': 'floor_progress',
    'entry_history': 'entry_history',
    'attendance_photos': 'attendance_photos',
    'staff_attendance': 'staff_attendance',
  };

  /// Tables whose rows carry project_id on the phone too.
  static const _projectScoped = {
    'tasks', 'dpr_entries', 'issues', 'workers', 'equipment', 'inspections', 'work_orders', 'approvals',
    'estimations', 'purchase_requisitions', 'purchase_orders', 'project_messages', 'site_attendance',
    'site_expenses', 'site_material_receipts', 'site_material_usage', 'site_payments_received',
    'site_client_bills', 'site_attendance_marks', 'site_notes', 'documents', 'site_close_reviews',
    'cost_codes', 'work_claims', 'work_certifications', 'variations', 'variation_decisions',
    'commercial_attachments', 'commercial_exception_actions', 'site_supplier_quotes',
    'project_members', 'site_access', 'site_work_measurements', 'site_work_measurement_decisions',
    'site_bill_allocations', 'site_supplier_invoices', 'site_approval_steps', 'site_close_settings', 'site_day_events',
    'site_cash_moves', 'site_floor_progress', 'entry_history',
    'attendance_photos', 'staff_attendance',
    ...siteExecutionProjectScoped,
  };

  /// Children found through their parent, for removing a whole site or
  /// record: (child server table, its parent server table, link column).
  static const _children = [
    ('dpr_photos', 'dpr_entries', 'dpr_entry_id'),
    ('equipment_logs', 'equipment', 'equipment_id'),
    ('inspection_items', 'inspections', 'inspection_id'),
    ('measurement_entries', 'cost_heads', 'cost_head_id'),
    ('steel_entries', 'cost_heads', 'cost_head_id'),
    ('cost_heads', 'estimations', 'estimation_id'),
    ('expense_attachments', 'site_expenses', 'expense_id'),
    ('site_receipt_attachments', 'site_material_receipts', 'receipt_id'),
    ('crm_activities', 'crm_leads', 'lead_id'),
    ('crm_quotes', 'crm_leads', 'lead_id'),
    ('tool_issues', 'tools', 'tool_id'),
    ('staff_advances', 'staff_members', 'staff_id'),
    ('payroll_lines', 'staff_members', 'staff_id'),
  ];

  /// Removes a row from the phone, with what hangs off it (a site takes all
  /// its records along), and the files of removed photos and bills.
  Future<void> _deleteLocal(String table, String id) async {
    await db.transaction(() async {
      Future<void> drop(String t, String where, List<String> args) async {
        final local = localTableNames[t]!;
        for (final (child, parent, column) in _children) {
          if (parent != t) continue;
          final ids = await db
              .customSelect('SELECT id FROM $local WHERE $where', variables: [for (final a in args) Variable<String>(a)])
              .get();
          for (final r in ids) {
            await drop(child, '$column = ?', [r.read<String>('id')]);
          }
        }
        if (t == 'dpr_photos' ||
            t == 'expense_attachments' ||
            t == 'site_receipt_attachments' ||
            t == 'commercial_attachments' ||
            t == 'attendance_photos' ||
            siteExecutionFileFolders.containsKey(t)) {
          final column = t == 'dpr_photos' ? 'photo_path' : 'file_path';
          final files = await db
              .customSelect('SELECT $column AS f FROM $local WHERE $where',
                  variables: [for (final a in args) Variable<String>(a)])
              .get();
          for (final f in files) {
            try {
              File(f.read<String>('f')).deleteSync();
            } catch (_) {}
          }
        }
        await db.customStatement('DELETE FROM $local WHERE $where', args);
      }

      if (table == 'projects') {
        for (final t in _projectScoped) {
          await drop(t, 'project_id = ?', [id]);
        }
      }
      await drop(table, 'id = ?', [id]);
    });
  }

  /// Saves a teammate's photo or bill on this phone. A file that can't be
  /// fetched right now (weak signal) is skipped, not fatal: the row is left
  /// for the next pull, so one photo never holds up the rest of the sync.
  Future<String?> _downloadFile(String objectPath, String id) async {
    final dir = await _resolveDocumentsDirectory();
    final slash = objectPath.lastIndexOf('/');
    final name = objectPath.substring(slash + 1).replaceAll(RegExp(r'[^\w.\-]'), '_');
    final file = File('${dir.path}/synced_${name.isEmpty ? id : name}');
    if (!file.existsSync()) {
      try {
        await file.writeAsBytes(await client.storage.from(filesBucket).download(objectPath));
      } catch (_) {
        return null;
      }
    }
    return file.path;
  }

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
              // Filtered channels get no usable delete payload (Realtime
              // can't apply a filter or RLS to a deleted row). Deletes come
              // through the change log on the next pull (_pullChanges).
              return;
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
