/// Pre-construction records: approvals and clearances, and the time and
/// money spent chasing them. Every write is queued for the cloud in the
/// same transaction.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/execution/pre_construction_rules.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/sync/site_execution_sync.dart';

const _uuid = Uuid();

String? _clip(String? s, int max) {
  final v = s?.trim();
  if (v == null || v.isEmpty) return null;
  return v.length > max ? v.substring(0, max) : v;
}

class PreConstructionDao {
  PreConstructionDao(this.db);
  final AppDatabase db;

  Future<void> _queue(String serverTable, String op, DataClass row) => db.syncOutboxDao.enqueue(
        targetTable: serverTable,
        recordId: (row.toJson()['id']) as String,
        operation: op,
        payloadJson: jsonEncode(executionToRemote(serverTable, row)),
      );

  Future<List<SiteApproval>> approvalsFor(String projectId) => (db.select(db.siteApprovals)
        ..where((a) => a.projectId.equals(projectId))
        ..orderBy([(a) => OrderingTerm.asc(a.createdAt)]))
      .get();

  Future<SiteApproval?> approvalById(String id) =>
      (db.select(db.siteApprovals)..where((a) => a.id.equals(id))).getSingleOrNull();

  Future<List<LiaisonLog>> liaisonFor(String projectId) => (db.select(db.liaisonLogs)
        ..where((l) => l.projectId.equals(projectId))
        ..orderBy([(l) => OrderingTerm.desc(l.onDay), (l) => OrderingTerm.desc(l.createdAt)]))
      .get();

  Future<SiteApproval> addApproval({
    required String projectId,
    required String authority,
    required String title,
    required String by,
    String? referenceNo,
    String? expectedBy,
    String? liaisonBy,
    String waitingOn = 'us',
    DateTime? now,
  }) =>
      db.transaction(() async {
        final name = _clip(title, 200);
        if (name == null) throw ExecutionRefused(tr('Say which approval this is.'));
        if (!approvalAuthorities.contains(authority)) throw ArgumentError.value(authority, 'authority');
        final t = now ?? DateTime.now();
        final row = await db.into(db.siteApprovals).insertReturning(SiteApprovalsCompanion.insert(
              id: _uuid.v4(),
              projectId: projectId,
              title: name,
              raisedBy: by,
              authority: Value(authority),
              referenceNo: Value(_clip(referenceNo, 60)),
              expectedBy: Value(expectedBy),
              liaisonBy: Value(_clip(liaisonBy, 120)),
              waitingOn: Value(waitingOn),
              createdAt: Value(t),
              updatedAt: Value(t),
            ));
        await _queue('site_approvals', 'insert', row);
        return row;
      });

  /// Moves an approval to [status] with a note on what happened. Approving
  /// stamps the day; the change is added to the history.
  Future<SiteApproval> moveApproval(
    String id, {
    required String status,
    required String waitingOn,
    String? note,
    String? referenceNo,
    String? expectedBy,
    String? validUntil,
    DateTime? now,
  }) =>
      db.transaction(() async {
        if (!approvalStatuses.contains(status)) throw ArgumentError.value(status, 'status');
        if (!approvalWaitingOn.contains(waitingOn)) throw ArgumentError.value(waitingOn, 'waitingOn');
        final a = await approvalById(id);
        if (a == null) throw ExecutionRefused(tr('This approval is no longer on the phone.'));
        if (!approvalIsOpen(a)) throw ExecutionRefused(tr('This approval is closed.'));
        final t = now ?? DateTime.now();
        final clean = _clip(note, 300) ?? '';
        if ((status == 'query_raised' || status == 'rejected') && clean.isEmpty) {
          throw ExecutionRefused(tr('Write what the authority said.'));
        }
        final lines = [if (a.history.isNotEmpty) ...a.history.split('\n'), approvalHistoryLine(t, status, waitingOn, clean)];
        // Over the column's 8000 characters, the oldest lines go whole.
        while (lines.length > 1 && lines.join('\n').length > 8000) {
          lines.removeAt(0);
        }
        final day = ymdOf(t);
        await (db.update(db.siteApprovals)..where((r) => r.id.equals(id))).write(SiteApprovalsCompanion(
          status: Value(status),
          waitingOn: Value(status == 'approved' || status == 'rejected' ? 'us' : waitingOn),
          appliedOn: Value(a.appliedOn ?? (status == 'applied' || status == 'resubmitted' ? day : null)),
          approvedOn: Value(status == 'approved' ? day : a.approvedOn),
          referenceNo: Value(_clip(referenceNo, 60) ?? a.referenceNo),
          expectedBy: Value(expectedBy ?? a.expectedBy),
          validUntil: Value(validUntil ?? a.validUntil),
          note: Value(clean.isEmpty ? a.note : clean),
          history: Value(lines.join('\n')),
          updatedAt: Value(t),
        ));
        final row = (await approvalById(id))!;
        await _queue('site_approvals', 'update', row);
        return row;
      });

  /// Records time spent chasing an approval, and what it cost.
  Future<LiaisonLog> logLiaison({
    required String projectId,
    required String by,
    required int minutes,
    String? approvalId,
    String? person,
    double cost = 0,
    String? note,
    String? onDay,
    DateTime? now,
  }) =>
      db.transaction(() async {
        if (minutes <= 0 && cost <= 0) throw ExecutionRefused(tr('Enter the time spent or the cost.'));
        if (minutes < 0 || minutes > 24 * 60) throw ExecutionRefused(tr('That is more than a day. Enter the time for one visit.'));
        if (cost < 0) throw ExecutionRefused(tr('The cost cannot be negative.'));
        final t = now ?? DateTime.now();
        final row = await db.into(db.liaisonLogs).insertReturning(LiaisonLogsCompanion.insert(
              id: _uuid.v4(),
              projectId: projectId,
              onDay: onDay ?? ymdOf(t),
              loggedBy: by,
              approvalId: Value(approvalId),
              minutes: Value(minutes),
              person: Value(_clip(person, 120)),
              cost: Value(cost),
              note: Value(_clip(note, 300)),
              createdAt: Value(t),
              updatedAt: Value(t),
            ));
        await _queue('site_liaison_logs', 'insert', row);
        return row;
      });
}

String ymdOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
