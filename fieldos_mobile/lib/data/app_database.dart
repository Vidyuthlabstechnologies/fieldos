/// FieldOS Mobile SQLite database (drift) + data-access methods.
///
/// Offline-first: the whole database lives in the app's documents directory.
/// Nothing here touches the network.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/core/format.dart' show fmtQty;
import 'package:fieldos_mobile/features/attendance/staff_attendance.dart';
import 'package:fieldos_mobile/features/commercial/commercial_rules.dart';
import 'package:fieldos_mobile/features/crm/crm_rules.dart';
import 'package:fieldos_mobile/features/payroll/payroll_rules.dart';
import 'package:fieldos_mobile/features/procurement/quote_compare.dart' show awardNote, compareQuotes;
import 'package:fieldos_mobile/features/warehouse/tools_rules.dart';
import 'package:fieldos_mobile/features/warehouse/warehouse_rules.dart';
import 'package:fieldos_mobile/features/money/billing_calc.dart' show BillLine, encodeLines;
import 'package:fieldos_mobile/l10n/language.dart' show trf;
import 'package:fieldos_mobile/data/backup.dart';
import 'package:fieldos_mobile/sync/sync_mappers.dart';

import 'tables.dart';

part 'app_database.g.dart';

final _uuid = Uuid();

String? _clip(String? s, int max) {
  final v = s?.trim();
  if (v == null || v.isEmpty) return null;
  return v.length > max ? v.substring(0, max) : v;
}

@DriftDatabase(tables: [
  Users,
  Sessions,
  AppSettings,
  Companies,
  CompanyMembers,
  Projects,
  ProjectMembers,
  Tasks,
  DprEntries,
  DprPhotos,
  Issues,
  Estimations,
  CostHeads,
  MeasurementEntries,
  SteelEntries,
  Suppliers,
  PurchaseRequests,
  PurchaseOrders,
  MaterialReceipts,
  MaterialUsage,
  PaymentsReceived,
  ClientBills,
  SiteExpenses,
  LabourAttendance,
  AttendanceMarks,
  ExpenseAttachments,
  ProjectNotes,
  Subcontractors,
  WorkOrders,
  Approvals,
  ProjectGeofences,
  Equipment,
  EquipmentLogs,
  Inspections,
  InspectionItems,
  Documents,
  Workers,
  ProjectMessages,
  ReceiptAttachments,
  CloseReviews,
  CostCodes,
  WorkClaims,
  WorkCertifications,
  Variations,
  VariationDecisions,
  CommercialAttachments,
  ExceptionActions,
  CrmLeads,
  CrmActivities,
  CrmQuotes,
  Stores,
  StockMoves,
  Tools,
  ToolIssues,
  StaffMembers,
  StaffAdvances,
  PayrollLines,
  SupplierQuotes,
  SiteAccess,
  WorkMeasurements,
  WorkMeasurementDecisions,
  BillAllocations,
  SupplierInvoices,
  ApprovalRules,
  ApprovalSteps,
  SiteDayEvents,
  SiteCloseSettings,
  MemberSyncStatus,
  AttendancePhotos,
  StaffAttendance,
  CashMoves,
  SyncOutbox,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ??
            driftDatabase(
              name: 'fieldos',
              // Web options are required by the constructor but ignored on
              // native (Android/iOS/desktop) builds, which is where this app
              // runs.
              web: DriftWebOptions(
                sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                driftWorker: Uri.parse('drift_worker.js'),
              ),
              native: DriftNativeOptions(
                // Centralised under the app's documents dir, mirroring the
                // desktop app's app-data layout (fieldos/paths.py).
                databasePath: () async {
                  final path = await appDatabasePath();
                  // A restore checked earlier is swapped in before the
                  // database opens, never while it is open.
                  applyStagedRestore(path);
                  return path;
                },
              ),
            ));

  /// In-memory database for tests (no filesystem / path_provider needed).
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 36;

  // v3 shipped with no MigrationStrategy at all -- the default only creates
  // missing tables, never adds columns, so any additive change to an
  // existing table would crash on upgrade. v4 catches up both the suppliers
  // `vendors`-parity columns and the procurement alignment columns. v5 adds
  // a notes column to MaterialReceipts for GRN photo-evidence paths (see
  // photo_capture.dart -- stored as text until this table gets sync
  // consideration; MaterialReceipts stays mobile-only per
  // docs/MATERIALRECEIPTS_SYNC_ANALYSIS.md, so this is a local-only column,
  // no Postgres/RLS counterpart needed). v6 adds ProjectMessages (team
  // chat, synced). v7 syncs attendance, expenses and receipts through their
  // own site_* cloud tables (receipts are no longer local-only), and adds
  // MaterialUsage, PaymentsReceived and SiteExpenses.workerId. v8 adds
  // task progress, priority and start date (planning and the delay view).
  // v9 adds ClientBills (RA bills and GST invoices, synced). v10 is the
  // money book: paid-to, mode, GST, voucher numbers and edit/cancel trails
  // on expenses, and edit/cancel trails on payments received.
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 6) {
            await m.createTable(projectMessages);
          }
          if (from < 5) {
            await m.addColumn(materialReceipts, materialReceipts.notes);
          }
          if (from < 4) {
            await m.addColumn(suppliers, suppliers.contactPerson);
            await m.addColumn(suppliers, suppliers.address);
            await m.addColumn(suppliers, suppliers.gstNumber);
            await m.addColumn(suppliers, suppliers.category);
            await m.addColumn(suppliers, suppliers.notes);
            await m.addColumn(purchaseRequests, purchaseRequests.urgency);
            await m.addColumn(purchaseRequests, purchaseRequests.approvedBy);
            await m.addColumn(purchaseRequests, purchaseRequests.approvedAt);
            await m.addColumn(purchaseRequests, purchaseRequests.notes);
            // unit was nullable; Postgres requires it NOT NULL. Backfill
            // existing nulls with '' while rebuilding the table non-null.
            // TableMigration is drift's only supported way to change
            // nullability on SQLite (needs a table rebuild).
            // ignore: experimental_member_use
            await m.alterTable(TableMigration(
              purchaseRequests,
              columnTransformer: {purchaseRequests.unit: const Constant('')},
            ));
            await m.addColumn(purchaseOrders, purchaseOrders.poNumber);
            await m.addColumn(purchaseOrders, purchaseOrders.deliveryDate);
            await m.addColumn(purchaseOrders, purchaseOrders.quoteId);
            await m.addColumn(purchaseOrders, purchaseOrders.notes);
          }
          // Last, so every older step above has already shaped the tables it reads.
          if (from < 7) {
            // v7: site attendance, expenses and material receipts start
            // syncing (their own site_* cloud tables), plus material usage
            // and payments received. Rows written before the upgrade are
            // queued once so the cloud gets the site's history too.
            await m.createTable(materialUsage);
            await m.createTable(paymentsReceived);
            await m.addColumn(siteExpenses, siteExpenses.workerId);
            await _queueExistingSiteRecords();
          }
          if (from < 8) {
            await m.addColumn(tasks, tasks.progress);
            await m.addColumn(tasks, tasks.priority);
            await m.addColumn(tasks, tasks.startDate);
          }
          if (from < 9) {
            await m.createTable(clientBills);
          }
          if (from < 10) {
            for (final c in [
              siteExpenses.paidTo,
              siteExpenses.mode,
              siteExpenses.gstPct,
              siteExpenses.gstInterState,
              siteExpenses.voucherNo,
              siteExpenses.voided,
              siteExpenses.voidReason,
              siteExpenses.editedAt,
              siteExpenses.editedBy,
            ]) {
              await _addColumnIfMissing(m, siteExpenses, c);
            }
            for (final c in [
              paymentsReceived.voided,
              paymentsReceived.voidReason,
              paymentsReceived.editedAt,
              paymentsReceived.editedBy,
            ]) {
              await _addColumnIfMissing(m, paymentsReceived, c);
            }
            await _numberExistingVouchers();
          }
          if (from < 11) {
            await m.createTable(attendanceMarks);
          }
          if (from < 12) {
            for (final c in [
              equipment.hourlyRate,
              equipment.ownership,
              equipment.hiredFrom,
              equipment.hiredOn,
              equipment.returnDueOn,
              equipment.returnedOn,
            ]) {
              await _addColumnIfMissing(m, equipment, c);
            }
          }
          if (from < 13) {
            await _addColumnIfMissing(m, suppliers, suppliers.openingBalance);
          }
          if (from < 14) {
            await m.createTable(expenseAttachments);
            await m.createTable(projectNotes);
          }
          if (from < 15) {
            await m.createTable(receiptAttachments);
            await m.createTable(closeReviews);
            await _moveSlipPhotosOutOfNotes();
          }
          if (from < 16) {
            // Commercial controls: budget lines, claims, certificates,
            // variations and the exceptions inbox, plus the links from
            // work orders, POs and expenses to a budget line.
            for (final TableInfo t in [
              costCodes,
              workClaims,
              workCertifications,
              variations,
              variationDecisions,
              commercialAttachments,
              exceptionActions,
            ]) {
              await m.createTable(t);
            }
            for (final c in [workOrders.unit, workOrders.contractQty, workOrders.rate, workOrders.costCodeId]) {
              await _addColumnIfMissing(m, workOrders, c);
            }
            await _addColumnIfMissing(m, purchaseOrders, purchaseOrders.costCodeId);
            await _addColumnIfMissing(m, siteExpenses, siteExpenses.costCodeId);
          }
          // v16 is commercial controls (PR #122). Each step checks what is
          // there, so the two land in either order.
          if (from < 17) {
            await _addColumnIfMissing(m, projectMembers, projectMembers.approvalLimit);
            // SQLite can't add a column whose default is the current time;
            // existing rows take their created_at instead.
            final cols = await customSelect('PRAGMA table_info(project_members)').get();
            if (!cols.any((r) => r.read<String>('name') == 'updated_at')) {
              await customStatement('ALTER TABLE project_members ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0');
              await customStatement('UPDATE project_members SET updated_at = created_at');
            }
            await m.createTable(siteAccess);
          }
          if (from < 18) {
            await m.createTable(workMeasurements);
            await m.createTable(workMeasurementDecisions);
            await m.createTable(billAllocations);
            await m.createTable(supplierInvoices);
          }
          // v19 to v29 are other work's steps; v30 is approval rules.
          if (from < 30) {
            await _createTableIfMissing(m, approvalRules);
            await _createTableIfMissing(m, approvalSteps);
          }
          if (from < 31) {
            // Daily site close: the day's submission and what was said
            // about it, each site's cutoff and supervisors, and when each
            // teammate's phone last synced. (Built as v19, moved after
            // master's v30; it checks what is there, so a phone that
            // already has the tables keeps them.)
            for (final TableInfo t in [siteDayEvents, siteCloseSettings, memberSyncStatus]) {
              await _createTableIfMissing(m, t);
            }
          }
          if (from < 32) {
            // Beat Onsite (built as v21 to v24, moved after master's v31;
            // each part checks what is there, so a phone that already has
            // them keeps them): CRM leads, history and quotations; central
            // stores, transfers, tools and staff salaries; supplier quotes;
            // selfie and geofence attendance.
            for (final TableInfo t in [
              crmLeads,
              crmActivities,
              crmQuotes,
              stores,
              stockMoves,
              tools,
              toolIssues,
              staffMembers,
              staffAdvances,
              payrollLines,
              supplierQuotes,
              attendancePhotos,
              staffAttendance,
            ]) {
              await _createTableIfMissing(m, t);
            }
            for (final c in [labourAttendance.photoId, labourAttendance.distanceM, labourAttendance.accuracyM]) {
              await _addColumnIfMissing(m, labourAttendance, c);
            }
            await _addColumnIfMissing(m, staffMembers, staffMembers.userId);
            for (final c in [purchaseOrders.dispatchedOn, purchaseOrders.dispatchVehicle, purchaseOrders.supplierNote]) {
              await _addColumnIfMissing(m, purchaseOrders, c);
            }
          }
          // v33 to v35 are left for other work in flight.
          if (from < 36) {
            // The site cash book (imprest): cash given, returned, counted.
            await _createTableIfMissing(m, cashMoves);
          }
        },
      );

  /// Before v15 a delivery photo was kept as `Photo: <path>` in the
  /// receipt's note. Those become real slips, so they sync like new ones.
  Future<void> _moveSlipPhotosOutOfNotes() async {
    for (final r in await select(materialReceipts).get()) {
      final note = r.notes?.trim() ?? '';
      if (!note.startsWith('Photo: ')) continue;
      final path = note.substring('Photo: '.length).trim();
      if (path.isEmpty || !File(path).existsSync()) continue;
      await materialDao.attachSlip(r.id, path);
      await (update(materialReceipts)..where((m) => m.id.equals(r.id)))
          .write(const MaterialReceiptsCompanion(notes: Value(null)));
    }
  }

  /// A table made by an earlier step of this same upgrade (createTable
  /// uses today's columns) already has the column.
  Future<void> _createTableIfMissing(Migrator m, TableInfo t) async {
    final found = await customSelect("SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        variables: [Variable<String>(t.actualTableName)]).get();
    if (found.isEmpty) await m.createTable(t);
  }

  Future<void> _addColumnIfMissing(Migrator m, TableInfo table, GeneratedColumn column) async {
    final cols = await customSelect('PRAGMA table_info(${table.actualTableName})').get();
    if (cols.any((r) => r.read<String>('name') == column.name)) return;
    await m.addColumn(table, column);
  }

  /// Expenses written before v10 get voucher numbers in date order, per
  /// site, so the first printed voucher isn't number 1 of a busy site.
  /// Local only: the cloud learns each number with the row's next edit.
  Future<void> _numberExistingVouchers() async {
    final rows = await (select(siteExpenses)
          ..orderBy([(e) => OrderingTerm.asc(e.incurredOn), (e) => OrderingTerm.asc(e.createdAt)]))
        .get();
    final next = <String, int>{};
    for (final e in rows) {
      final n = (next[e.projectId] ?? 0) + 1;
      next[e.projectId] = n;
      await (update(siteExpenses)..where((x) => x.id.equals(e.id))).write(SiteExpensesCompanion(voucherNo: Value(n)));
    }
  }

  Future<void> _queueExistingSiteRecords() async {
    for (final a in await select(labourAttendance).get()) {
      await syncOutboxDao.enqueue(
          targetTable: 'site_attendance', recordId: a.id, operation: 'insert',
          payloadJson: jsonEncode(attendanceToSupabaseJson(a)));
    }
    for (final e in await select(siteExpenses).get()) {
      await syncOutboxDao.enqueue(
          targetTable: 'site_expenses', recordId: e.id, operation: 'insert',
          payloadJson: jsonEncode(siteExpenseToSupabaseJson(e)));
    }
    for (final r in await select(materialReceipts).get()) {
      await syncOutboxDao.enqueue(
          targetTable: 'site_material_receipts', recordId: r.id, operation: 'insert',
          payloadJson: jsonEncode(materialReceiptToSupabaseJson(r)));
    }
  }

  // --- DAO accessors ------------------------------------------------------
  UserDao get userDao => UserDao(this);
  SessionDao get sessionDao => SessionDao(this);
  SettingsDao get settingsDao => SettingsDao(this);
  CompanyDao get companyDao => CompanyDao(this);
  ProjectDao get projectDao => ProjectDao(this);
  TaskDao get taskDao => TaskDao(this);
  DprDao get dprDao => DprDao(this);
  IssueDao get issueDao => IssueDao(this);
  EstimationDao get estimationDao => EstimationDao(this);
  SupplierDao get supplierDao => SupplierDao(this);
  PurchaseDao get purchaseDao => PurchaseDao(this);
  MaterialDao get materialDao => MaterialDao(this);
  ExpenseDao get expenseDao => ExpenseDao(this);
  AttendanceDao get attendanceDao => AttendanceDao(this);
  GeofenceDao get geofenceDao => GeofenceDao(this);
  SubcontractorDao get subcontractorDao => SubcontractorDao(this);
  ExpenseDao get workOrderDao => ExpenseDao(this);
  ApprovalDao get approvalDao => ApprovalDao(this);
  EquipmentDao get equipmentDao => EquipmentDao(this);
  InspectionDao get inspectionDao => InspectionDao(this);
  DocumentDao get documentDao => DocumentDao(this);
  WorkerDao get workerDao => WorkerDao(this);
  SyncOutboxDao get syncOutboxDao => SyncOutboxDao(this);
  MessageDao get messageDao => MessageDao(this);
  PaymentDao get paymentDao => PaymentDao(this);
  BillDao get billDao => BillDao(this);
  NoteDao get noteDao => NoteDao(this);
  CloseDao get closeDao => CloseDao(this);
  CommercialDao get commercialDao => CommercialDao(this);
  CrmDao get crmDao => CrmDao(this);
  WarehouseDao get warehouseDao => WarehouseDao(this);
  PayrollDao get payrollDao => PayrollDao(this);
  SupplierQuoteDao get supplierQuoteDao => SupplierQuoteDao(this);
  StaffAttendanceDao get staffAttendanceDao => StaffAttendanceDao(this);
  SiteTeamDao get siteTeamDao => SiteTeamDao(this);
  BillingRecordsDao get billingRecordsDao => BillingRecordsDao(this);
  ApprovalChainDao get approvalChainDao => ApprovalChainDao(this);
  DayCloseDao get dayCloseDao => DayCloseDao(this);
  CashBookDao get cashBookDao => CashBookDao(this);

  static const filesQueuedKey = 'files_queued_for_sync_v1';

  /// DPR photos and expense bills used to stay on the phone that took them.
  /// The first time sync runs on a version that sends them, queue every one
  /// still on disk (once; a replay of one already sent is harmless, see
  /// SyncEngine.pushPending). Local-only (sample) records stay local.
  Future<int> queueFilesFromBeforeSync() async {
    if (await settingsDao.get(filesQueuedKey) != null) return 0;
    var queued = 0;
    await transaction(() async {
      for (final photo in await select(dprPhotos).get()) {
        final dpr = await dprDao.byId(photo.dprEntryId);
        if (dpr == null || !File(photo.photoPath).existsSync()) continue;
        await syncOutboxDao.enqueue(
          targetTable: 'dpr_photos',
          recordId: photo.id,
          operation: 'insert',
          payloadJson: jsonEncode(dprPhotoToSupabaseJson(photo, projectId: dpr.projectId)),
        );
        queued++;
      }
      for (final bill in await select(expenseAttachments).get()) {
        final expense = await expenseDao.byId(bill.expenseId);
        if (expense == null || !File(bill.filePath).existsSync()) continue;
        await syncOutboxDao.enqueue(
          targetTable: 'expense_attachments',
          recordId: bill.id,
          operation: 'insert',
          payloadJson: jsonEncode(expenseAttachmentToSupabaseJson(bill, projectId: expense.projectId)),
        );
        queued++;
      }
      await settingsDao.set(filesQueuedKey, DateTime.now().toUtc().toIso8601String());
    });
    return queued;
  }
}

/// The database file on the phone.
Future<String> appDatabasePath() async =>
    p.join((await getApplicationDocumentsDirectory()).path, 'fieldos.sqlite');

/// Where DPR photos and other local media are stored, relative to the app's
/// documents directory.
Future<Directory> localMediaDirectory() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(docs.path, 'media', 'dpr'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// Where project documents are stored, relative to the app's documents directory.
Future<Directory> localDocumentsDirectory() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(docs.path, 'media', 'documents'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

// ---------------------------------------------------------------------------
// Users
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [Users])
class UserDao extends DatabaseAccessor<AppDatabase> with _$UserDaoMixin {
  UserDao(super.db);

  Future<User?> byUsername(String username) =>
      (select(users)..where((u) => u.username.equals(username))).getSingleOrNull();

  /// "Ravi" and "ravi" are the same person: the first account whose name
  /// matches ignoring capitals.
  Future<User?> byUsernameIgnoringCase(String username) async {
    final rows = await (select(users)..where((u) => u.username.lower().equals(username.toLowerCase()))).get();
    return rows.isEmpty ? null : rows.first;
  }

  /// Whether anyone has made an account on this phone yet.
  Future<bool> any() async => (await (select(users)..limit(1)).get()).isNotEmpty;

  Future<User?> byId(String id) =>
      (select(users)..where((u) => u.id.equals(id))).getSingleOrNull();

  Future<void> create(UsersCompanion user) => into(users).insert(user);

  Future<void> setPasswordHash(String userId, String hash) =>
      (update(users)..where((u) => u.id.equals(userId))).write(UsersCompanion(passwordHash: Value(hash)));
}

// ---------------------------------------------------------------------------
// Sessions
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [Sessions])
class SessionDao extends DatabaseAccessor<AppDatabase> with _$SessionDaoMixin {
  SessionDao(super.db);

  Future<Session?> byToken(String token) =>
      (select(sessions)..where((s) => s.token.equals(token))).getSingleOrNull();

  Future<void> create(SessionsCompanion session) =>
      into(sessions).insert(session);

  Future<void> deleteByToken(String token) =>
      (delete(sessions)..where((s) => s.token.equals(token))).go();

  Future<void> setExpiry(String token, DateTime expiresAt) =>
      (update(sessions)..where((s) => s.token.equals(token))).write(SessionsCompanion(expiresAt: Value(expiresAt)));

  Future<void> deleteExpired() =>
      (delete(sessions)..where((s) => s.expiresAt.isSmallerThanValue(DateTime.now()))).go();
}

// ---------------------------------------------------------------------------
// App settings (e.g. the optional Sarvam API key)
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [AppSettings])
class SettingsDao extends DatabaseAccessor<AppDatabase> with _$SettingsDaoMixin {
  SettingsDao(super.db);

  Future<String?> get(String key) async {
    final row = await (select(appSettings)..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> set(String key, String value) => into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: key, value: value),
      );

  Future<void> remove(String key) => (delete(appSettings)..where((s) => s.key.equals(key))).go();
}

// ---------------------------------------------------------------------------
// Companies + membership
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [Companies, CompanyMembers])
class CompanyDao extends DatabaseAccessor<AppDatabase> with _$CompanyDaoMixin {
  CompanyDao(super.db);

  Future<Company> create(String name) {
    final id = _uuid.v4();
    final company = CompaniesCompanion.insert(
      id: id,
      name: name,
    );
    return transaction(() async {
      await into(companies).insert(company);
      return (await (select(companies)..where((c) => c.id.equals(id))).getSingle());
    });
  }

  /// A company that already exists on the server (joined with a code):
  /// stored under the server's id so pulled projects attach to it.
  Future<Company> ensureWithId(String id, String name) async {
    await into(companies).insert(CompaniesCompanion.insert(id: id, name: name), mode: InsertMode.insertOrIgnore);
    return (select(companies)..where((c) => c.id.equals(id))).getSingle();
  }

  /// All companies a user belongs to.
  Future<List<Company>> forUser(String userId) {
    final q = select(companies).join([
      innerJoin(companyMembers, companyMembers.companyId.equalsExp(companies.id)),
    ])
      ..where(companyMembers.userId.equals(userId));
    return q.map((row) => row.readTable(companies)).get();
  }

  Future<String?> roleOf(String companyId, String userId) async {
    final row = await (select(companyMembers)
          ..where((m) => m.companyId.equals(companyId) & m.userId.equals(userId)))
        .getSingleOrNull();
    return row?.role;
  }

  Future<void> addMember({
    required String companyId,
    required String userId,
    required String role,
  }) =>
      into(companyMembers).insertOnConflictUpdate(CompanyMembersCompanion.insert(
        id: _uuid.v4(),
        companyId: companyId,
        userId: userId,
        role: role,
      ));

  /// Insert-or-update by (company, user) -- addMember's upsert is keyed on
  /// the row id, so it throws on the (companyId, userId) unique key when
  /// the membership already exists.
  Future<void> upsertMemberRole({required String companyId, required String userId, required String role}) async {
    final updated = await (update(companyMembers)
          ..where((m) => m.companyId.equals(companyId) & m.userId.equals(userId)))
        .write(CompanyMembersCompanion(role: Value(role)));
    if (updated == 0) await addMember(companyId: companyId, userId: userId, role: role);
  }

  Future<List<CompanyMember>> members(String companyId) =>
      (select(companyMembers)..where((m) => m.companyId.equals(companyId))).get();
}

// ---------------------------------------------------------------------------
// Projects
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [Projects, ProjectMembers])
class ProjectDao extends DatabaseAccessor<AppDatabase> with _$ProjectDaoMixin {
  ProjectDao(super.db);

  /// Enqueues an outbox entry in the SAME transaction as the local write
  /// (the classic "transactional outbox" pattern) -- the two can never
  /// silently diverge, unlike a caller remembering to enqueue afterward.
  Future<Project> create(ProjectsCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(projects).insert(companion.copyWith(id: Value(id)));
      final row = await (select(projects)..where((p) => p.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'projects',
        recordId: row.id,
        operation: 'insert',
        payloadJson: jsonEncode(projectToSupabaseJson(row)),
      );
      return row;
    });
  }

  Future<List<Project>> forCompany(String companyId) =>
      (select(projects)..where((p) => p.companyId.equals(companyId))).get();

  /// Site location + geofence radius, synced to every phone in the company
  /// (attendance punch-in validates against it).
  Future<void> setLocation(String projectId, {required double lat, required double lng, required int radiusM}) {
    return transaction(() async {
      await (update(projects)..where((p) => p.id.equals(projectId))).write(ProjectsCompanion(
        locationLat: Value(lat),
        locationLng: Value(lng),
        geofenceRadiusM: Value(radiusM),
      ));
      final row = await (select(projects)..where((p) => p.id.equals(projectId))).getSingleOrNull();
      if (row == null) return;
      await db.syncOutboxDao.enqueue(
        targetTable: 'projects',
        recordId: row.id,
        operation: 'update',
        payloadJson: jsonEncode(projectToSupabaseJson(row)),
      );
    });
  }

  /// The geofence radius alone, for a site whose location isn't set yet
  /// (a new site made from a template).
  Future<void> setGeofenceRadius(String projectId, int radiusM) {
    if (radiusM <= 0) throw ArgumentError.value(radiusM, 'radiusM');
    return transaction(() async {
      await (update(projects)..where((p) => p.id.equals(projectId))).write(ProjectsCompanion(geofenceRadiusM: Value(radiusM)));
      final row = await (select(projects)..where((p) => p.id.equals(projectId))).getSingleOrNull();
      if (row == null) return;
      await db.syncOutboxDao.enqueue(
        targetTable: 'projects',
        recordId: row.id,
        operation: 'update',
        payloadJson: jsonEncode(projectToSupabaseJson(row)),
      );
    });
  }

  /// Moves a project to another stage (planning, active, on_hold or
  /// completed, the values the cloud accepts), synced like any edit.
  Future<void> setStatus(String projectId, String status) {
    if (!const {'planning', 'active', 'on_hold', 'completed'}.contains(status)) {
      throw ArgumentError.value(status, 'status');
    }
    return transaction(() async {
      await (update(projects)..where((p) => p.id.equals(projectId))).write(ProjectsCompanion(status: Value(status)));
      final row = await (select(projects)..where((p) => p.id.equals(projectId))).getSingleOrNull();
      if (row == null) return;
      await db.syncOutboxDao.enqueue(
        targetTable: 'projects',
        recordId: row.id,
        operation: 'update',
        payloadJson: jsonEncode(projectToSupabaseJson(row)),
      );
    });
  }

  Future<Project?> byId(String id) =>
      (select(projects)..where((p) => p.id.equals(id))).getSingleOrNull();

  /// Merges a row pulled from Supabase (see lib/sync/) into local storage --
  /// insert if new, overwrite if the id already exists. Server-wins for
  /// this reference-data table, matching docs/SUPABASE_SYNC_RESEARCH.md's
  /// conflict strategy.
  Future<void> upsertFromRemote(ProjectsCompanion companion) =>
      into(projects).insertOnConflictUpdate(companion);
}

// ---------------------------------------------------------------------------
// Tasks
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [Tasks, Projects])
class TaskDao extends DatabaseAccessor<AppDatabase> with _$TaskDaoMixin {
  TaskDao(super.db);

  Future<Task> create(TasksCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(tasks).insert(companion.copyWith(id: Value(id)));
      final row = await (select(tasks)..where((t) => t.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'tasks',
        recordId: row.id,
        operation: 'insert',
        payloadJson: jsonEncode(taskToSupabaseJson(row)),
      );
      return row;
    });
  }

  Future<List<Task>> forProject(String projectId) =>
      (select(tasks)..where((t) => t.projectId.equals(projectId))).get();

  /// Every task not yet done in the company's projects, for the late
  /// counts on the home screen.
  Future<List<Task>> openForCompany(String companyId) {
    final q = select(tasks).join([innerJoin(projects, projects.id.equalsExp(tasks.projectId))])
      ..where(projects.companyId.equals(companyId) & tasks.status.equals('done').not());
    return q.map((r) => r.readTable(tasks)).get();
  }

  Future<void> updateStatus(String id, String status) {
    // Done means 100%; reopening a finished task keeps what was logged.
    return edit(id, TasksCompanion(status: Value(status), progress: status == 'done' ? const Value(100) : const Value.absent()));
  }

  /// Progress from a daily report. Reaching 100 marks the task done, and
  /// any progress moves a to-do task to in progress.
  Future<void> setProgress(String id, int progress) async {
    final p = progress.clamp(0, 100);
    final row = await (select(tasks)..where((t) => t.id.equals(id))).getSingle();
    final status = p >= 100 ? 'done' : (p > 0 && row.status == 'todo' ? 'in_progress' : row.status);
    await edit(id, TasksCompanion(progress: Value(p), status: Value(status)));
  }

  /// Any change to a task, queued for sync like the others.
  Future<void> edit(String id, TasksCompanion changes) {
    return transaction(() async {
      await (update(tasks)..where((t) => t.id.equals(id))).write(changes.copyWith(updatedAt: Value(DateTime.now())));
      final row = await (select(tasks)..where((t) => t.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'tasks',
        recordId: row.id,
        operation: 'update',
        payloadJson: jsonEncode(taskToSupabaseJson(row)),
      );
    });
  }

  /// See ProjectDao.upsertFromRemote -- same server-wins merge pattern.
  Future<void> upsertFromRemote(TasksCompanion companion) =>
      into(tasks).insertOnConflictUpdate(companion);
}

// ---------------------------------------------------------------------------
// DPR
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [DprEntries, DprPhotos])
class DprDao extends DatabaseAccessor<AppDatabase> with _$DprDaoMixin {
  DprDao(super.db);

  Future<DprEntry> create(DprEntriesCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(dprEntries).insert(companion.copyWith(id: Value(id)));
      final row = await (select(dprEntries)..where((d) => d.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'dpr_entries',
        recordId: row.id,
        operation: 'insert',
        payloadJson: jsonEncode(dprEntryToSupabaseJson(row)),
      );
      return row;
    });
  }

  /// See ProjectDao.upsertFromRemote -- same server-wins merge pattern.
  Future<void> upsertFromRemote(DprEntriesCompanion companion) =>
      into(dprEntries).insertOnConflictUpdate(companion);

  Future<List<DprEntry>> forProject(String projectId) {
    return (select(dprEntries)..where((d) => d.projectId.equals(projectId))
          ..orderBy([(d) => OrderingTerm.desc(d.entryDate)]))
        .get();
  }

  Future<DprEntry?> byId(String id) =>
      (select(dprEntries)..where((d) => d.id.equals(id))).getSingleOrNull();

  /// Adds a photo to a report and queues it (file first, then the row) so
  /// the rest of the team sees it too.
  Future<DprPhoto> addPhoto(DprPhotosCompanion companion) => transaction(() async {
        final row = await into(dprPhotos).insertReturning(companion.copyWith(id: Value(_uuid.v4())));
        final dpr = await byId(row.dprEntryId);
        if (dpr != null) {
          await db.syncOutboxDao.enqueue(
            targetTable: 'dpr_photos',
            recordId: row.id,
            operation: 'insert',
            payloadJson: jsonEncode(dprPhotoToSupabaseJson(row, projectId: dpr.projectId)),
          );
        }
        return row;
      });

  /// A teammate's photo, already downloaded to [DprPhotosCompanion.photoPath].
  Future<void> upsertPhotoFromRemote(DprPhotosCompanion c) => into(dprPhotos).insertOnConflictUpdate(c);

  Future<DprPhoto?> photoById(String id) => (select(dprPhotos)..where((p) => p.id.equals(id))).getSingleOrNull();

  Future<List<DprPhoto>> photosFor(String dprEntryId) =>
      (select(dprPhotos)..where((p) => p.dprEntryId.equals(dprEntryId))).get();

  /// Takes a photo off its report, for the whole team, and deletes the
  /// file from the phone.
  Future<void> deletePhoto(String id) async {
    final row = await (select(dprPhotos)..where((p) => p.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    await transaction(() async {
      await (delete(dprPhotos)..where((p) => p.id.equals(id))).go();
      final dpr = await byId(row.dprEntryId);
      if (dpr != null) {
        await db.syncOutboxDao.enqueue(
          targetTable: 'dpr_photos',
          recordId: row.id,
          operation: 'delete',
          payloadJson: jsonEncode({'id': row.id, 'photo_path': dprPhotoStoragePath(dpr.projectId, row)}),
        );
      }
    });
    await _deleteFileQuietly(row.photoPath);
  }
}

// ---------------------------------------------------------------------------
// Issues
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [Issues])
class IssueDao extends DatabaseAccessor<AppDatabase> with _$IssueDaoMixin {
  IssueDao(super.db);

  Future<Issue> create(IssuesCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(issues).insert(companion.copyWith(id: Value(id)));
      final row = await (select(issues)..where((i) => i.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'issues',
        recordId: row.id,
        operation: 'insert',
        payloadJson: jsonEncode(issueToSupabaseJson(row)),
      );
      return row;
    });
  }

  Future<List<Issue>> forProject(String projectId) =>
      (select(issues)..where((i) => i.projectId.equals(projectId))).get();

  Future<void> resolve(String id) {
    return transaction(() async {
      await (update(issues)..where((i) => i.id.equals(id))).write(IssuesCompanion(
        status: const Value('resolved'),
        resolvedAt: Value(DateTime.now()),
      ));
      final row = await (select(issues)..where((i) => i.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'issues',
        recordId: row.id,
        operation: 'update',
        payloadJson: jsonEncode(issueToSupabaseJson(row)),
      );
    });
  }

  /// See ProjectDao.upsertFromRemote -- same server-wins merge pattern.
  Future<void> upsertFromRemote(IssuesCompanion companion) =>
      into(issues).insertOnConflictUpdate(companion);
}

// ---------------------------------------------------------------------------
// Estimations + BOQ line items
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [Estimations, CostHeads, MeasurementEntries, SteelEntries])
class EstimationDao extends DatabaseAccessor<AppDatabase> with _$EstimationDaoMixin {
  EstimationDao(super.db);

  Future<Estimation> create(EstimationsCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(estimations).insert(companion.copyWith(id: Value(id)));
      final row = await (select(estimations)..where((e) => e.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'estimations',
        recordId: row.id,
        operation: 'insert',
        payloadJson: jsonEncode(estimationToSupabaseJson(row)),
      );
      return row;
    });
  }

  Future<List<Estimation>> forProject(String projectId) =>
      (select(estimations)..where((e) => e.projectId.equals(projectId))).get();

  /// See ProjectDao.upsertFromRemote -- same server-wins merge pattern.
  Future<void> upsertFromRemote(EstimationsCompanion companion) =>
      into(estimations).insertOnConflictUpdate(companion);

  Future<CostHead> addCostHead(CostHeadsCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(costHeads).insert(companion.copyWith(id: Value(id)));
      final row = await (select(costHeads)..where((c) => c.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'cost_heads',
        recordId: row.id,
        operation: 'insert',
        payloadJson: jsonEncode(costHeadToSupabaseJson(row)),
      );
      return row;
    });
  }

  Future<void> upsertFromRemoteCostHead(CostHeadsCompanion companion) =>
      into(costHeads).insertOnConflictUpdate(companion);

  Future<void> addMeasurement(MeasurementEntriesCompanion companion) {
    return transaction(() async {
      final id = companion.id.present ? companion.id.value : _uuid.v4();
      await into(measurementEntries).insert(companion.copyWith(id: Value(id)));
      final row = await (select(measurementEntries)..where((m) => m.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'measurement_entries',
        recordId: row.id,
        operation: 'insert',
        payloadJson: jsonEncode(measurementEntryToSupabaseJson(row)),
      );
    });
  }

  Future<void> upsertFromRemoteMeasurement(MeasurementEntriesCompanion companion) =>
      into(measurementEntries).insertOnConflictUpdate(companion);

  Future<void> addSteel(SteelEntriesCompanion companion) {
    return transaction(() async {
      final id = companion.id.present ? companion.id.value : _uuid.v4();
      await into(steelEntries).insert(companion.copyWith(id: Value(id)));
      final row = await (select(steelEntries)..where((s) => s.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'steel_entries',
        recordId: row.id,
        operation: 'insert',
        payloadJson: jsonEncode(steelEntryToSupabaseJson(row)),
      );
    });
  }

  Future<void> upsertFromRemoteSteel(SteelEntriesCompanion companion) =>
      into(steelEntries).insertOnConflictUpdate(companion);

  Future<List<CostHead>> costHeadsFor(String estimationId) {
    return (select(costHeads)
          ..where((c) => c.estimationId.equals(estimationId))
          ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
        .get();
  }

  Future<List<MeasurementEntry>> measurements(String costHeadId) =>
      (select(measurementEntries)..where((m) => m.costHeadId.equals(costHeadId))).get();

  Future<List<SteelEntry>> steel(String costHeadId) =>
      (select(steelEntries)..where((s) => s.costHeadId.equals(costHeadId))).get();
}

// ---------------------------------------------------------------------------
// Suppliers + subcontractors
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [Suppliers])
class SupplierDao extends DatabaseAccessor<AppDatabase> with _$SupplierDaoMixin {
  SupplierDao(super.db);

  Future<Supplier> create(SuppliersCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(suppliers).insert(companion.copyWith(id: Value(id)));
      final row = await (select(suppliers)..where((s) => s.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'vendors',
        recordId: row.id,
        operation: 'insert',
        payloadJson: jsonEncode(supplierToSupabaseJson(row)),
      );
      return row;
    });
  }

  Future<List<Supplier>> forCompany(String companyId) =>
      (select(suppliers)..where((s) => s.companyId.equals(companyId))).get();

  /// Changes a supplier's details (the cloud lets owners and project
  /// managers do this). It stays with its company.
  Future<Supplier> edit(String id, SuppliersCompanion changes) {
    return transaction(() async {
      await (update(suppliers)..where((s) => s.id.equals(id))).write(changes.copyWith(
        id: const Value.absent(),
        companyId: const Value.absent(),
        createdAt: const Value.absent(),
      ));
      final row = await (select(suppliers)..where((s) => s.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'vendors',
        recordId: row.id,
        operation: 'update',
        payloadJson: jsonEncode(supplierToSupabaseJson(row)),
      );
      return row;
    });
  }

  /// See ProjectDao.upsertFromRemote -- same server-wins merge pattern.
  Future<void> upsertFromRemote(SuppliersCompanion companion) =>
      into(suppliers).insertOnConflictUpdate(companion);
}

@DriftAccessor(tables: [Subcontractors])
class SubcontractorDao extends DatabaseAccessor<AppDatabase> with _$SubcontractorDaoMixin {
  SubcontractorDao(super.db);

  Future<Subcontractor> create(SubcontractorsCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(subcontractors).insert(companion.copyWith(id: Value(id)));
      final row = await (select(subcontractors)..where((s) => s.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'subcontractors',
        recordId: row.id,
        operation: 'insert',
        payloadJson: jsonEncode(subcontractorToSupabaseJson(row)),
      );
      return row;
    });
  }

  Future<List<Subcontractor>> forCompany(String companyId) =>
      (select(subcontractors)..where((s) => s.companyId.equals(companyId))).get();

  /// See ProjectDao.upsertFromRemote -- same server-wins merge pattern.
  Future<void> upsertFromRemote(SubcontractorsCompanion companion) =>
      into(subcontractors).insertOnConflictUpdate(companion);
}

// ---------------------------------------------------------------------------
// Procurement: RFQ -> PO -> GRN
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [PurchaseRequests, PurchaseOrders])
class PurchaseDao extends DatabaseAccessor<AppDatabase> with _$PurchaseDaoMixin {
  PurchaseDao(super.db);

  Future<PurchaseRequest> createRequest(PurchaseRequestsCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(purchaseRequests).insert(companion.copyWith(id: Value(id)));
      final row = await (select(purchaseRequests)..where((r) => r.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'purchase_requisitions',
        recordId: row.id,
        operation: 'insert',
        payloadJson: jsonEncode(purchaseRequestToSupabaseJson(row)),
      );
      return row;
    });
  }

  Future<PurchaseOrder> createOrder(PurchaseOrdersCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(purchaseOrders).insert(companion.copyWith(id: Value(id)));
      final row = await (select(purchaseOrders)..where((o) => o.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'purchase_orders',
        recordId: row.id,
        operation: 'insert',
        payloadJson: jsonEncode(purchaseOrderToSupabaseJson(row)),
      );
      return row;
    });
  }

  Future<List<PurchaseRequest>> requestsFor(String projectId) =>
      (select(purchaseRequests)..where((r) => r.projectId.equals(projectId))).get();

  Future<List<PurchaseOrder>> ordersFor(String projectId) =>
      (select(purchaseOrders)..where((o) => o.projectId.equals(projectId))).get();

  Future<void> setRequestStatus(String id, String status) =>
      transaction(() async {
        await (update(purchaseRequests)..where((r) => r.id.equals(id)))
            .write(PurchaseRequestsCompanion(status: Value(status)));
        final row = await (select(purchaseRequests)..where((r) => r.id.equals(id))).getSingle();
        await db.syncOutboxDao.enqueue(
          targetTable: 'purchase_requisitions',
          recordId: row.id,
          operation: 'update',
          payloadJson: jsonEncode(purchaseRequestToSupabaseJson(row)),
        );
      });

  Future<void> setOrderStatus(String id, String status) =>
      transaction(() async {
        await (update(purchaseOrders)..where((o) => o.id.equals(id)))
            .write(PurchaseOrdersCompanion(status: Value(status)));
        final row = await (select(purchaseOrders)..where((o) => o.id.equals(id))).getSingle();
        await db.syncOutboxDao.enqueue(
          targetTable: 'purchase_orders',
          recordId: row.id,
          operation: 'update',
          payloadJson: jsonEncode(purchaseOrderToSupabaseJson(row)),
        );
      });

  /// Raises a PO for a request and marks the request ordered, as one step
  /// (audit P1, 2026-11-10). These used to be two writes from the screen,
  /// so a crash or a killed app between them left an order whose request
  /// still said "Waiting for a PO" and could be ordered twice. A second tap
  /// (or a retry after an interruption) returns the order already made.
  Future<PurchaseOrder> orderFromRequest(String requestId, PurchaseOrdersCompanion order) => transaction(() async {
        final existing = await (select(purchaseOrders)
              ..where((o) => o.requestId.equals(requestId) & o.status.isNotValue('cancelled')))
            .get();
        if (existing.isNotEmpty) {
          final request = await (select(purchaseRequests)..where((r) => r.id.equals(requestId))).getSingleOrNull();
          if (request != null && request.status != 'ordered') await setRequestStatus(requestId, 'ordered');
          return existing.first;
        }
        final row = await createOrder(order.copyWith(requestId: Value(requestId)));
        await setRequestStatus(requestId, 'ordered');
        return row;
      });

  /// Records goods received against an order and, when everything has come,
  /// closes it, as one step (audit P1): a receipt without its closure left
  /// a delivered order showing as still due. Idempotent on the receipt id,
  /// so a repeated submit doesn't count the delivery twice.
  /// [slipPath]: the delivery slip photo, kept with the receipt in the
  /// same step so a receipt never syncs without the slip it was taken with.
  Future<MaterialReceipt> receiveAgainstOrder(String orderId, MaterialReceiptsCompanion receipt,
          {required bool closeOrder, String? slipPath}) =>
      transaction(() async {
        final id = receipt.id.present ? receipt.id.value : _uuid.v4();
        final already = await (select(db.materialReceipts)..where((m) => m.id.equals(id))).getSingleOrNull();
        final row = already ?? await db.materialDao.createReceipt(receipt.copyWith(id: Value(id), poId: Value(orderId)));
        if (already == null && slipPath != null) await db.materialDao.attachSlip(row.id, slipPath);
        if (closeOrder) {
          final order = await (select(purchaseOrders)..where((o) => o.id.equals(orderId))).getSingleOrNull();
          if (order != null && order.status != 'delivered') await setOrderStatus(orderId, 'delivered');
        }
        return row;
      });

  /// See ProjectDao.upsertFromRemote -- same server-wins merge pattern.
  Future<void> upsertFromRemoteRequest(PurchaseRequestsCompanion companion) =>
      into(purchaseRequests).insertOnConflictUpdate(companion);

  Future<void> upsertFromRemoteOrder(PurchaseOrdersCompanion companion) =>
      into(purchaseOrders).insertOnConflictUpdate(companion);
}

@DriftAccessor(tables: [MaterialReceipts, MaterialUsage, ReceiptAttachments])
class MaterialDao extends DatabaseAccessor<AppDatabase> with _$MaterialDaoMixin {
  MaterialDao(super.db);

  Future<MaterialReceipt> createReceipt(MaterialReceiptsCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(materialReceipts).insert(companion.copyWith(id: Value(id)));
      final row = await (select(materialReceipts)..where((m) => m.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'site_material_receipts',
        recordId: row.id,
        operation: 'insert',
        payloadJson: jsonEncode(materialReceiptToSupabaseJson(row)),
      );
      return row;
    });
  }

  Future<List<MaterialReceipt>> forProject(String projectId) =>
      (select(materialReceipts)..where((m) => m.projectId.equals(projectId))).get();

  Future<MaterialUsageData> recordUsage(MaterialUsageCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(materialUsage).insert(companion.copyWith(id: Value(id)));
      final row = await (select(materialUsage)..where((m) => m.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'site_material_usage',
        recordId: row.id,
        operation: 'insert',
        payloadJson: jsonEncode(materialUsageToSupabaseJson(row)),
      );
      return row;
    });
  }

  Future<List<MaterialUsageData>> usageForProject(String projectId) =>
      (select(materialUsage)..where((m) => m.projectId.equals(projectId))).get();

  Future<void> upsertReceiptFromRemote(MaterialReceiptsCompanion c) => into(materialReceipts).insertOnConflictUpdate(c);

  Future<MaterialReceipt?> receiptById(String id) =>
      (select(materialReceipts)..where((m) => m.id.equals(id))).getSingleOrNull();

  /// Keeps the delivery slip photo with a receipt and queues it (file
  /// first, then the row) so the manager approving it sees the slip.
  Future<ReceiptAttachment> attachSlip(String receiptId, String filePath, {String? mimeType}) => transaction(() async {
        final row = await into(receiptAttachments).insertReturning(ReceiptAttachmentsCompanion.insert(
          id: _uuid.v4(),
          receiptId: receiptId,
          filePath: filePath,
          mimeType: mimeType ?? attachmentMimeType(filePath),
        ));
        final receipt = await receiptById(receiptId);
        if (receipt != null) {
          await db.syncOutboxDao.enqueue(
            targetTable: 'site_receipt_attachments',
            recordId: row.id,
            operation: 'insert',
            payloadJson: jsonEncode(receiptAttachmentToSupabaseJson(row, projectId: receipt.projectId)),
          );
        }
        return row;
      });

  Future<ReceiptAttachment?> slipById(String id) =>
      (select(receiptAttachments)..where((a) => a.id.equals(id))).getSingleOrNull();

  Future<List<ReceiptAttachment>> slipsFor(String receiptId) => (select(receiptAttachments)
        ..where((a) => a.receiptId.equals(receiptId))
        ..orderBy([(a) => OrderingTerm.asc(a.createdAt)]))
      .get();

  /// Every slip of the site's receipts, by receipt id.
  Future<Map<String, List<ReceiptAttachment>>> slipsForProject(String projectId) async {
    final rows = await (select(receiptAttachments).join(
            [innerJoin(materialReceipts, materialReceipts.id.equalsExp(receiptAttachments.receiptId))])
          ..where(materialReceipts.projectId.equals(projectId))
          ..orderBy([OrderingTerm.asc(receiptAttachments.createdAt)]))
        .get();
    final out = <String, List<ReceiptAttachment>>{};
    for (final r in rows) {
      final a = r.readTable(receiptAttachments);
      (out[a.receiptId] ??= []).add(a);
    }
    return out;
  }

  Future<void> upsertSlipFromRemote(ReceiptAttachmentsCompanion c) => into(receiptAttachments).insertOnConflictUpdate(c);
  Future<void> upsertUsageFromRemote(MaterialUsageCompanion c) => into(materialUsage).insertOnConflictUpdate(c);
}

@DriftAccessor(tables: [PaymentsReceived])
class PaymentDao extends DatabaseAccessor<AppDatabase> with _$PaymentDaoMixin {
  PaymentDao(super.db);

  Future<PaymentsReceivedData> create(PaymentsReceivedCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(paymentsReceived).insert(companion.copyWith(id: Value(id)));
      final row = await (select(paymentsReceived)..where((p) => p.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'site_payments_received',
        recordId: row.id,
        operation: 'insert',
        payloadJson: jsonEncode(paymentReceivedToSupabaseJson(row)),
      );
      return row;
    });
  }

  /// Payments that count: cancelled ones are left out of every total.
  Future<List<PaymentsReceivedData>> forProject(String projectId) => (select(paymentsReceived)
        ..where((p) => p.projectId.equals(projectId) & p.voided.equals(false))
        ..orderBy([(p) => OrderingTerm.desc(p.receivedOn)]))
      .get();

  /// Every payment of the site, cancelled ones too, for the money book.
  Future<List<PaymentsReceivedData>> allForProject(String projectId) => (select(paymentsReceived)
        ..where((p) => p.projectId.equals(projectId))
        ..orderBy([(p) => OrderingTerm.desc(p.receivedOn)]))
      .get();

  Future<PaymentsReceivedData> edit(String id, PaymentsReceivedCompanion changes, {required String by, DateTime? now}) {
    return transaction(() async {
      await (update(paymentsReceived)..where((p) => p.id.equals(id))).write(changes.copyWith(
        id: const Value.absent(),
        projectId: const Value.absent(),
        recordedBy: const Value.absent(),
        createdAt: const Value.absent(),
        editedAt: Value(now ?? DateTime.now()),
        editedBy: Value(by),
      ));
      return _queueUpdate(id);
    });
  }

  Future<PaymentsReceivedData> setVoided(String id,
      {required bool voided, String? reason, required String by, DateTime? now}) {
    return transaction(() async {
      await (update(paymentsReceived)..where((p) => p.id.equals(id))).write(PaymentsReceivedCompanion(
        voided: Value(voided),
        voidReason: Value(voided ? _clip(reason, 200) : null),
        editedAt: Value(now ?? DateTime.now()),
        editedBy: Value(by),
      ));
      return _queueUpdate(id);
    });
  }

  Future<PaymentsReceivedData> _queueUpdate(String id) async {
    final row = await (select(paymentsReceived)..where((p) => p.id.equals(id))).getSingle();
    await db.syncOutboxDao.enqueue(
      targetTable: 'site_payments_received',
      recordId: row.id,
      operation: 'update',
      payloadJson: jsonEncode(paymentReceivedToSupabaseJson(row)),
    );
    return row;
  }

  Future<void> upsertFromRemote(PaymentsReceivedCompanion c) => into(paymentsReceived).insertOnConflictUpdate(c);
}

@DriftAccessor(tables: [ClientBills])
class BillDao extends DatabaseAccessor<AppDatabase> with _$BillDaoMixin {
  BillDao(super.db);

  Future<ClientBill> create(ClientBillsCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(clientBills).insert(companion.copyWith(id: Value(id)));
      final row = await (select(clientBills)..where((b) => b.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'site_client_bills',
        recordId: row.id,
        operation: 'insert',
        payloadJson: jsonEncode(clientBillToSupabaseJson(row)),
      );
      return row;
    });
  }

  /// Newest first.
  Future<List<ClientBill>> forProject(String projectId) => (select(clientBills)
        ..where((b) => b.projectId.equals(projectId))
        ..orderBy([(b) => OrderingTerm.desc(b.billDate), (b) => OrderingTerm.desc(b.createdAt)]))
      .get();

  Future<void> setStatus(String id, String status) {
    return transaction(() async {
      await (update(clientBills)..where((b) => b.id.equals(id))).write(ClientBillsCompanion(status: Value(status)));
      final row = await (select(clientBills)..where((b) => b.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'site_client_bills',
        recordId: row.id,
        operation: 'update',
        payloadJson: jsonEncode(clientBillToSupabaseJson(row)),
      );
    });
  }

  Future<void> upsertFromRemote(ClientBillsCompanion c) => into(clientBills).insertOnConflictUpdate(c);
}

// ---------------------------------------------------------------------------
// Finance actuals (expenses + work-order billing)
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [SiteExpenses, WorkOrders, ExpenseAttachments])
class ExpenseDao extends DatabaseAccessor<AppDatabase> with _$ExpenseDaoMixin {
  ExpenseDao(super.db);

  Future<SiteExpense> create(SiteExpensesCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      final voucher = companion.voucherNo.present && companion.voucherNo.value != null
          ? companion.voucherNo
          : Value(await nextVoucherNo(companion.projectId.value));
      await into(siteExpenses).insert(companion.copyWith(id: Value(id), voucherNo: voucher));
      final row = await (select(siteExpenses)..where((e) => e.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'site_expenses',
        recordId: row.id,
        operation: 'insert',
        payloadJson: jsonEncode(siteExpenseToSupabaseJson(row)),
      );
      return row;
    });
  }

  /// The site's expenses that count: cancelled ones are left out, so every
  /// total (wage sheet, reports, budget, dashboard) ignores them.
  Future<List<SiteExpense>> forProject(String projectId) =>
      (select(siteExpenses)..where((e) => e.projectId.equals(projectId) & e.voided.equals(false))).get();

  /// Every expense of the site, cancelled ones too, for the money book.
  Future<List<SiteExpense>> allForProject(String projectId) =>
      (select(siteExpenses)..where((e) => e.projectId.equals(projectId))).get();

  Future<SiteExpense?> byId(String id) => (select(siteExpenses)..where((e) => e.id.equals(id))).getSingleOrNull();

  /// One more than the highest voucher number this phone knows for the
  /// site (its own entries and everything synced from the team). On a
  /// phone linked to the cloud this is only provisional: the server gives
  /// the final number when the expense reaches it
  /// (20261110000000_server_voucher_numbers.sql), because two phones
  /// offline on one site would otherwise both issue the same number.
  Future<int> nextVoucherNo(String projectId) async {
    final max = siteExpenses.voucherNo.max();
    final row = await (selectOnly(siteExpenses)
          ..addColumns([max])
          ..where(siteExpenses.projectId.equals(projectId)))
        .getSingle();
    return (row.read(max) ?? 0) + 1;
  }

  /// Corrects an entry. The voucher number, site and who first wrote it
  /// stay; who changed it and when are kept on the row.
  /// Expenses of the site whose insert is still waiting in the outbox:
  /// their voucher number is this phone's guess until the server answers.
  Future<Set<String>> provisionalVoucherIds(String projectId) async {
    final rows = await (select(db.syncOutbox).join([
      innerJoin(siteExpenses, siteExpenses.id.equalsExp(db.syncOutbox.recordId)),
    ])
          ..where(db.syncOutbox.targetTable.equals('site_expenses') &
              db.syncOutbox.operation.equals('insert') &
              siteExpenses.projectId.equals(projectId)))
        .get();
    return {for (final r in rows) r.readTable(siteExpenses).id};
  }

  /// The final number the server gave an expense. Not queued: it came from
  /// the server.
  Future<void> setServerVoucher(String id, int voucherNo) =>
      (update(siteExpenses)..where((e) => e.id.equals(id))).write(SiteExpensesCompanion(voucherNo: Value(voucherNo)));

  Future<SiteExpense> edit(String id, SiteExpensesCompanion changes, {required String by, DateTime? now}) {
    return transaction(() async {
      await (update(siteExpenses)..where((e) => e.id.equals(id))).write(changes.copyWith(
        id: const Value.absent(),
        projectId: const Value.absent(),
        recordedBy: const Value.absent(),
        voucherNo: const Value.absent(),
        createdAt: const Value.absent(),
        editedAt: Value(now ?? DateTime.now()),
        editedBy: Value(by),
      ));
      return _queueUpdate(id);
    });
  }

  /// Cancels an entry: it stays in the book, struck through with [reason],
  /// and counts in no total. [undo] brings it back.
  Future<SiteExpense> setVoided(String id, {required bool voided, String? reason, required String by, DateTime? now}) {
    return transaction(() async {
      await (update(siteExpenses)..where((e) => e.id.equals(id))).write(SiteExpensesCompanion(
        voided: Value(voided),
        voidReason: Value(voided ? _clip(reason, 200) : null),
        editedAt: Value(now ?? DateTime.now()),
        editedBy: Value(by),
      ));
      return _queueUpdate(id);
    });
  }

  Future<SiteExpense> _queueUpdate(String id) async {
    final row = await (select(siteExpenses)..where((e) => e.id.equals(id))).getSingle();
    await db.syncOutboxDao.enqueue(
      targetTable: 'site_expenses',
      recordId: row.id,
      operation: 'update',
      payloadJson: jsonEncode(siteExpenseToSupabaseJson(row)),
    );
    return row;
  }

  Future<void> upsertFromRemote(SiteExpensesCompanion c) => into(siteExpenses).insertOnConflictUpdate(c);

  /// Keeps a bill photo or PDF with an expense, and queues it (file first,
  /// then the row) so the office and the rest of the team can open it.
  Future<ExpenseAttachment> attach(String expenseId, String filePath, {String? mimeType}) => transaction(() async {
        final row = await into(expenseAttachments).insertReturning(ExpenseAttachmentsCompanion.insert(
          id: _uuid.v4(),
          expenseId: expenseId,
          filePath: filePath,
          mimeType: mimeType ?? attachmentMimeType(filePath),
        ));
        final expense = await byId(expenseId);
        if (expense != null) {
          await db.syncOutboxDao.enqueue(
            targetTable: 'expense_attachments',
            recordId: row.id,
            operation: 'insert',
            payloadJson: jsonEncode(expenseAttachmentToSupabaseJson(row, projectId: expense.projectId)),
          );
        }
        return row;
      });

  Future<void> upsertAttachmentFromRemote(ExpenseAttachmentsCompanion c) =>
      into(expenseAttachments).insertOnConflictUpdate(c);

  Future<ExpenseAttachment?> attachmentById(String id) =>
      (select(expenseAttachments)..where((a) => a.id.equals(id))).getSingleOrNull();

  Future<List<ExpenseAttachment>> attachmentsFor(String expenseId) => (select(expenseAttachments)
        ..where((a) => a.expenseId.equals(expenseId))
        ..orderBy([(a) => OrderingTerm.asc(a.createdAt)]))
      .get();

  /// How many bills each of the site's expenses has, for the paperclip on
  /// the money book's lines.
  Future<Map<String, int>> attachmentCounts(String projectId) async {
    final count = expenseAttachments.id.count();
    final rows = await (selectOnly(expenseAttachments)
          ..join([innerJoin(siteExpenses, siteExpenses.id.equalsExp(expenseAttachments.expenseId))])
          ..addColumns([expenseAttachments.expenseId, count])
          ..where(siteExpenses.projectId.equals(projectId))
          ..groupBy([expenseAttachments.expenseId]))
        .get();
    return {for (final r in rows) r.read(expenseAttachments.expenseId)!: r.read(count) ?? 0};
  }

  /// Takes the bill off the expense, for the whole team, and deletes its
  /// file from the phone.
  Future<void> removeAttachment(String id) async {
    final row = await (select(expenseAttachments)..where((a) => a.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    await transaction(() async {
      await (delete(expenseAttachments)..where((a) => a.id.equals(id))).go();
      final expense = await byId(row.expenseId);
      if (expense != null) {
        await db.syncOutboxDao.enqueue(
          targetTable: 'expense_attachments',
          recordId: row.id,
          operation: 'delete',
          payloadJson: jsonEncode({'id': row.id, 'file_path': expenseBillStoragePath(expense.projectId, row)}),
        );
      }
    });
    await _deleteFileQuietly(row.filePath);
  }

  Future<WorkOrder> createWorkOrder(WorkOrdersCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(workOrders).insert(companion.copyWith(id: Value(id)));
      final row = await (select(workOrders)..where((w) => w.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'work_orders',
        recordId: row.id,
        operation: 'insert',
        payloadJson: jsonEncode(workOrderToSupabaseJson(row)),
      );
      return row;
    });
  }

  Future<List<WorkOrder>> workOrdersFor(String projectId) =>
      (select(workOrders)..where((w) => w.projectId.equals(projectId))).get();

  Future<void> billWorkOrder(String id, double additional) {
    return transaction(() async {
      await (update(workOrders)..where((w) => w.id.equals(id)))
          .write(WorkOrdersCompanion(billedAmount: Value(additional)));
      final row = await (select(workOrders)..where((w) => w.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'work_orders',
        recordId: row.id,
        operation: 'update',
        payloadJson: jsonEncode(workOrderToSupabaseJson(row)),
      );
    });
  }

  /// See ProjectDao.upsertFromRemote -- same server-wins merge pattern.
  Future<void> upsertFromRemoteWorkOrder(WorkOrdersCompanion companion) =>
      into(workOrders).insertOnConflictUpdate(companion);
}

// ---------------------------------------------------------------------------
// Labour attendance (GPS)
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [LabourAttendance, AttendanceMarks])
class AttendanceDao extends DatabaseAccessor<AppDatabase> with _$AttendanceDaoMixin {
  AttendanceDao(super.db);

  Future<LabourAttendanceData> punchIn(LabourAttendanceCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(labourAttendance).insert(companion.copyWith(id: Value(id)));
      final row = await (select(labourAttendance)..where((a) => a.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'site_attendance',
        recordId: row.id,
        operation: 'insert',
        payloadJson: jsonEncode(attendanceToSupabaseJson(row)),
      );
      return row;
    });
  }

  /// Closes a punch now, or at [at] for one left open on an earlier day
  /// (closing that "now" would count days as hours on site).
  Future<void> punchOut(String id, {double? lat, double? lng, bool? withinGeofence, DateTime? at}) =>
      transaction(() async {
        await (update(labourAttendance)..where((a) => a.id.equals(id))).write(LabourAttendanceCompanion(
          punchOut: Value(at ?? DateTime.now()),
          lat: lat == null ? const Value.absent() : Value(lat),
          lng: lng == null ? const Value.absent() : Value(lng),
          withinGeofence: withinGeofence == null ? const Value.absent() : Value(withinGeofence),
        ));
        final row = await (select(labourAttendance)..where((a) => a.id.equals(id))).getSingle();
        await db.syncOutboxDao.enqueue(
          targetTable: 'site_attendance',
          recordId: row.id,
          operation: 'update',
          payloadJson: jsonEncode(attendanceToSupabaseJson(row)),
        );
      });

  Future<void> upsertFromRemote(LabourAttendanceCompanion c) => into(labourAttendance).insertOnConflictUpdate(c);

  /// Newest punch first.
  Future<List<LabourAttendanceData>> forProject(String projectId) => (select(labourAttendance)
        ..where((a) => a.projectId.equals(projectId))
        ..orderBy([(a) => OrderingTerm.desc(a.punchIn)]))
      .get();

  /// One id per worker per day on every phone, so two people marking the
  /// same worker's day end up with one row, the later mark winning.
  static String markId(String projectId, String workerId, String day) =>
      _uuid.v5(Namespace.url.value, 'fieldos:attendance-mark:$projectId:$workerId:$day');

  /// Hand-marked days of the site (rows cleared back to punches included,
  /// with null units).
  Future<List<AttendanceMark>> marksForProject(String projectId) =>
      (select(attendanceMarks)..where((m) => m.projectId.equals(projectId))).get();

  /// Marks [workerId]'s [day] as [units] days (null: count the punches).
  Future<AttendanceMark> setMark({
    required String projectId,
    required String workerId,
    required String day,
    required double? units,
    required String by,
    DateTime? now,
  }) =>
      transaction(() async {
        final id = markId(projectId, workerId, day);
        await into(attendanceMarks).insertOnConflictUpdate(AttendanceMarksCompanion.insert(
          id: id,
          projectId: projectId,
          workerId: workerId,
          day: day,
          units: Value(units),
          recordedBy: by,
          updatedAt: Value(now ?? DateTime.now()),
        ));
        final row = await (select(attendanceMarks)..where((m) => m.id.equals(id))).getSingle();
        await db.syncOutboxDao.enqueue(
          targetTable: 'site_attendance_marks',
          recordId: id,
          operation: 'upsert',
          payloadJson: jsonEncode(attendanceMarkToSupabaseJson(row)),
        );
        return row;
      });

  /// A teammate's mark replaces ours only when it is newer.
  Future<void> upsertMarkFromRemote(AttendanceMarksCompanion c) async {
    final mine = await (select(attendanceMarks)..where((m) => m.id.equals(c.id.value))).getSingleOrNull();
    if (mine != null && c.updatedAt.present && mine.updatedAt.isAfter(c.updatedAt.value)) return;
    await into(attendanceMarks).insertOnConflictUpdate(c);
  }
}

// ---------------------------------------------------------------------------
// Site notes
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [ProjectNotes])
class NoteDao extends DatabaseAccessor<AppDatabase> with _$NoteDaoMixin {
  NoteDao(super.db);

  /// The site's notes, pinned first, then the latest change first. Removed
  /// notes are left out.
  Future<List<ProjectNote>> forProject(String projectId) => (select(projectNotes)
        ..where((n) => n.projectId.equals(projectId) & n.deleted.equals(false))
        ..orderBy([
          (n) => OrderingTerm.desc(n.pinned),
          (n) => OrderingTerm.desc(n.updatedAt),
        ]))
      .get();

  Future<ProjectNote> create({required String projectId, required String body, required String by, bool pinned = false, DateTime? now}) {
    final at = now ?? DateTime.now();
    return transaction(() async {
      final row = await into(projectNotes).insertReturning(ProjectNotesCompanion.insert(
        id: _uuid.v4(),
        projectId: projectId,
        body: _noteBody(body),
        pinned: Value(pinned),
        createdBy: by,
        createdAt: Value(at),
        updatedAt: Value(at),
      ));
      await _queue(row, 'insert');
      return row;
    });
  }

  /// Rewrites, pins or removes a note. The site and who wrote it stay.
  Future<ProjectNote> change(String id, {String? body, bool? pinned, bool? deleted, DateTime? now}) {
    return transaction(() async {
      await (update(projectNotes)..where((n) => n.id.equals(id))).write(ProjectNotesCompanion(
        body: body == null ? const Value.absent() : Value(_noteBody(body)),
        pinned: pinned == null ? const Value.absent() : Value(pinned),
        deleted: deleted == null ? const Value.absent() : Value(deleted),
        updatedAt: Value(now ?? DateTime.now()),
      ));
      final row = await (select(projectNotes)..where((n) => n.id.equals(id))).getSingle();
      await _queue(row, 'update');
      return row;
    });
  }

  Future<void> _queue(ProjectNote row, String operation) => db.syncOutboxDao.enqueue(
        targetTable: 'site_notes',
        recordId: row.id,
        operation: operation,
        payloadJson: jsonEncode(projectNoteToSupabaseJson(row)),
      );

  /// A teammate's copy replaces ours only when it is newer.
  Future<void> upsertFromRemote(ProjectNotesCompanion c) async {
    final mine = await (select(projectNotes)..where((n) => n.id.equals(c.id.value))).getSingleOrNull();
    if (mine != null && c.updatedAt.present && mine.updatedAt.isAfter(c.updatedAt.value)) return;
    await into(projectNotes).insertOnConflictUpdate(c);
  }
}

String _noteBody(String body) {
  final t = body.trim();
  if (t.isEmpty) throw ArgumentError('A note needs some words');
  return t.length > 4000 ? t.substring(0, 4000) : t;
}

/// What kind of file a bill is, from its name.
String attachmentMimeType(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

Future<void> _deleteFileQuietly(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {
    // The row is gone; a file the phone won't let us delete is harmless.
  }
}

@DriftAccessor(tables: [ProjectGeofences])
class GeofenceDao extends DatabaseAccessor<AppDatabase> with _$GeofenceDaoMixin {
  GeofenceDao(super.db);

  Future<ProjectGeofence?> forProject(String projectId) =>
      (select(projectGeofences)..where((g) => g.projectId.equals(projectId))).getSingleOrNull();

  /// Saves the geofence locally AND on the project row, which is what
  /// syncs: the local-only table used to mean a geofence set on the owner's
  /// phone never reached the supervisors' phones that do the punching in.
  Future<void> set(String projectId, double lat, double lng, double radiusMeters) async {
    await into(projectGeofences).insertOnConflictUpdate(ProjectGeofencesCompanion(
      projectId: Value(projectId),
      centerLat: Value(lat),
      centerLng: Value(lng),
      radiusMeters: Value(radiusMeters),
    ));
    await db.projectDao.setLocation(projectId, lat: lat, lng: lng, radiusM: radiusMeters.round());
  }

  /// The project's synced site location when it has one (set on this or a
  /// colleague's phone -- [set] writes both), else a geofence that only
  /// exists locally from before site locations synced.
  Future<ProjectGeofence?> effectiveFor(String projectId) async {
    final project = await db.projectDao.byId(projectId);
    final lat = project?.locationLat, lng = project?.locationLng;
    if (project != null && lat != null && lng != null) {
      return ProjectGeofence(
        projectId: projectId,
        centerLat: lat,
        centerLng: lng,
        radiusMeters: (project.geofenceRadiusM ?? 100).toDouble(),
        updatedAt: project.createdAt,
      );
    }
    return forProject(projectId);
  }
}

// ---------------------------------------------------------------------------
// Multi-level approvals
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [Approvals])
class ApprovalDao extends DatabaseAccessor<AppDatabase> with _$ApprovalDaoMixin {
  ApprovalDao(super.db);

  Future<Approval> create(ApprovalsCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(approvals).insert(companion.copyWith(id: Value(id)));
      final row = await (select(approvals)..where((a) => a.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'approvals',
        recordId: row.id,
        operation: 'insert',
        payloadJson: jsonEncode(approvalToSupabaseJson(row)),
      );
      return row;
    });
  }

  Future<List<Approval>> pendingFor(String? projectId) {
    final q = select(approvals)..where((a) => a.status.equals('pending'));
    if (projectId != null) {
      q.where((a) => a.projectId.equals(projectId));
    }
    return q.get();
  }

  /// Records the decision. What was asked (the request's own note, such as
  /// "Spending is ₹25,000 over the BOQ budget.") stays, and a reason, if
  /// one is given, goes after it; it used to replace the request text, so
  /// a decided approval no longer said what it had been about.
  Future<void> decide(String id, bool approved, String approverId, String? note) {
    return transaction(() async {
      final before = await (select(approvals)..where((a) => a.id.equals(id))).getSingle();
      final reason = note?.trim() ?? '';
      final asked = before.decisionNote?.trim() ?? '';
      final joined = reason.isEmpty
          ? before.decisionNote
          : asked.isEmpty
              ? reason
              : '$asked\nReason: $reason';
      // The column holds 300 characters.
      final text = joined != null && joined.length > 300 ? joined.substring(0, 300) : joined;
      await (update(approvals)..where((a) => a.id.equals(id))).write(ApprovalsCompanion(
        status: Value(approved ? 'approved' : 'rejected'),
        approverId: Value(approverId),
        decisionNote: Value(text),
        decidedAt: Value(DateTime.now()),
      ));
      final row = await (select(approvals)..where((a) => a.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'approvals',
        recordId: row.id,
        operation: 'update',
        payloadJson: jsonEncode(approvalToSupabaseJson(row)),
      );
    });
  }

  /// See ProjectDao.upsertFromRemote -- same server-wins merge pattern.
  Future<void> upsertFromRemote(ApprovalsCompanion companion) =>
      into(approvals).insertOnConflictUpdate(companion);
}

// ---------------------------------------------------------------------------
// Equipment
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [Equipment, EquipmentLogs])
class EquipmentDao extends DatabaseAccessor<AppDatabase> with _$EquipmentDaoMixin {
  EquipmentDao(super.db);

  Future<EquipmentData> create(EquipmentCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(equipment).insert(companion.copyWith(id: Value(id)));
      final row = await (select(equipment)..where((e) => e.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'equipment',
        recordId: row.id,
        operation: 'insert',
        payloadJson: jsonEncode(equipmentToSupabaseJson(row)),
      );
      return row;
    });
  }

  Future<List<EquipmentData>> forProject(String projectId) {
    return (select(equipment)..where((e) => e.projectId.equals(projectId))).get();
  }

  Future<void> updateStatus(String id, String status) => edit(id, EquipmentCompanion(status: Value(status)));

  /// Changes a machine's details. It stays on its site.
  Future<EquipmentData> edit(String id, EquipmentCompanion changes) {
    return transaction(() async {
      await (update(equipment)..where((e) => e.id.equals(id))).write(changes.copyWith(
        id: const Value.absent(),
        projectId: const Value.absent(),
        createdAt: const Value.absent(),
      ));
      final row = await (select(equipment)..where((e) => e.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'equipment',
        recordId: row.id,
        operation: 'update',
        payloadJson: jsonEncode(equipmentToSupabaseJson(row)),
      );
      return row;
    });
  }

  /// A hired machine went back to its owner on [on]; it is no longer on
  /// site, so it can't be "in use".
  Future<EquipmentData> markReturned(String id, DateTime on) async {
    final e = await (select(equipment)..where((x) => x.id.equals(id))).getSingle();
    // The cloud refuses a return before the hire began.
    final day = DateTime(on.year, on.month, on.day);
    final hired = e.hiredOn;
    return edit(id, EquipmentCompanion(
      returnedOn: Value(hired != null && day.isBefore(hired) ? hired : day),
      status: const Value('available'),
    ));
  }

  /// Every usage log of the site's machines, for the hire register.
  Future<List<EquipmentLog>> logsForProject(String projectId) {
    final q = select(equipmentLogs).join([innerJoin(equipment, equipment.id.equalsExp(equipmentLogs.equipmentId))])
      ..where(equipment.projectId.equals(projectId));
    return q.map((r) => r.readTable(equipmentLogs)).get();
  }

  /// See ProjectDao.upsertFromRemote -- same server-wins merge pattern.
  Future<void> upsertFromRemote(EquipmentCompanion companion) =>
      into(equipment).insertOnConflictUpdate(companion);

  Future<EquipmentLog> addLog(EquipmentLogsCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(equipmentLogs).insert(companion.copyWith(id: Value(id)));
      final row = await (select(equipmentLogs)..where((l) => l.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'equipment_logs',
        recordId: row.id,
        operation: 'insert',
        payloadJson: jsonEncode(equipmentLogToSupabaseJson(row)),
      );
      return row;
    });
  }

  /// See ProjectDao.upsertFromRemote -- same server-wins merge pattern.
  Future<void> upsertLogFromRemote(EquipmentLogsCompanion companion) =>
      into(equipmentLogs).insertOnConflictUpdate(companion);

  Future<List<EquipmentLog>> logsFor(String equipmentId) {
    return (select(equipmentLogs)
          ..where((l) => l.equipmentId.equals(equipmentId))
          ..orderBy([(l) => OrderingTerm.desc(l.logDate)]))
        .get();
  }
}

// ---------------------------------------------------------------------------
// Inspections
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [Inspections, InspectionItems])
class InspectionDao extends DatabaseAccessor<AppDatabase> with _$InspectionDaoMixin {
  InspectionDao(super.db);

  Future<Inspection> create(InspectionsCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(inspections).insert(companion.copyWith(id: Value(id)));
      final row = await (select(inspections)..where((i) => i.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'inspections',
        recordId: row.id,
        operation: 'insert',
        payloadJson: jsonEncode(inspectionToSupabaseJson(row)),
      );
      return row;
    });
  }

  Future<List<Inspection>> forProject(String projectId) {
    return (select(inspections)..where((i) => i.projectId.equals(projectId))).get();
  }

  Future<void> complete(String id, String overallResult) {
    return transaction(() async {
      await (update(inspections)..where((i) => i.id.equals(id))).write(InspectionsCompanion(
        status: const Value('completed'),
        completedDate: Value(DateTime.now()),
        overallResult: Value(overallResult),
      ));
      final row = await (select(inspections)..where((i) => i.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'inspections',
        recordId: row.id,
        operation: 'update',
        payloadJson: jsonEncode(inspectionToSupabaseJson(row)),
      );
    });
  }

  /// See ProjectDao.upsertFromRemote -- same server-wins merge pattern.
  Future<void> upsertFromRemote(InspectionsCompanion companion) =>
      into(inspections).insertOnConflictUpdate(companion);

  Future<InspectionItem> addItem(InspectionItemsCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    // Auto-assign sortOrder if not provided
    final effectiveCompanion = companion.sortOrder.present
        ? companion
        : companion.copyWith(sortOrder: const Value(0)); // We'll update after insert
    return transaction(() async {
      // First, get the current count of items for this inspection to set sortOrder
      int sortOrder = 0;
      if (!companion.sortOrder.present) {
        final count = await (select(inspectionItems)
              ..where((item) => item.inspectionId.equals(companion.inspectionId.value))).get();
        sortOrder = count.length;
      }
      await into(inspectionItems).insert(effectiveCompanion.copyWith(
        id: Value(id),
        sortOrder: Value(sortOrder),
      ));
      final row = await (select(inspectionItems)..where((item) => item.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'inspection_items',
        recordId: row.id,
        operation: 'insert',
        payloadJson: jsonEncode(inspectionItemToSupabaseJson(row)),
      );
      return row;
    });
  }

  /// See ProjectDao.upsertFromRemote -- same server-wins merge pattern.
  Future<void> upsertItemFromRemote(InspectionItemsCompanion companion) =>
      into(inspectionItems).insertOnConflictUpdate(companion);

  Future<List<InspectionItem>> itemsFor(String inspectionId) {
    return (select(inspectionItems)
          ..where((item) => item.inspectionId.equals(inspectionId))
          ..orderBy([(item) => OrderingTerm.asc(item.sortOrder)]))
        .get();
  }

  /// A ticked checklist item, sent to the team like every other change (it
  /// used to stay on the phone that ticked it).
  Future<void> updateItemStatus(String id, String status, {String? notes}) {
    final companion = InspectionItemsCompanion(
      status: Value(status),
      notes: notes != null ? Value(notes) : const Value.absent(),
    );
    return transaction(() async {
      await (update(inspectionItems)..where((item) => item.id.equals(id))).write(companion);
      final row = await (select(inspectionItems)..where((item) => item.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'inspection_items',
        recordId: row.id,
        operation: 'update',
        payloadJson: jsonEncode(inspectionItemToSupabaseJson(row)),
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Documents
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [Documents])
class DocumentDao extends DatabaseAccessor<AppDatabase> with _$DocumentDaoMixin {
  DocumentDao(super.db);

  /// Mirrors the desktop backend's versioning rule (fieldos/routers/documents.py):
  /// if a document with this exact `name` already exists for this project, the
  /// new row's version = (max existing version for that name) + 1; otherwise 1.
  Future<Document> create(DocumentsCompanion companion) {
    return transaction(() async {
      // Look up existing rows for (projectId, name) to compute next version
      final existing = await (select(documents)
            ..where((d) => d.projectId.equals(companion.projectId.value) & d.name.equals(companion.name.value))
            ..orderBy([(d) => OrderingTerm.desc(d.version)]))
          .get();
      final nextVersion = existing.isEmpty ? 1 : existing.first.version + 1;

      final id = companion.id.present ? companion.id.value : _uuid.v4();
      await into(documents).insert(companion.copyWith(
        id: Value(id),
        version: Value(nextVersion),
      ));
      final row = await (select(documents)..where((d) => d.id.equals(id))).getSingle();
      // The file itself rides through Supabase Storage (see SyncEngine's
      // documents branch); the outbox payload carries the local path under a
      // transient key the engine strips before the row reaches Postgres.
      await db.syncOutboxDao.enqueue(
        targetTable: 'documents',
        recordId: row.id,
        operation: 'insert',
        payloadJson: jsonEncode({
          ...documentToSupabaseJson(row),
          '_local_file_path': row.filePath,
        }),
      );
      return (await (select(documents)..where((d) => d.id.equals(id))).getSingle());
    });
  }

  Future<List<Document>> forProject(String projectId) {
    return (select(documents)
          ..where((d) => d.projectId.equals(projectId))
          ..orderBy([(d) => OrderingTerm.desc(d.createdAt)]))
        .get();
  }

  Future<List<Document>> versionsOf(String projectId, String name) {
    return (select(documents)
          ..where((d) => d.projectId.equals(projectId) & d.name.equals(name))
          ..orderBy([(d) => OrderingTerm.desc(d.version)]))
        .get();
  }

  /// See ProjectDao.upsertFromRemote -- same server-wins merge pattern.
  Future<void> upsertFromRemote(DocumentsCompanion companion) =>
      into(documents).insertOnConflictUpdate(companion);
}

// ---------------------------------------------------------------------------
// Workers
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [Workers])
class WorkerDao extends DatabaseAccessor<AppDatabase> with _$WorkerDaoMixin {
  WorkerDao(super.db);

  Future<Worker> create(WorkersCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(workers).insert(companion.copyWith(id: Value(id)));
      final row = await (select(workers)..where((w) => w.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'workers',
        recordId: row.id,
        operation: 'insert',
        payloadJson: jsonEncode(workerToSupabaseJson(row)),
      );
      return row;
    });
  }

  Future<List<Worker>> forProject(String projectId) {
    return (select(workers)
          ..where((w) => w.projectId.equals(projectId))
          ..orderBy([(w) => OrderingTerm.asc(w.name)]))
        .get();
  }

  Future<void> setStatus(String id, String status) {
    return transaction(() async {
      await (update(workers)..where((w) => w.id.equals(id))).write(WorkersCompanion(status: Value(status)));
      final row = await (select(workers)..where((w) => w.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'workers',
        recordId: row.id,
        operation: 'update',
        payloadJson: jsonEncode(workerToSupabaseJson(row)),
      );
    });
  }

  /// See ProjectDao.upsertFromRemote -- same server-wins merge pattern.
  Future<void> upsertFromRemote(WorkersCompanion companion) =>
      into(workers).insertOnConflictUpdate(companion);
}

// ---------------------------------------------------------------------------
// Sync outbox (see docs/SUPABASE_SYNC_RESEARCH.md, lib/sync/sync_engine.dart)
// ---------------------------------------------------------------------------

/// Above this many failed push attempts, an outbox entry is left in place
/// (not deleted) but stops being retried automatically -- surfaced via
/// [parked] for a manual "why didn't this sync" UI later, rather than
/// retrying a permanently-broken write forever.
const int syncOutboxMaxRetries = 5;

/// Settings key for [SyncOutboxDao.localOnlyIds].
const localOnlyIdsKey = 'local_only_ids';

@DriftAccessor(tables: [SyncOutbox])
class SyncOutboxDao extends DatabaseAccessor<AppDatabase> with _$SyncOutboxDaoMixin {
  SyncOutboxDao(super.db);

  Set<String>? _localOnly;

  /// Records that stay on this phone: the sample project and everything
  /// made under it. Kept in settings under [localOnlyIdsKey].
  Future<Set<String>> localOnlyIds() async {
    final cached = _localOnly;
    if (cached != null) return cached;
    final raw = await db.settingsDao.get(localOnlyIdsKey);
    final ids = <String>{if (raw != null && raw.isNotEmpty) ...(jsonDecode(raw) as List).cast<String>()};
    return _localOnly = ids;
  }

  Future<void> _saveLocalOnly(Set<String> ids) => db.settingsDao.set(localOnlyIdsKey, jsonEncode(ids.toList()));

  /// Keeps [id], and anything later written that points at it, off the
  /// cloud.
  Future<void> markLocalOnly(String id) async {
    final ids = await localOnlyIds();
    if (ids.add(id)) await _saveLocalOnly(ids);
  }

  Future<void> forgetLocalOnly(Iterable<String> remove) async {
    final ids = await localOnlyIds();
    ids.removeAll(remove);
    await _saveLocalOnly(ids);
  }

  /// Queues a write for the cloud, unless the record is local-only or
  /// points at one (a task of the sample project, a log of its machine):
  /// then the record becomes local-only too and nothing is queued.
  Future<void> enqueue({
    required String targetTable,
    required String recordId,
    required String operation,
    required String payloadJson,
  }) async {
    final local = await localOnlyIds();
    if (local.isNotEmpty) {
      var skip = local.contains(recordId);
      if (!skip) {
        final payload = jsonDecode(payloadJson);
        skip = payload is Map && payload.values.any((v) => v is String && local.contains(v));
      }
      if (skip) {
        await markLocalOnly(recordId);
        return;
      }
    }
    await into(syncOutbox).insert(SyncOutboxCompanion.insert(
      targetTable: targetTable,
      recordId: recordId,
      operation: operation,
      payload: payloadJson,
    ));
  }

  /// Entries still worth retrying, oldest first (so a stuck head-of-queue
  /// entry doesn't block ordering forever -- caller stops draining on the
  /// first failure within a run rather than skipping past it, to preserve
  /// write ordering per record).
  Future<List<SyncOutboxData>> pending() {
    return (select(syncOutbox)
          ..where((o) => o.retryCount.isSmallerThanValue(syncOutboxMaxRetries))
          ..orderBy([(o) => OrderingTerm.asc(o.createdAt)]))
        .get();
  }

  Future<List<SyncOutboxData>> parked() {
    return (select(syncOutbox)..where((o) => o.retryCount.isBiggerOrEqualValue(syncOutboxMaxRetries))).get();
  }

  Future<void> markSynced(int id) => (delete(syncOutbox)..where((o) => o.id.equals(id))).go();

  Future<void> recordFailure(int id, String error) async {
    final row = await (select(syncOutbox)..where((o) => o.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    await (update(syncOutbox)..where((o) => o.id.equals(id))).write(SyncOutboxCompanion(
      retryCount: Value(row.retryCount + 1),
      lastError: Value(error),
    ));
  }

  /// The server could not be reached: keep the reason for the status
  /// screen but do not count a try, so a phone that is offline for hours
  /// never parks its writes.
  Future<void> noteTransientFailure(int id, String error) =>
      (update(syncOutbox)..where((o) => o.id.equals(id))).write(SyncOutboxCompanion(lastError: Value(error)));

  Future<int> pendingCount() async {
    final rows = await pending();
    return rows.length;
  }

  /// Rows parked after [syncOutboxMaxRetries] failures, for the sync
  /// status UI -- these will not be retried automatically.
  Future<int> parkedCount() async => (await parked()).length;

  static String key(String table, String recordId) => '$table:$recordId';

  /// Every (table, record) this device has written but not yet pushed,
  /// including parked rows. Pull and Realtime skip these so an unpushed
  /// local edit is never replaced by an older server copy.
  Future<Set<String>> dirtyKeys() async {
    final rows = await select(syncOutbox).get();
    return {for (final r in rows) key(r.targetTable, r.recordId)};
  }

  /// Gives parked rows another chance (e.g. after the RLS/membership issue
  /// that parked them has been fixed by joining the company).
  Future<void> retryParked() =>
      (update(syncOutbox)..where((o) => o.retryCount.isBiggerOrEqualValue(syncOutboxMaxRetries)))
          .write(const SyncOutboxCompanion(retryCount: Value(0)));
}

// ---------------------------------------------------------------------------
// Team chat
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [ProjectMessages])
class MessageDao extends DatabaseAccessor<AppDatabase> with _$MessageDaoMixin {
  MessageDao(super.db);

  /// Local write + outbox entry in one transaction (see ProjectDao.create).
  Future<ProjectMessage> send({
    required String projectId,
    required String senderId,
    required String senderName,
    required String body,
  }) {
    final id = _uuid.v4();
    return transaction(() async {
      await into(projectMessages).insert(ProjectMessagesCompanion.insert(
        id: id,
        projectId: projectId,
        senderId: senderId,
        senderName: senderName,
        body: body,
        createdAt: Value(DateTime.now().toUtc()),
      ));
      final row = await (select(projectMessages)..where((m) => m.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'project_messages',
        recordId: row.id,
        operation: 'insert',
        payloadJson: jsonEncode(projectMessageToSupabaseJson(row)),
      );
      return row;
    });
  }

  Future<void> upsertFromRemote(ProjectMessagesCompanion companion) =>
      into(projectMessages).insertOnConflictUpdate(companion);

  /// Oldest first, the order a chat reads in.
  Stream<List<ProjectMessage>> watchForProject(String projectId) =>
      (select(projectMessages)
            ..where((m) => m.projectId.equals(projectId))
            ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
          .watch();

  Future<List<ProjectMessage>> forProject(String projectId) =>
      (select(projectMessages)
            ..where((m) => m.projectId.equals(projectId))
            ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
          .get();
}

// ---------------------------------------------------------------------------
// Weekly site close (v15)
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [CloseReviews])
class CloseDao extends DatabaseAccessor<AppDatabase> with _$CloseDaoMixin {
  CloseDao(super.db);

  /// Every decision on a site's week, oldest first. Dates are kept to the
  /// second, so two decisions in the same second keep the order they were
  /// written in (rowid); pulls apply teammates' rows in change-log order.
  Future<List<CloseReview>> forWeek(String projectId, String weekStart) => (select(closeReviews)
        ..where((r) => r.projectId.equals(projectId) & r.weekStart.equals(weekStart))
        ..orderBy([(r) => OrderingTerm.asc(r.createdAt), (r) => OrderingTerm.asc(r.rowId)]))
      .get();

  /// Every decision on the site, oldest first.
  Future<List<CloseReview>> forProject(String projectId) => (select(closeReviews)
        ..where((r) => r.projectId.equals(projectId))
        ..orderBy([(r) => OrderingTerm.asc(r.createdAt), (r) => OrderingTerm.asc(r.rowId)]))
      .get();

  /// Records one decision. Rows are only ever added: a correction is a new
  /// row, so the history stays as it happened.
  Future<CloseReview> record({
    required String projectId,
    required String weekStart,
    required String itemKind,
    required String itemId,
    required String decision,
    required String by,
    String? note,
    String? fingerprint,
    double? amount,
    double? acceptedQty,
    DateTime? now,
  }) =>
      transaction(() async {
        final row = await into(closeReviews).insertReturning(CloseReviewsCompanion.insert(
          id: _uuid.v4(),
          projectId: projectId,
          weekStart: weekStart,
          itemKind: itemKind,
          itemId: itemId,
          decision: decision,
          note: Value(_clip(note, 300)),
          fingerprint: Value(_clip(fingerprint, 200)),
          amount: Value(amount),
          acceptedQty: Value(acceptedQty),
          decidedBy: by,
          createdAt: Value(now ?? DateTime.now()),
        ));
        await db.syncOutboxDao.enqueue(
          targetTable: 'site_close_reviews',
          recordId: row.id,
          operation: 'insert',
          payloadJson: jsonEncode(closeReviewToSupabaseJson(row)),
        );
        return row;
      });

  Future<void> upsertFromRemote(CloseReviewsCompanion c) => into(closeReviews).insertOnConflictUpdate(c);
}

// ---------------------------------------------------------------------------
// Commercial controls (v16): budget lines, claims, certificates, variations,
// exception actions. See features/commercial/commercial.dart for the rules
// and supabase/migrations/20261110100000_commercial_controls.sql for the
// server's copy of them.
// ---------------------------------------------------------------------------

/// A certification the rules refuse (the same quantity twice, or beyond
/// the order). The message is shown as is.
class CertificationRefused implements Exception {
  CertificationRefused(this.message);
  final String message;
  @override
  String toString() => message;
}

@DriftAccessor(tables: [
  CostCodes,
  WorkOrders,
  WorkClaims,
  WorkCertifications,
  Variations,
  VariationDecisions,
  CommercialAttachments,
  ExceptionActions,
  PurchaseOrders,
  SiteExpenses,
])
class CommercialDao extends DatabaseAccessor<AppDatabase> with _$CommercialDaoMixin {
  CommercialDao(super.db);

  Future<void> _queue(String table, String id, String op, Map<String, dynamic> json) =>
      db.syncOutboxDao.enqueue(targetTable: table, recordId: id, operation: op, payloadJson: jsonEncode(json));

  // --- Budget lines ---------------------------------------------------------

  Future<List<CostCode>> costCodesFor(String projectId) => (select(costCodes)
        ..where((c) => c.projectId.equals(projectId))
        ..orderBy([(c) => OrderingTerm.asc(c.sortOrder), (c) => OrderingTerm.asc(c.code)]))
      .get();

  Future<CostCode> addCostCode({
    required String projectId,
    required String code,
    required String name,
    double originalBudget = 0,
    double uncommittedEstimate = 0,
  }) =>
      transaction(() async {
        final n = (await costCodesFor(projectId)).length;
        final row = await into(costCodes).insertReturning(CostCodesCompanion.insert(
          id: _uuid.v4(),
          projectId: projectId,
          code: code.trim(),
          name: name.trim(),
          originalBudget: Value(originalBudget),
          uncommittedEstimate: Value(uncommittedEstimate),
          sortOrder: Value(n),
        ));
        await _queue('cost_codes', row.id, 'insert', costCodeToSupabaseJson(row));
        return row;
      });

  /// The original budget changes only by an approved variation, so this
  /// edits the name and what is still to be committed.
  Future<void> updateCostCode(String id, {String? name, double? uncommittedEstimate, double? originalBudget}) =>
      transaction(() async {
        await (update(costCodes)..where((c) => c.id.equals(id))).write(CostCodesCompanion(
          name: name == null ? const Value.absent() : Value(name.trim()),
          uncommittedEstimate: uncommittedEstimate == null ? const Value.absent() : Value(uncommittedEstimate),
          originalBudget: originalBudget == null ? const Value.absent() : Value(originalBudget),
          updatedAt: Value(DateTime.now()),
        ));
        final row = await (select(costCodes)..where((c) => c.id.equals(id))).getSingle();
        await _queue('cost_codes', id, 'update', costCodeToSupabaseJson(row));
      });

  Future<void> setOrderCostCode(String orderId, String? costCodeId) => transaction(() async {
        await (update(purchaseOrders)..where((o) => o.id.equals(orderId)))
            .write(PurchaseOrdersCompanion(costCodeId: Value(costCodeId)));
        final row = await (select(purchaseOrders)..where((o) => o.id.equals(orderId))).getSingle();
        await _queue('purchase_orders', orderId, 'update', purchaseOrderToSupabaseJson(row));
      });

  Future<void> setExpenseCostCode(String expenseId, String? costCodeId) => transaction(() async {
        await (update(siteExpenses)..where((e) => e.id.equals(expenseId)))
            .write(SiteExpensesCompanion(costCodeId: Value(costCodeId)));
        final row = await (select(siteExpenses)..where((e) => e.id.equals(expenseId))).getSingle();
        await _queue('site_expenses', expenseId, 'update', siteExpenseToSupabaseJson(row));
      });

  // --- Work orders ----------------------------------------------------------

  Future<List<WorkOrder>> workOrdersFor(String projectId) => (select(workOrders)
        ..where((w) => w.projectId.equals(projectId))
        ..orderBy([(w) => OrderingTerm.asc(w.createdAt)]))
      .get();

  Future<List<WorkOrder>> workOrdersForSubcontractor(String subcontractorId) =>
      (select(workOrders)..where((w) => w.subcontractorId.equals(subcontractorId))).get();

  Future<WorkOrder?> workOrderById(String id) => (select(workOrders)..where((w) => w.id.equals(id))).getSingleOrNull();

  /// A work order with its baseline: the agreed quantity, unit and rate.
  Future<WorkOrder> createWorkOrder({
    required String projectId,
    required String subcontractorId,
    required String description,
    required String unit,
    required double qty,
    required double rate,
    String? costCodeId,
  }) =>
      transaction(() async {
        final row = await into(workOrders).insertReturning(WorkOrdersCompanion.insert(
          id: _uuid.v4(),
          projectId: projectId,
          subcontractorId: subcontractorId,
          description: description.trim(),
          agreedAmount: Value(_money(qty * rate)),
          unit: Value(unit.trim()),
          contractQty: Value(qty),
          rate: Value(rate),
          costCodeId: Value(costCodeId),
        ));
        await _queue('work_orders', row.id, 'insert', workOrderToSupabaseJson(row));
        return row;
      });

  // --- Claims and certification ---------------------------------------------

  Future<List<WorkClaim>> claimsFor(String workOrderId) => (select(workClaims)
        ..where((c) => c.workOrderId.equals(workOrderId))
        ..orderBy([(c) => OrderingTerm.asc(c.createdAt), (c) => OrderingTerm.asc(c.rowId)]))
      .get();

  Future<List<WorkClaim>> claimsForProject(String projectId) => (select(workClaims)
        ..where((c) => c.projectId.equals(projectId))
        ..orderBy([(c) => OrderingTerm.asc(c.createdAt), (c) => OrderingTerm.asc(c.rowId)]))
      .get();

  Future<WorkClaim?> claimById(String id) => (select(workClaims)..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<List<WorkCertification>> certificationsFor(String workOrderId) => (select(workCertifications)
        ..where((c) => c.workOrderId.equals(workOrderId))
        ..orderBy([(c) => OrderingTerm.asc(c.createdAt), (c) => OrderingTerm.asc(c.rowId)]))
      .get();

  Future<List<WorkCertification>> certificationsForProject(String projectId) => (select(workCertifications)
        ..where((c) => c.projectId.equals(projectId))
        ..orderBy([(c) => OrderingTerm.asc(c.createdAt), (c) => OrderingTerm.asc(c.rowId)]))
      .get();

  Future<WorkClaim> submitClaim({
    required String workOrderId,
    required double qty,
    required String by,
    String? location,
    String? note,
    List<String> photos = const [],
    DateTime? now,
  }) =>
      transaction(() async {
        final order = await workOrderById(workOrderId);
        if (order == null) throw StateError('This work order is no longer on the phone.');
        if (qty <= 0) throw CertificationRefused('Enter the quantity completed.');
        final row = await into(workClaims).insertReturning(WorkClaimsCompanion.insert(
          id: _uuid.v4(),
          projectId: order.projectId,
          workOrderId: workOrderId,
          qty: qty,
          location: Value(_clip(location, 120)),
          note: Value(_clip(note, 300)),
          submittedBy: by,
          createdAt: Value(now ?? DateTime.now()),
        ));
        await _queue('work_claims', row.id, 'insert', workClaimToSupabaseJson(row));
        for (final p in photos) {
          await attach(projectId: order.projectId, parentKind: 'claim', parentId: row.id, filePath: p);
        }
        return row;
      });

  /// Accepted and rejected quantities on a claim; with [raiseVariation],
  /// what is left of the claim (beyond the order) goes to the variation
  /// register in the same step. With [againstVariationId], quantity held
  /// for that (approved) variation is certified.
  Future<WorkCertification> certify({
    required String claimId,
    required double accepted,
    required double rejected,
    required String by,
    String? note,
    bool raiseVariation = false,
    String? againstVariationId,
    List<String> photos = const [],
    DateTime? now,
  }) =>
      transaction(() async {
        final claim = await claimById(claimId);
        if (claim == null) throw StateError('This claim is no longer on the phone.');
        final order = (await workOrderById(claim.workOrderId))!;
        final certs = await certificationsFor(order.id);
        final vars = await variationsFor(order.projectId);
        final decs = await decisionsFor(order.projectId);
        final refusal = certificationRefusal(
          order: order,
          claim: claim,
          certifications: certs,
          variations: vars,
          decisions: decs,
          accepted: accepted,
          rejected: rejected,
        );
        if (refusal != null) throw CertificationRefused(refusal);
        final held = claimHeldAfter(claim, certs, accepted: accepted, rejected: rejected);
        String? variationId = againstVariationId;
        if (raiseVariation && held > 0.0005) {
          final rate = workOrderRate(order) ?? 0;
          final v = await raiseVariationRow(
            projectId: order.projectId,
            workOrderId: order.id,
            costCodeId: order.costCodeId,
            title: trf('{what}: {qty} {unit} beyond the order',
                {'what': order.description, 'qty': fmtQty(held), 'unit': order.unit ?? ''}),
            origin: 'claim_over_order',
            sourceClaimId: claim.id,
            qty: held,
            unit: order.unit,
            estimatedCost: _money(held * rate),
            ownerId: null,
            note: note,
            by: by,
            now: now,
          );
          variationId = v.id;
          for (final p in photos) {
            await attach(projectId: order.projectId, parentKind: 'variation', parentId: v.id, filePath: p);
          }
        }
        if (accepted <= 0 && rejected <= 0 && variationId == null) {
          throw CertificationRefused('Nothing to certify: enter an accepted or rejected quantity.');
        }
        final row = await into(workCertifications).insertReturning(WorkCertificationsCompanion.insert(
          id: _uuid.v4(),
          projectId: order.projectId,
          workOrderId: order.id,
          claimId: claim.id,
          acceptedQty: Value(accepted),
          rejectedQty: Value(rejected),
          variationId: Value(variationId),
          note: Value(_clip(note, 300)),
          certifiedBy: by,
          createdAt: Value(now ?? DateTime.now()),
        ));
        await _queue('work_certifications', row.id, 'insert', workCertificationToSupabaseJson(row));
        for (final p in photos) {
          await attach(projectId: order.projectId, parentKind: 'certification', parentId: row.id, filePath: p);
        }
        return row;
      });

  // --- Variations -------------------------------------------------------------

  Future<List<Variation>> variationsFor(String projectId) => (select(variations)
        ..where((v) => v.projectId.equals(projectId))
        ..orderBy([(v) => OrderingTerm.asc(v.createdAt), (v) => OrderingTerm.asc(v.rowId)]))
      .get();

  Future<Variation?> variationById(String id) => (select(variations)..where((v) => v.id.equals(id))).getSingleOrNull();

  Future<List<VariationDecision>> decisionsFor(String projectId) =>
      (select(variationDecisions)..where((d) => d.projectId.equals(projectId))).get();

  Future<Variation> raiseVariationRow({
    required String projectId,
    required String title,
    required String origin,
    required String by,
    String? workOrderId,
    String? costCodeId,
    String? sourceClaimId,
    double? qty,
    String? unit,
    double estimatedCost = 0,
    int scheduleDays = 0,
    String? ownerId,
    String? note,
    List<String> photos = const [],
    DateTime? now,
  }) =>
      transaction(() async {
        final row = await into(variations).insertReturning(VariationsCompanion.insert(
          id: _uuid.v4(),
          projectId: projectId,
          workOrderId: Value(workOrderId),
          costCodeId: Value(costCodeId),
          title: _clip(title, 200) ?? 'Variation',
          origin: origin,
          sourceClaimId: Value(sourceClaimId),
          qty: Value(qty),
          unit: Value(_clip(unit, 20)),
          estimatedCost: Value(estimatedCost),
          scheduleDays: Value(scheduleDays),
          ownerId: Value(ownerId),
          note: Value(_clip(note, 500)),
          raisedBy: by,
          createdAt: Value(now ?? DateTime.now()),
        ));
        await _queue('variations', row.id, 'insert', variationToSupabaseJson(row));
        for (final p in photos) {
          await attach(projectId: projectId, parentKind: 'variation', parentId: row.id, filePath: p);
        }
        return row;
      });

  /// The one decision on a variation. An approved one changes the work
  /// order's quantity and value and the budget line it belongs to; the
  /// baseline stays as it was for comparison.
  Future<VariationDecision> decideVariation({
    required String variationId,
    required bool approve,
    required String by,
    double? approvedQty,
    double? approvedCost,
    String? note,
    DateTime? now,
  }) =>
      transaction(() async {
        final v = await variationById(variationId);
        if (v == null) throw StateError('This variation is no longer on the phone.');
        final existing = await (select(variationDecisions)..where((d) => d.variationId.equals(variationId)))
            .getSingleOrNull();
        if (existing != null) throw CertificationRefused('This variation has already been decided.');
        final row = await into(variationDecisions).insertReturning(VariationDecisionsCompanion.insert(
          id: _uuid.v4(),
          variationId: variationId,
          projectId: v.projectId,
          decision: approve ? 'approved' : 'rejected',
          approvedQty: Value(approve ? (approvedQty ?? v.qty) : null),
          approvedCost: Value(approve ? (approvedCost ?? v.estimatedCost) : null),
          note: Value(_clip(note, 300)),
          decidedBy: by,
          createdAt: Value(now ?? DateTime.now()),
        ));
        await _queue('variation_decisions', row.id, 'insert', variationDecisionToSupabaseJson(row));
        return row;
      });

  // --- Evidence -------------------------------------------------------------

  Future<CommercialAttachment> attach({
    required String projectId,
    required String parentKind,
    required String parentId,
    required String filePath,
  }) =>
      transaction(() async {
        final row = await into(commercialAttachments).insertReturning(CommercialAttachmentsCompanion.insert(
          id: _uuid.v4(),
          projectId: projectId,
          parentKind: parentKind,
          parentId: parentId,
          filePath: filePath,
          mimeType: attachmentMimeType(filePath),
        ));
        await _queue('commercial_attachments', row.id, 'insert', commercialAttachmentToSupabaseJson(row));
        return row;
      });

  Future<List<CommercialAttachment>> attachmentsFor(String projectId) =>
      (select(commercialAttachments)..where((a) => a.projectId.equals(projectId))).get();

  Future<CommercialAttachment?> attachmentById(String id) =>
      (select(commercialAttachments)..where((a) => a.id.equals(id))).getSingleOrNull();

  // --- Exceptions -------------------------------------------------------------

  Future<List<ExceptionAction>> exceptionActionsFor(String projectId) => (select(exceptionActions)
        ..where((a) => a.projectId.equals(projectId))
        ..orderBy([(a) => OrderingTerm.asc(a.createdAt), (a) => OrderingTerm.asc(a.rowId)]))
      .get();

  Future<ExceptionAction> actOnException({
    required String projectId,
    required String exceptionKey,
    required String action,
    required String by,
    String? ownerId,
    String? dueOn,
    String? note,
    String? fingerprint,
    DateTime? now,
  }) =>
      transaction(() async {
        final row = await into(exceptionActions).insertReturning(ExceptionActionsCompanion.insert(
          id: _uuid.v4(),
          projectId: projectId,
          exceptionKey: exceptionKey,
          action: action,
          ownerId: Value(ownerId),
          dueOn: Value(dueOn),
          note: Value(_clip(note, 300)),
          fingerprint: Value(_clip(fingerprint, 200)),
          actedBy: by,
          createdAt: Value(now ?? DateTime.now()),
        ));
        await _queue('commercial_exception_actions', row.id, 'insert', exceptionActionToSupabaseJson(row));
        return row;
      });

  // --- Pull -------------------------------------------------------------------

  Future<void> upsertCostCode(CostCodesCompanion c) => into(costCodes).insertOnConflictUpdate(c);
  Future<void> upsertClaim(WorkClaimsCompanion c) => into(workClaims).insertOnConflictUpdate(c);
  Future<void> upsertCertification(WorkCertificationsCompanion c) => into(workCertifications).insertOnConflictUpdate(c);
  Future<void> upsertVariation(VariationsCompanion c) => into(variations).insertOnConflictUpdate(c);
  Future<void> upsertDecision(VariationDecisionsCompanion c) => into(variationDecisions).insertOnConflictUpdate(c);
  Future<void> upsertAttachment(CommercialAttachmentsCompanion c) => into(commercialAttachments).insertOnConflictUpdate(c);
  Future<void> upsertExceptionAction(ExceptionActionsCompanion c) => into(exceptionActions).insertOnConflictUpdate(c);
}

double _money(double v) => (v * 100).roundToDouble() / 100;

// ---------------------------------------------------------------------------
// Site team and access (v17)
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [ProjectMembers, SiteAccess])
class SiteTeamDao extends DatabaseAccessor<AppDatabase> with _$SiteTeamDaoMixin {
  SiteTeamDao(super.db);

  Future<List<ProjectMember>> membersFor(String projectId) => (select(projectMembers)
        ..where((m) => m.projectId.equals(projectId))
        ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
      .get();

  /// The person's row on the site, if they are on its team.
  Future<ProjectMember?> memberOf(String projectId, String userId) =>
      (select(projectMembers)..where((m) => m.projectId.equals(projectId) & m.userId.equals(userId)))
          .getSingleOrNull();

  /// Every site's team rows for a company's sites, by project id.
  Future<Map<String, List<ProjectMember>>> membersByProject(Iterable<String> projectIds) async {
    final ids = projectIds.toList();
    if (ids.isEmpty) return const {};
    final rows = await (select(projectMembers)..where((m) => m.projectId.isIn(ids))).get();
    final out = <String, List<ProjectMember>>{};
    for (final r in rows) {
      (out[r.projectId] ??= []).add(r);
    }
    return out;
  }

  /// Adds someone to the site, or changes their role and limit if they
  /// are on it already.
  Future<ProjectMember> setMember(
      {required String projectId, required String userId, required String role, double? approvalLimit, DateTime? now}) {
    if (!siteRoleValues.contains(role)) throw ArgumentError.value(role, 'role');
    if (approvalLimit != null && approvalLimit < 0) throw ArgumentError.value(approvalLimit, 'approvalLimit');
    return transaction(() async {
      final at = now ?? DateTime.now();
      final mine = await memberOf(projectId, userId);
      if (mine == null) {
        final row = await into(projectMembers).insertReturning(ProjectMembersCompanion.insert(
          id: _uuid.v4(),
          projectId: projectId,
          userId: userId,
          role: role,
          approvalLimit: Value(approvalLimit),
          createdAt: Value(at),
          updatedAt: Value(at),
        ));
        await _queueMember(row, 'insert');
        return row;
      }
      await (update(projectMembers)..where((m) => m.id.equals(mine.id))).write(ProjectMembersCompanion(
        role: Value(role),
        approvalLimit: Value(approvalLimit),
        updatedAt: Value(at),
      ));
      final row = await (select(projectMembers)..where((m) => m.id.equals(mine.id))).getSingle();
      await _queueMember(row, 'update');
      return row;
    });
  }

  Future<void> removeMember(String id) => transaction(() async {
        final row = await (select(projectMembers)..where((m) => m.id.equals(id))).getSingleOrNull();
        if (row == null) return;
        await (delete(projectMembers)..where((m) => m.id.equals(id))).go();
        await db.syncOutboxDao.enqueue(
            targetTable: 'project_members', recordId: id, operation: 'delete', payloadJson: jsonEncode({'id': id}));
      });

  Future<void> _queueMember(ProjectMember row, String operation) => db.syncOutboxDao.enqueue(
        targetTable: 'project_members',
        recordId: row.id,
        operation: operation,
        payloadJson: jsonEncode(projectMemberToSupabaseJson(row)),
      );

  Future<bool> isMembersOnly(String projectId) async =>
      (await (select(siteAccess)..where((a) => a.id.equals(projectId))).getSingleOrNull())?.membersOnly ?? false;

  Future<Set<String>> membersOnlySites(Iterable<String> projectIds) async {
    final ids = projectIds.toList();
    if (ids.isEmpty) return const {};
    final rows = await (select(siteAccess)..where((a) => a.id.isIn(ids) & a.membersOnly.equals(true))).get();
    return {for (final r in rows) r.id};
  }

  Future<void> setMembersOnly(String projectId, bool membersOnly, {DateTime? now}) => transaction(() async {
        final existed = await (select(siteAccess)..where((a) => a.id.equals(projectId))).getSingleOrNull();
        await into(siteAccess).insertOnConflictUpdate(SiteAccessCompanion.insert(
          id: projectId,
          projectId: projectId,
          membersOnly: Value(membersOnly),
          updatedAt: Value(now ?? DateTime.now()),
        ));
        final row = await (select(siteAccess)..where((a) => a.id.equals(projectId))).getSingle();
        await db.syncOutboxDao.enqueue(
          targetTable: 'site_access',
          recordId: projectId,
          operation: existed == null ? 'insert' : 'update',
          payloadJson: jsonEncode(siteAccessToSupabaseJson(row)),
        );
      });

  /// One row per person per site: a server row replaces a local one for
  /// the same person made with another id (both phones added them).
  Future<void> upsertMemberFromRemote(ProjectMembersCompanion c) => transaction(() async {
        await (delete(projectMembers)
              ..where((m) =>
                  m.projectId.equals(c.projectId.value) & m.userId.equals(c.userId.value) & m.id.equals(c.id.value).not()))
            .go();
        await into(projectMembers).insertOnConflictUpdate(c);
      });
  Future<void> upsertAccessFromRemote(SiteAccessCompanion c) => into(siteAccess).insertOnConflictUpdate(c);
}

// ---------------------------------------------------------------------------
// Measurement to billing, and reconciliation (v18)
// ---------------------------------------------------------------------------

/// Thrown when an allocation would pay more than the payment has left, or
/// more than the bill or its retention needs. The server refuses the same.
class AllocationTooBig implements Exception {
  const AllocationTooBig(this.message);
  final String message;
  @override
  String toString() => message;
}

@DriftAccessor(tables: [WorkMeasurements, WorkMeasurementDecisions, BillAllocations, SupplierInvoices, ClientBills, PaymentsReceived])
class BillingRecordsDao extends DatabaseAccessor<AppDatabase> with _$BillingRecordsDaoMixin {
  BillingRecordsDao(super.db);

  // Measurement book

  Future<WorkMeasurement> measure({
    required String projectId,
    String? costHeadId,
    required String description,
    required String unit,
    double? rate,
    required double qty,
    required DateTime on,
    required String by,
    String? location,
    String? note,
  }) {
    if (qty == 0 || !qty.isFinite) throw ArgumentError.value(qty, 'qty');
    if (description.trim().isEmpty || unit.trim().isEmpty) throw ArgumentError('Say what was measured, and its unit.');
    return transaction(() async {
      final row = await into(workMeasurements).insertReturning(WorkMeasurementsCompanion.insert(
        id: _uuid.v4(),
        projectId: projectId,
        costHeadId: Value(costHeadId),
        description: _clip(description.trim(), 200)!,
        unit: _clip(unit.trim(), 20)!,
        rate: Value(rate),
        qty: qty,
        measuredOn: DateTime(on.year, on.month, on.day),
        location: Value(_clip(location, 200)),
        note: Value(_clip(note, 300)),
        measuredBy: by,
      ));
      await db.syncOutboxDao.enqueue(
          targetTable: 'site_work_measurements',
          recordId: row.id,
          operation: 'insert',
          payloadJson: jsonEncode(workMeasurementToSupabaseJson(row)));
      return row;
    });
  }

  /// Approves (all or part of) a measurement, or rejects it. One decision
  /// per measurement.
  Future<WorkMeasurementDecision> decide(String measurementId,
      {required bool approve, double? approvedQty, required String by, String? note}) {
    return transaction(() async {
      final m = await (select(workMeasurements)..where((w) => w.id.equals(measurementId))).getSingle();
      final existing =
          await (select(workMeasurementDecisions)..where((d) => d.measurementId.equals(measurementId))).getSingleOrNull();
      if (existing != null) throw StateError('This measurement has been decided already.');
      final qty = approve ? (approvedQty ?? m.qty) : null;
      if (qty != null && (qty.sign != m.qty.sign || qty.abs() > m.qty.abs() + 1e-9)) {
        throw ArgumentError('The approved quantity must be between zero and what was measured.');
      }
      final row = await into(workMeasurementDecisions).insertReturning(WorkMeasurementDecisionsCompanion.insert(
        id: _uuid.v4(),
        projectId: m.projectId,
        measurementId: m.id,
        decision: approve ? 'approved' : 'rejected',
        approvedQty: Value(qty),
        note: Value(_clip(note, 300)),
        decidedBy: by,
      ));
      await db.syncOutboxDao.enqueue(
          targetTable: 'site_work_measurement_decisions',
          recordId: row.id,
          operation: 'insert',
          payloadJson: jsonEncode(measurementDecisionToSupabaseJson(row)));
      return row;
    });
  }

  Future<List<WorkMeasurement>> measurementsFor(String projectId) => (select(workMeasurements)
        ..where((m) => m.projectId.equals(projectId))
        ..orderBy([(m) => OrderingTerm.asc(m.measuredOn), (m) => OrderingTerm.asc(m.createdAt)]))
      .get();

  Future<Map<String, WorkMeasurementDecision>> decisionsFor(String projectId) async => {
        for (final d in await (select(workMeasurementDecisions)..where((d) => d.projectId.equals(projectId))).get())
          d.measurementId: d,
      };

  // Payments against bills

  Future<List<BillAllocation>> allocationsFor(String projectId) =>
      (select(billAllocations)..where((a) => a.projectId.equals(projectId))).get();

  /// Puts [amount] of [paymentId] against [billId] (its net amount, or its
  /// retention). Marks the bill paid when its net amount is covered.
  Future<BillAllocation> allocate(
      {required String paymentId, required String billId, String kind = 'bill', required double amount, required String by, String? note}) {
    if (!(amount > 0)) throw ArgumentError.value(amount, 'amount');
    if (kind != 'bill' && kind != 'retention') throw ArgumentError.value(kind, 'kind');
    return transaction(() async {
      final p = await (select(paymentsReceived)..where((x) => x.id.equals(paymentId))).getSingle();
      final b = await (select(clientBills)..where((x) => x.id.equals(billId))).getSingle();
      if (p.projectId != b.projectId) throw ArgumentError('The payment and the bill are on different sites.');
      if (p.voided) throw const AllocationTooBig('A cancelled payment pays nothing.');
      final all = await allocationsFor(p.projectId);
      double used(bool Function(BillAllocation) f) => all.where(f).fold(0.0, (s, a) => s + a.amount);
      final left = p.amount - used((a) => a.paymentId == paymentId);
      if (amount > left + 0.005) throw AllocationTooBig('Only ${left.toStringAsFixed(2)} of this payment is left.');
      final need = kind == 'bill'
          ? b.netPayable - used((a) => a.billId == billId && a.kind == 'bill')
          : _round2(b.gross * b.retentionPct / 100) - used((a) => a.billId == billId && a.kind == 'retention');
      if (amount > need + 0.005) throw AllocationTooBig('Only ${need.toStringAsFixed(2)} is still due on this.');
      final row = await into(billAllocations).insertReturning(BillAllocationsCompanion.insert(
        id: _uuid.v4(),
        projectId: p.projectId,
        paymentId: paymentId,
        billId: billId,
        kind: Value(kind),
        amount: _round2(amount),
        note: Value(_clip(note, 300)),
        createdBy: by,
      ));
      await db.syncOutboxDao.enqueue(
          targetTable: 'site_bill_allocations',
          recordId: row.id,
          operation: 'insert',
          payloadJson: jsonEncode(billAllocationToSupabaseJson(row)));
      if (kind == 'bill' && need - amount <= 0.005 && b.status != 'paid') await db.billDao.setStatus(billId, 'paid');
      return row;
    });
  }

  /// Takes an allocation back; a bill no longer covered is unpaid again.
  Future<void> removeAllocation(String id) => transaction(() async {
        final a = await (select(billAllocations)..where((x) => x.id.equals(id))).getSingleOrNull();
        if (a == null) return;
        await (delete(billAllocations)..where((x) => x.id.equals(id))).go();
        await db.syncOutboxDao.enqueue(
            targetTable: 'site_bill_allocations', recordId: id, operation: 'delete', payloadJson: jsonEncode({'id': id}));
        final b = await (select(clientBills)..where((x) => x.id.equals(a.billId))).getSingleOrNull();
        if (a.kind == 'bill' && b != null && b.status == 'paid') await db.billDao.setStatus(b.id, 'issued');
      });

  // Supplier invoices

  Future<SupplierInvoice> recordSupplierInvoice(SupplierInvoicesCompanion c) => transaction(() async {
        final row = await into(supplierInvoices)
            .insertReturning(c.copyWith(id: c.id.present ? c.id : Value(_uuid.v4())));
        await db.syncOutboxDao.enqueue(
            targetTable: 'site_supplier_invoices',
            recordId: row.id,
            operation: 'insert',
            payloadJson: jsonEncode(supplierInvoiceToSupabaseJson(row)));
        return row;
      });

  Future<void> voidSupplierInvoice(String id, String reason) {
    if (reason.trim().isEmpty) throw ArgumentError('Say why the invoice is cancelled.');
    return transaction(() async {
      await (update(supplierInvoices)..where((i) => i.id.equals(id)))
          .write(SupplierInvoicesCompanion(voided: const Value(true), voidReason: Value(_clip(reason.trim(), 200))));
      final row = await (select(supplierInvoices)..where((i) => i.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
          targetTable: 'site_supplier_invoices',
          recordId: id,
          operation: 'update',
          payloadJson: jsonEncode(supplierInvoiceToSupabaseJson(row)));
    });
  }

  Future<List<SupplierInvoice>> supplierInvoicesFor(String projectId) => (select(supplierInvoices)
        ..where((i) => i.projectId.equals(projectId))
        ..orderBy([(i) => OrderingTerm.desc(i.invoiceDate), (i) => OrderingTerm.desc(i.createdAt)]))
      .get();

  Future<void> upsertMeasurementFromRemote(WorkMeasurementsCompanion c) => into(workMeasurements).insertOnConflictUpdate(c);
  Future<void> upsertDecisionFromRemote(WorkMeasurementDecisionsCompanion c) =>
      into(workMeasurementDecisions).insertOnConflictUpdate(c);
  Future<void> upsertAllocationFromRemote(BillAllocationsCompanion c) => into(billAllocations).insertOnConflictUpdate(c);
  Future<void> upsertSupplierInvoiceFromRemote(SupplierInvoicesCompanion c) =>
      into(supplierInvoices).insertOnConflictUpdate(c);
}

double _round2(double v) => (v * 100).roundToDouble() / 100;

/// Multi-level approvals by amount (v30): the owner's rules, and the
/// signatures on each item. What a chain needs is worked out in
/// lib/features/approvals/approval_chain.dart.
@DriftAccessor(tables: [ApprovalRules, ApprovalSteps])
class ApprovalChainDao extends DatabaseAccessor<AppDatabase> with _$ApprovalChainDaoMixin {
  ApprovalChainDao(super.db);

  Future<List<ApprovalRule>> rulesFor(String companyId) => (select(approvalRules)
        ..where((r) => r.companyId.equals(companyId) & r.voided.equals(false))
        ..orderBy([(r) => OrderingTerm.asc(r.kind), (r) => OrderingTerm.asc(r.aboveAmount)]))
      .get();

  /// Sets the amount above which [kind] needs [role]; null removes the
  /// rule. One live rule per kind and level.
  Future<void> setRule(String companyId, {required String kind, required String role, double? above, required String by}) =>
      transaction(() async {
        if (above != null && (above < 0 || !above.isFinite)) throw ArgumentError.value(above, 'above');
        final live = await (select(approvalRules)
              ..where((r) =>
                  r.companyId.equals(companyId) & r.kind.equals(kind) & r.role.equals(role) & r.voided.equals(false)))
            .get();
        for (final (i, r) in live.indexed) {
          final keep = i == 0 && above != null;
          final row = r.copyWith(aboveAmount: keep ? _round2(above) : r.aboveAmount, voided: !keep, updatedAt: DateTime.now());
          if (row == r) continue;
          await update(approvalRules).replace(row);
          await db.syncOutboxDao.enqueue(
              targetTable: 'site_approval_rules',
              recordId: row.id,
              operation: 'update',
              payloadJson: jsonEncode(approvalRuleToSupabaseJson(row)));
        }
        if (live.isEmpty && above != null) {
          final row = await into(approvalRules).insertReturning(ApprovalRulesCompanion.insert(
              id: _uuid.v4(), companyId: companyId, kind: kind, role: role, aboveAmount: _round2(above), createdBy: by));
          await db.syncOutboxDao.enqueue(
              targetTable: 'site_approval_rules',
              recordId: row.id,
              operation: 'insert',
              payloadJson: jsonEncode(approvalRuleToSupabaseJson(row)));
        }
      });

  Future<List<ApprovalStep>> stepsFor(String projectId) =>
      (select(approvalSteps)..where((s) => s.projectId.equals(projectId))..orderBy([(s) => OrderingTerm.asc(s.createdAt)])).get();

  Future<List<ApprovalStep>> stepsForItem(String kind, String itemId) => (select(approvalSteps)
        ..where((s) => s.kind.equals(kind) & s.itemId.equals(itemId))
        ..orderBy([(s) => OrderingTerm.asc(s.createdAt)]))
      .get();

  /// Signs [level] on an item. A person signs each level of an item once.
  Future<ApprovalStep> sign({
    required String projectId,
    required String kind,
    required String itemId,
    required String level,
    required bool approve,
    double? amount,
    required String by,
    String? note,
  }) =>
      transaction(() async {
        final mine = await (select(approvalSteps)
              ..where((s) => s.kind.equals(kind) & s.itemId.equals(itemId) & s.level.equals(level) & s.decidedBy.equals(by)))
            .getSingleOrNull();
        if (mine != null) return mine;
        final row = await into(approvalSteps).insertReturning(ApprovalStepsCompanion.insert(
          id: _uuid.v4(),
          projectId: projectId,
          kind: kind,
          itemId: itemId,
          level: level,
          decision: approve ? 'approved' : 'rejected',
          amount: Value(amount),
          note: Value(_clip(note, 300)),
          decidedBy: by,
        ));
        await db.syncOutboxDao.enqueue(
            targetTable: 'site_approval_steps',
            recordId: row.id,
            operation: 'insert',
            payloadJson: jsonEncode(approvalStepToSupabaseJson(row)));
        return row;
      });

  Future<void> upsertRuleFromRemote(ApprovalRulesCompanion c) => into(approvalRules).insertOnConflictUpdate(c);
  Future<void> upsertStepFromRemote(ApprovalStepsCompanion c) => into(approvalSteps).insertOnConflictUpdate(c);
}

/// The roles a person can have on one site.
const siteRoleValues = ['owner', 'project_manager', 'site_engineer', 'accounts', 'storekeeper', 'viewer'];

// ---------------------------------------------------------------------------
// CRM (v21): leads, their history and quotations. Company-wide; the server
// lets only the owner and project managers read or write them
// (supabase/migrations/20261110400000_crm.sql). Rules in
// features/crm/crm_rules.dart.
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [CrmLeads, CrmActivities, CrmQuotes])
class CrmDao extends DatabaseAccessor<AppDatabase> with _$CrmDaoMixin {
  CrmDao(super.db);

  Future<void> _queue(String table, String id, String op, Map<String, dynamic> json) =>
      db.syncOutboxDao.enqueue(targetTable: table, recordId: id, operation: op, payloadJson: jsonEncode(json));

  Future<List<CrmLead>> leadsFor(String companyId) => (select(crmLeads)
        ..where((l) => l.companyId.equals(companyId))
        ..orderBy([(l) => OrderingTerm.desc(l.updatedAt)]))
      .get();

  Future<CrmLead?> leadById(String id) => (select(crmLeads)..where((l) => l.id.equals(id))).getSingleOrNull();

  Future<List<CrmActivity>> activitiesFor(String leadId) => (select(crmActivities)
        ..where((a) => a.leadId.equals(leadId))
        ..orderBy([(a) => OrderingTerm.desc(a.createdAt), (a) => OrderingTerm.desc(a.rowId)]))
      .get();

  Future<List<CrmQuote>> quotesFor(String companyId) => (select(crmQuotes)
        ..where((q) => q.companyId.equals(companyId))
        ..orderBy([(q) => OrderingTerm.desc(q.quoteDate), (q) => OrderingTerm.desc(q.createdAt)]))
      .get();

  Future<List<CrmQuote>> quotesForLead(String leadId) => (select(crmQuotes)
        ..where((q) => q.leadId.equals(leadId))
        ..orderBy([(q) => OrderingTerm.desc(q.quoteDate), (q) => OrderingTerm.desc(q.createdAt)]))
      .get();

  Future<CrmQuote?> quoteById(String id) => (select(crmQuotes)..where((q) => q.id.equals(id))).getSingleOrNull();

  Future<CrmLead> addLead({
    required String companyId,
    required String name,
    required String by,
    String? phone,
    String? email,
    String? location,
    String source = 'other',
    String? workType,
    double? estimatedValue,
    DateTime? nextFollowUp,
    String? notes,
    String? ownerId,
  }) {
    if (name.trim().isEmpty) throw ArgumentError('Enter who the enquiry is from.');
    return transaction(() async {
      final row = await into(crmLeads).insertReturning(CrmLeadsCompanion.insert(
        id: _uuid.v4(),
        companyId: companyId,
        name: _clip(name.trim(), 200)!,
        phone: Value(_blank(phone, 30)),
        email: Value(_blank(email, 120)),
        location: Value(_blank(location, 300)),
        source: Value(leadSources.contains(source) ? source : 'other'),
        workType: Value(_blank(workType, 200)),
        estimatedValue: Value(estimatedValue),
        nextFollowUp: Value(nextFollowUp),
        notes: Value(_blank(notes, 1000)),
        ownerId: Value(ownerId ?? by),
        createdBy: by,
      ));
      await _queue('crm_leads', row.id, 'insert', crmLeadToSupabaseJson(row));
      return row;
    });
  }

  Future<CrmLead> updateLead(
    String id, {
    String? name,
    Value<String?> phone = const Value.absent(),
    Value<String?> email = const Value.absent(),
    Value<String?> location = const Value.absent(),
    String? source,
    Value<String?> workType = const Value.absent(),
    Value<double?> estimatedValue = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<String?> ownerId = const Value.absent(),
  }) =>
      transaction(() async {
        String? b(Value<String?> v, int max) => _blank(v.value, max);
        await (update(crmLeads)..where((l) => l.id.equals(id))).write(CrmLeadsCompanion(
          name: name == null || name.trim().isEmpty ? const Value.absent() : Value(_clip(name.trim(), 200)!),
          phone: phone.present ? Value(b(phone, 30)) : const Value.absent(),
          email: email.present ? Value(b(email, 120)) : const Value.absent(),
          location: location.present ? Value(b(location, 300)) : const Value.absent(),
          source: source != null && leadSources.contains(source) ? Value(source) : const Value.absent(),
          workType: workType.present ? Value(b(workType, 200)) : const Value.absent(),
          estimatedValue: estimatedValue,
          notes: notes.present ? Value(b(notes, 1000)) : const Value.absent(),
          ownerId: ownerId,
          updatedAt: Value(DateTime.now()),
        ));
        return _pushLead(id);
      });

  Future<CrmLead> _pushLead(String id) async {
    final row = await (select(crmLeads)..where((l) => l.id.equals(id))).getSingle();
    await _queue('crm_leads', id, 'update', crmLeadToSupabaseJson(row));
    return row;
  }

  /// Moves a lead along. Lost needs a reason (that is the point of
  /// tracking it); every move is written to the lead's history.
  Future<CrmLead> setStage(String id, String stage, {required String by, String? lostReason, DateTime? now}) {
    if (!leadStages.contains(stage)) throw ArgumentError.value(stage, 'stage');
    if (stage == 'lost' && (lostReason ?? '').trim().isEmpty) {
      throw ArgumentError('Say why it was lost, so the next one is not.');
    }
    return transaction(() async {
      final before = await leadById(id);
      if (before == null) throw StateError('This lead is no longer on the phone.');
      if (before.stage == stage) return before;
      final at = now ?? DateTime.now();
      await (update(crmLeads)..where((l) => l.id.equals(id))).write(CrmLeadsCompanion(
        stage: Value(stage),
        lostReason: Value(stage == 'lost' ? _clip(lostReason!.trim(), 300) : null),
        // Nothing to follow up on a decided lead.
        nextFollowUp: isOpenStage(stage) ? const Value.absent() : const Value(null),
        updatedAt: Value(at),
      ));
      final note = stage == 'lost'
          ? '${leadStageLabels[before.stage]} -> ${leadStageLabels[stage]}: ${lostReason!.trim()}'
          : '${leadStageLabels[before.stage]} -> ${leadStageLabels[stage]}';
      await _addActivity(before.companyId, id, 'stage', note, by, at);
      return _pushLead(id);
    });
  }

  Future<CrmLead> setFollowUp(String id, DateTime? when) => transaction(() async {
        await (update(crmLeads)..where((l) => l.id.equals(id)))
            .write(CrmLeadsCompanion(nextFollowUp: Value(when), updatedAt: Value(DateTime.now())));
        return _pushLead(id);
      });

  /// Logs a call, visit or note and (optionally) sets the next follow-up
  /// in one go, the way it happens on the phone after a call. A first
  /// contact moves a new lead to contacted.
  Future<void> logActivity({
    required String leadId,
    required String kind,
    required String note,
    required String by,
    DateTime? nextFollowUp,
    bool clearFollowUp = false,
    DateTime? now,
  }) {
    if (!activityKinds.contains(kind)) throw ArgumentError.value(kind, 'kind');
    if (note.trim().isEmpty) throw ArgumentError('Write what was said or agreed.');
    return transaction(() async {
      final lead = await leadById(leadId);
      if (lead == null) throw StateError('This lead is no longer on the phone.');
      final at = now ?? DateTime.now();
      await _addActivity(lead.companyId, leadId, kind, note.trim(), by, at);
      final moveOn = lead.stage == 'new' && kind != 'note';
      await (update(crmLeads)..where((l) => l.id.equals(leadId))).write(CrmLeadsCompanion(
        stage: moveOn ? Value(kind == 'visit' ? 'site_visit' : 'contacted') : const Value.absent(),
        nextFollowUp: nextFollowUp != null
            ? Value(nextFollowUp)
            : clearFollowUp
                ? const Value(null)
                : const Value.absent(),
        updatedAt: Value(at),
      ));
      await _pushLead(leadId);
    });
  }

  Future<void> _addActivity(String companyId, String leadId, String kind, String note, String by, DateTime at) async {
    final row = await into(crmActivities).insertReturning(CrmActivitiesCompanion.insert(
      id: _uuid.v4(),
      companyId: companyId,
      leadId: leadId,
      kind: kind,
      note: _clip(note, 1000)!,
      byUser: by,
      createdAt: Value(at),
    ));
    await _queue('crm_activities', row.id, 'insert', crmActivityToSupabaseJson(row));
  }

  /// A new quote, or a change to one. The total is worked out here so the
  /// list and the pipeline always agree with the PDF.
  Future<CrmQuote> saveQuote({
    String? id,
    required String leadId,
    required List<BillLine> lines,
    required String by,
    double gstRate = 18,
    bool interState = false,
    double discount = 0,
    DateTime? quoteDate,
    DateTime? validUntil,
    String? terms,
  }) {
    final clean = [for (final l in lines) if (l.description.trim().isNotEmpty) l];
    if (clean.isEmpty) throw ArgumentError('Add at least one item with a description.');
    if (clean.any((l) => l.qty < 0 || l.rate < 0)) throw ArgumentError('Quantities and rates cannot be negative.');
    if (gstRate < 0 || gstRate > 28) throw ArgumentError('GST is between 0 and 28%.');
    final totals = quoteTotals(clean, discount: discount, gstRate: gstRate, interState: interState);
    return transaction(() async {
      final lead = await leadById(leadId);
      if (lead == null) throw StateError('This lead is no longer on the phone.');
      final date = quoteDate ?? DateTime.now();
      if (id == null) {
        final existing = (await quotesFor(lead.companyId)).map((q) => q.quoteNumber);
        final row = await into(crmQuotes).insertReturning(CrmQuotesCompanion.insert(
          id: _uuid.v4(),
          companyId: lead.companyId,
          leadId: leadId,
          quoteNumber: nextQuoteNumber(existing, date),
          quoteDate: date,
          validUntil: Value(validUntil),
          linesJson: Value(encodeLines(clean)),
          gstRate: Value(gstRate),
          interState: Value(interState),
          discount: Value(totals.discount),
          total: Value(totals.total),
          terms: Value(_blank(terms, 2000)),
          createdBy: by,
        ));
        await _queue('crm_quotes', row.id, 'insert', crmQuoteToSupabaseJson(row));
        if (const ['new', 'contacted', 'site_visit'].contains(lead.stage)) {
          await (update(crmLeads)..where((l) => l.id.equals(leadId)))
              .write(CrmLeadsCompanion(stage: const Value('quoted'), updatedAt: Value(DateTime.now())));
          await _addActivity(lead.companyId, leadId, 'stage',
              '${leadStageLabels[lead.stage]} -> ${leadStageLabels['quoted']}: ${row.quoteNumber}', by, DateTime.now());
          await _pushLead(leadId);
        }
        return row;
      }
      final before = await quoteById(id);
      if (before == null) throw StateError('This quote is no longer on the phone.');
      if (before.status == 'accepted') throw ArgumentError('An accepted quote is not changed. Make a new one.');
      await (update(crmQuotes)..where((q) => q.id.equals(id))).write(CrmQuotesCompanion(
        quoteDate: Value(date),
        validUntil: Value(validUntil),
        linesJson: Value(encodeLines(clean)),
        gstRate: Value(gstRate),
        interState: Value(interState),
        discount: Value(totals.discount),
        total: Value(totals.total),
        terms: Value(_blank(terms, 2000)),
        updatedAt: Value(DateTime.now()),
      ));
      final row = await (select(crmQuotes)..where((q) => q.id.equals(id))).getSingle();
      await _queue('crm_quotes', id, 'update', crmQuoteToSupabaseJson(row));
      return row;
    });
  }

  Future<CrmQuote> setQuoteStatus(String id, String status, {required String by}) {
    if (!quoteStatuses.contains(status)) throw ArgumentError.value(status, 'status');
    return transaction(() async {
      final q = await quoteById(id);
      if (q == null) throw StateError('This quote is no longer on the phone.');
      await (update(crmQuotes)..where((x) => x.id.equals(id)))
          .write(CrmQuotesCompanion(status: Value(status), updatedAt: Value(DateTime.now())));
      final row = await (select(crmQuotes)..where((x) => x.id.equals(id))).getSingle();
      await _queue('crm_quotes', id, 'update', crmQuoteToSupabaseJson(row));
      await _addActivity(q.companyId, q.leadId, 'stage',
          '${q.quoteNumber}: ${quoteStatusLabels[q.status]} -> ${quoteStatusLabels[status]}', by, DateTime.now());
      return row;
    });
  }

  Future<void> deleteQuote(String id) => transaction(() async {
        final q = await quoteById(id);
        if (q == null) return;
        if (q.status == 'accepted') throw ArgumentError('An accepted quote is kept with the site it became.');
        await (delete(crmQuotes)..where((x) => x.id.equals(id))).go();
        await _queue('crm_quotes', id, 'delete', {'id': id});
      });

  /// Won: makes the site with the client's name, puts the accepted quote's
  /// items on it as budget lines, and links the lead to it. One
  /// transaction, so a half-made site never appears.
  Future<Project> convertToSite({
    required String leadId,
    required String siteName,
    required String by,
    String? quoteId,
    DateTime? now,
  }) =>
      transaction(() async {
        final lead = await leadById(leadId);
        if (lead == null) throw StateError('This lead is no longer on the phone.');
        if (lead.projectId != null) {
          final existing = await db.projectDao.byId(lead.projectId!);
          if (existing != null) return existing;
        }
        final name = siteName.trim().isEmpty ? lead.name : siteName.trim();
        final project = await db.projectDao.create(ProjectsCompanion.insert(
          id: _uuid.v4(),
          companyId: lead.companyId,
          name: _clip(name, 200)!,
          clientName: Value(_clip(lead.name, 200)),
          status: const Value('planning'),
        ));
        if (quoteId != null) {
          final q = await quoteById(quoteId);
          if (q != null) {
            if (q.status != 'accepted') await setQuoteStatus(q.id, 'accepted', by: by);
            for (final b in budgetLinesFromQuote(decodeQuoteLines(q.linesJson))) {
              await db.commercialDao
                  .addCostCode(projectId: project.id, code: b.code, name: _clip(b.name, 200)!, originalBudget: b.budget);
            }
          }
        }
        final at = now ?? DateTime.now();
        await (update(crmLeads)..where((l) => l.id.equals(leadId))).write(CrmLeadsCompanion(
          stage: const Value('won'),
          projectId: Value(project.id),
          nextFollowUp: const Value(null),
          lostReason: const Value(null),
          updatedAt: Value(at),
        ));
        await _addActivity(lead.companyId, leadId, 'stage',
            '${leadStageLabels[lead.stage]} -> ${leadStageLabels['won']}: ${project.name}', by, at);
        await _pushLead(leadId);
        return project;
      });

  Future<void> deleteLead(String id) => transaction(() async {
        final lead = await leadById(id);
        if (lead == null) return;
        if (lead.projectId != null) throw ArgumentError('A won lead is kept: it is where the site came from.');
        await (delete(crmActivities)..where((a) => a.leadId.equals(id))).go();
        await (delete(crmQuotes)..where((q) => q.leadId.equals(id))).go();
        await (delete(crmLeads)..where((l) => l.id.equals(id))).go();
        // The server removes the history and quotes with the lead.
        await _queue('crm_leads', id, 'delete', {'id': id});
      });

  Future<void> upsertLeadFromRemote(CrmLeadsCompanion c) => into(crmLeads).insertOnConflictUpdate(c);
  Future<void> upsertActivityFromRemote(CrmActivitiesCompanion c) => into(crmActivities).insertOnConflictUpdate(c);
  Future<void> upsertQuoteFromRemote(CrmQuotesCompanion c) => into(crmQuotes).insertOnConflictUpdate(c);
}

String? _blank(String? s, int max) {
  final t = s?.trim() ?? '';
  return t.isEmpty ? null : _clip(t, max);
}

/// Company stores, stock moves between stores and sites, and the tools
/// register.
@DriftAccessor(tables: [Stores, StockMoves, Tools, ToolIssues])
class WarehouseDao extends DatabaseAccessor<AppDatabase> with _$WarehouseDaoMixin {
  WarehouseDao(super.db);

  Future<void> _queue(String table, String id, String op, Map<String, dynamic> json) =>
      db.syncOutboxDao.enqueue(targetTable: table, recordId: id, operation: op, payloadJson: jsonEncode(json));

  // --- Stores -----------------------------------------------------------------

  Future<List<Store>> storesFor(String companyId, {bool includeArchived = false}) => (select(stores)
        ..where((s) => s.companyId.equals(companyId) & (includeArchived ? const Constant(true) : s.archived.equals(false)))
        ..orderBy([(s) => OrderingTerm.asc(s.name)]))
      .get();

  Future<Store?> storeById(String id) => (select(stores)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<Store> addStore({required String companyId, required String name, required String by, String? location}) async {
    if (name.trim().isEmpty) throw ArgumentError('Enter the store name.');
    return transaction(() async {
      final row = await into(stores).insertReturning(StoresCompanion.insert(
        id: _uuid.v4(),
        companyId: companyId,
        name: _clip(name, 120)!,
        location: Value(_blankW(location, 300)),
        createdBy: by,
      ));
      await _queue('stores', row.id, 'insert', storeToSupabaseJson(row));
      return row;
    });
  }

  Future<void> updateStore(String id, {required String name, String? location, bool? archived}) =>
      transaction(() async {
        if (name.trim().isEmpty) throw ArgumentError('Enter the store name.');
        await (update(stores)..where((s) => s.id.equals(id))).write(StoresCompanion(
          name: Value(_clip(name, 120)!),
          location: Value(_blankW(location, 300)),
          archived: archived == null ? const Value.absent() : Value(archived),
        ));
        final row = await storeById(id);
        if (row != null) await _queue('stores', id, 'update', storeToSupabaseJson(row));
      });

  // --- Stock moves --------------------------------------------------------------

  Future<List<StockMove>> movesFor(String companyId) => (select(stockMoves)
        ..where((m) => m.companyId.equals(companyId))
        ..orderBy([(m) => OrderingTerm.desc(m.sentOn), (m) => OrderingTerm.desc(m.createdAt)]))
      .get();

  /// Moves into or out of one site, for its stock tab.
  Future<List<StockMove>> movesForSite(String projectId) => (select(stockMoves)
        ..where((m) => m.fromProjectId.equals(projectId) | m.toProjectId.equals(projectId))
        ..orderBy([(m) => OrderingTerm.desc(m.sentOn), (m) => OrderingTerm.desc(m.createdAt)]))
      .get();

  Future<StockMove?> moveById(String id) => (select(stockMoves)..where((m) => m.id.equals(id))).getSingleOrNull();

  /// Saves a move after [checkMove]. Material bought into a store and count
  /// corrections are done at once; a transfer is on the way until counted
  /// at the other end. A transfer out of a store is priced at the store's
  /// average rate when no rate is given, and cannot send more than the
  /// store holds.
  Future<StockMove> addMove({
    required String companyId,
    required String kind,
    required String materialName,
    required double quantity,
    required String by,
    String? unit,
    String? fromStoreId,
    String? fromProjectId,
    String? toStoreId,
    String? toProjectId,
    String? supplierName,
    double? rate,
    String? vehicle,
    String? note,
    DateTime? on,
  }) async {
    final problem = checkMove(
      kind: kind,
      fromStoreId: fromStoreId,
      fromProjectId: fromProjectId,
      toStoreId: toStoreId,
      toProjectId: toProjectId,
      materialName: materialName,
      quantity: quantity,
      note: note,
    );
    if (problem != null) throw ArgumentError(problem);
    if (rate != null && rate < 0) throw ArgumentError('A rate is not below zero.');
    return transaction(() async {
      var r = rate;
      if (fromStoreId != null) {
        final all = await movesFor(companyId);
        final have = storeBalance(all, fromStoreId, materialName, unit);
        if (quantity > have + 1e-9) {
          throw ArgumentError(trf('The store has only {qty} of this.', {'qty': fmtQty(have < 0 ? 0 : have)}));
        }
        r ??= storeRate(all, fromStoreId, materialName, unit);
      }
      final now = on ?? DateTime.now();
      final row = await into(stockMoves).insertReturning(StockMovesCompanion.insert(
        id: _uuid.v4(),
        companyId: companyId,
        kind: kind,
        fromStoreId: Value(fromStoreId),
        fromProjectId: Value(fromProjectId),
        toStoreId: Value(toStoreId),
        toProjectId: Value(toProjectId),
        supplierName: Value(kind == 'inward' ? _blankW(supplierName, 120) : null),
        materialName: _clip(materialName, 200)!,
        unit: Value(_blankW(unit, 20)),
        quantity: quantity,
        rate: Value(r == null ? null : (r * 100).roundToDouble() / 100),
        status: Value(kind == 'transfer' ? 'in_transit' : 'received'),
        receivedQty: Value(kind == 'transfer' ? null : quantity),
        vehicle: Value(_blankW(vehicle, 40)),
        note: Value(_blankW(note, 300)),
        sentBy: by,
        sentOn: now,
        receivedBy: Value(kind == 'transfer' ? null : by),
        receivedOn: Value(kind == 'transfer' ? null : now),
      ));
      await _queue('stock_moves', row.id, 'insert', stockMoveToSupabaseJson(row));
      return row;
    });
  }

  /// The receiving end counts what arrived. [arrived] defaults to all of it;
  /// less is a shortage, kept on the move.
  Future<StockMove> receive(String id, {required String by, double? arrived, String? note, DateTime? on}) =>
      transaction(() async {
        final m = await moveById(id);
        if (m == null) throw ArgumentError('That transfer is no longer here.');
        if (m.status != 'in_transit') throw ArgumentError('This transfer was already closed.');
        final qty = arrived ?? m.quantity;
        if (qty < 0 || qty > m.quantity + 1e-9) throw ArgumentError('Enter what arrived, up to what was sent.');
        final extra = _blankW(note, 300);
        await (update(stockMoves)..where((x) => x.id.equals(id))).write(StockMovesCompanion(
          status: const Value('received'),
          receivedQty: Value(qty),
          receivedBy: Value(by),
          receivedOn: Value(on ?? DateTime.now()),
          note: extra == null ? const Value.absent() : Value(_clip([m.note, extra].whereType<String>().join(' / '), 300)),
        ));
        final row = (await moveById(id))!;
        await _queue('stock_moves', id, 'update', stockMoveToSupabaseJson(row));
        return row;
      });

  /// Calls back a transfer that has not been received. The material is back
  /// with the sender.
  Future<void> cancelMove(String id, {String? reason}) => transaction(() async {
        final m = await moveById(id);
        if (m == null) return;
        if (m.status != 'in_transit') throw ArgumentError('Only a transfer still on the way can be called back.');
        final why = _blankW(reason, 300);
        await (update(stockMoves)..where((x) => x.id.equals(id))).write(StockMovesCompanion(
          status: const Value('cancelled'),
          note: why == null ? const Value.absent() : Value(_clip([m.note, why].whereType<String>().join(' / '), 300)),
        ));
        final row = (await moveById(id))!;
        await _queue('stock_moves', id, 'update', stockMoveToSupabaseJson(row));
      });

  // --- Tools ------------------------------------------------------------------

  Future<List<Tool>> toolsFor(String companyId) => (select(tools)
        ..where((t) => t.companyId.equals(companyId))
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .get();

  Future<Tool?> toolById(String id) => (select(tools)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<ToolIssue>> issuesFor(String companyId) => (select(toolIssues)
        ..where((i) => i.companyId.equals(companyId))
        ..orderBy([(i) => OrderingTerm.desc(i.issuedOn), (i) => OrderingTerm.desc(i.createdAt)]))
      .get();

  Future<List<ToolIssue>> issuesForTool(String toolId) => (select(toolIssues)
        ..where((i) => i.toolId.equals(toolId))
        ..orderBy([(i) => OrderingTerm.desc(i.issuedOn), (i) => OrderingTerm.desc(i.createdAt)]))
      .get();

  Future<ToolIssue?> issueById(String id) => (select(toolIssues)..where((i) => i.id.equals(id))).getSingleOrNull();

  /// Adds a tool; with no code it gets the next asset tag (T-001 ...).
  Future<Tool> addTool({
    required String companyId,
    required String name,
    required String by,
    String? code,
    String? category,
    double? value,
    String? storeId,
    String? notes,
  }) async {
    if (name.trim().isEmpty) throw ArgumentError('Enter the tool name.');
    if (value != null && value < 0) throw ArgumentError('A value is not below zero.');
    return transaction(() async {
      final tag = _blankW(code, 40) ?? nextToolCode(await toolsFor(companyId));
      final row = await into(tools).insertReturning(ToolsCompanion.insert(
        id: _uuid.v4(),
        companyId: companyId,
        name: _clip(name, 120)!,
        code: Value(tag),
        category: Value(_blankW(category, 60)),
        value: Value(value),
        storeId: Value(storeId),
        notes: Value(_blankW(notes, 300)),
        createdBy: by,
      ));
      await _queue('tools', row.id, 'insert', toolToSupabaseJson(row));
      return row;
    });
  }

  Future<void> updateTool(
    String id, {
    required String name,
    String? code,
    String? category,
    double? value,
    String? storeId,
    String? condition,
    String? notes,
  }) =>
      transaction(() async {
        if (name.trim().isEmpty) throw ArgumentError('Enter the tool name.');
        if (condition != null && !toolConditions.contains(condition)) throw ArgumentError('Unknown condition.');
        await (update(tools)..where((t) => t.id.equals(id))).write(ToolsCompanion(
          name: Value(_clip(name, 120)!),
          code: Value(_blankW(code, 40)),
          category: Value(_blankW(category, 60)),
          value: Value(value),
          storeId: Value(storeId),
          condition: condition == null ? const Value.absent() : Value(condition),
          notes: Value(_blankW(notes, 300)),
          updatedAt: Value(DateTime.now()),
        ));
        final row = await toolById(id);
        if (row != null) await _queue('tools', id, 'update', toolToSupabaseJson(row));
      });

  /// Hands a tool to someone, at a site or from the store. A tool already
  /// out, lost or retired is not issued again.
  Future<ToolIssue> issueTool({
    required String toolId,
    required String issuedTo,
    required String by,
    String? projectId,
    String? workerId,
    DateTime? dueBack,
    String? note,
    DateTime? on,
  }) =>
      transaction(() async {
        final t = await toolById(toolId);
        if (t == null) throw ArgumentError('That tool is no longer here.');
        if (issuedTo.trim().isEmpty) throw ArgumentError('Enter who is taking it.');
        final now = on ?? DateTime.now();
        final state = toolState(t, await issuesForTool(toolId), now);
        if (state == ToolState.issued || state == ToolState.overdue) {
          throw ArgumentError('This tool is already out. Take it back first.');
        }
        if (state == ToolState.lost || state == ToolState.retired) throw ArgumentError('This tool is not in use.');
        final row = await into(toolIssues).insertReturning(ToolIssuesCompanion.insert(
          id: _uuid.v4(),
          companyId: t.companyId,
          toolId: toolId,
          projectId: Value(projectId),
          issuedTo: _clip(issuedTo, 120)!,
          workerId: Value(workerId),
          issuedBy: by,
          issuedOn: now,
          dueBack: Value(dueBack),
          note: Value(_blankW(note, 300)),
        ));
        await _queue('tool_issues', row.id, 'insert', toolIssueToSupabaseJson(row));
        return row;
      });

  /// Takes a tool back: fine, damaged (with what to recover) or lost.
  Future<ToolIssue> returnTool(String issueId,
          {required String condition, double? recoverAmount, String? note, DateTime? on}) =>
      transaction(() async {
        final i = await issueById(issueId);
        if (i == null) throw ArgumentError('That issue is no longer here.');
        if (!isOpenIssue(i)) throw ArgumentError('This tool was already taken back.');
        if (!returnConditions.contains(condition)) throw ArgumentError('Unknown condition.');
        if (recoverAmount != null && recoverAmount < 0) throw ArgumentError('An amount is not below zero.');
        final extra = _blankW(note, 300);
        await (update(toolIssues)..where((x) => x.id.equals(issueId))).write(ToolIssuesCompanion(
          returnedOn: Value(condition == 'lost' ? null : (on ?? DateTime.now())),
          returnCondition: Value(condition),
          recoverAmount: Value(condition == 'ok' ? null : recoverAmount),
          note: extra == null ? const Value.absent() : Value(_clip([i.note, extra].whereType<String>().join(' / '), 300)),
        ));
        if (condition == 'damaged') {
          // The server does the same when the return arrives (a site
          // engineer cannot edit the register itself), so nothing is sent.
          await (update(tools)..where((t) => t.id.equals(i.toolId) & t.condition.equals('in_use')))
              .write(ToolsCompanion(condition: const Value('repair'), updatedAt: Value(DateTime.now())));
        }
        final row = (await issueById(issueId))!;
        await _queue('tool_issues', issueId, 'update', toolIssueToSupabaseJson(row));
        return row;
      });

  Future<void> upsertStoreFromRemote(StoresCompanion c) => into(stores).insertOnConflictUpdate(c);
  Future<void> upsertMoveFromRemote(StockMovesCompanion c) => into(stockMoves).insertOnConflictUpdate(c);
  Future<void> upsertToolFromRemote(ToolsCompanion c) => into(tools).insertOnConflictUpdate(c);
  Future<void> upsertIssueFromRemote(ToolIssuesCompanion c) => into(toolIssues).insertOnConflictUpdate(c);
}

/// Monthly salaried staff, their advances and payslips.
@DriftAccessor(tables: [StaffMembers, StaffAdvances, PayrollLines])
class PayrollDao extends DatabaseAccessor<AppDatabase> with _$PayrollDaoMixin {
  PayrollDao(super.db);

  Future<void> _queue(String table, String id, String op, Map<String, dynamic> json) =>
      db.syncOutboxDao.enqueue(targetTable: table, recordId: id, operation: op, payloadJson: jsonEncode(json));

  Future<List<StaffMember>> staffFor(String companyId) => (select(staffMembers)
        ..where((s) => s.companyId.equals(companyId))
        ..orderBy([(s) => OrderingTerm.desc(s.active), (s) => OrderingTerm.asc(s.name)]))
      .get();

  Future<StaffMember?> staffById(String id) => (select(staffMembers)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<List<StaffAdvance>> advancesFor(String companyId) => (select(staffAdvances)
        ..where((a) => a.companyId.equals(companyId))
        ..orderBy([(a) => OrderingTerm.desc(a.givenOn)]))
      .get();

  Future<List<PayrollLine>> linesFor(String companyId) => (select(payrollLines)
        ..where((l) => l.companyId.equals(companyId))
        ..orderBy([(l) => OrderingTerm.desc(l.month)]))
      .get();

  Future<List<PayrollLine>> linesForMonth(String companyId, String month) => (select(payrollLines)
        ..where((l) => l.companyId.equals(companyId) & l.month.equals(month)))
      .get();

  Future<PayrollLine?> lineById(String id) => (select(payrollLines)..where((l) => l.id.equals(id))).getSingleOrNull();

  static void _checkPay(String name, double basic, double hra, double other, String ptState) {
    if (name.trim().isEmpty) throw ArgumentError('Enter the name.');
    if (!(basic > 0)) throw ArgumentError('Enter the monthly basic pay.');
    if (hra < 0 || other < 0) throw ArgumentError('An allowance is not below zero.');
    if (!ptStates.contains(ptState)) throw ArgumentError('Unknown professional tax state.');
  }

  Future<StaffMember> addStaff({
    required String companyId,
    required String name,
    required double basic,
    double hra = 0,
    double otherAllowance = 0,
    bool pf = true,
    bool esi = true,
    String ptState = 'TS',
    String? phone,
    String? designation,
    String? projectId,
    String? uan,
    DateTime? joinedOn,
    String? userId,
  }) async {
    _checkPay(name, basic, hra, otherAllowance, ptState);
    return transaction(() async {
      await _checkLogin(companyId, userId, null);
      final row = await into(staffMembers).insertReturning(StaffMembersCompanion.insert(
        id: _uuid.v4(),
        companyId: companyId,
        name: _clip(name, 120)!,
        phone: Value(_blankW(phone, 30)),
        designation: Value(_blankW(designation, 80)),
        projectId: Value(projectId),
        basic: basic,
        hra: Value(hra),
        otherAllowance: Value(otherAllowance),
        pf: Value(pf),
        esi: Value(esi),
        ptState: Value(ptState),
        uan: Value(_blankW(uan, 20)),
        joinedOn: Value(joinedOn),
        userId: Value(userId),
      ));
      await _queue('staff_members', row.id, 'insert', staffMemberToSupabaseJson(row));
      return row;
    });
  }

  Future<void> updateStaff(
    String id, {
    required String name,
    required double basic,
    double hra = 0,
    double otherAllowance = 0,
    bool pf = true,
    bool esi = true,
    String ptState = 'TS',
    String? phone,
    String? designation,
    String? projectId,
    String? uan,
    DateTime? joinedOn,
    bool active = true,
    Value<String?> userId = const Value.absent(),
  }) =>
      transaction(() async {
        _checkPay(name, basic, hra, otherAllowance, ptState);
        if (userId.present) {
          final s = await staffById(id);
          if (s != null) await _checkLogin(s.companyId, userId.value, id);
        }
        await (update(staffMembers)..where((s) => s.id.equals(id))).write(StaffMembersCompanion(
          name: Value(_clip(name, 120)!),
          phone: Value(_blankW(phone, 30)),
          designation: Value(_blankW(designation, 80)),
          projectId: Value(projectId),
          basic: Value(basic),
          hra: Value(hra),
          otherAllowance: Value(otherAllowance),
          pf: Value(pf),
          esi: Value(esi),
          ptState: Value(ptState),
          uan: Value(_blankW(uan, 20)),
          joinedOn: Value(joinedOn),
          active: Value(active),
          userId: userId,
          updatedAt: Value(DateTime.now()),
        ));
        final row = await staffById(id);
        if (row != null) await _queue('staff_members', id, 'update', staffMemberToSupabaseJson(row));
      });

  /// One salary per login.
  Future<void> _checkLogin(String companyId, String? userId, String? exceptId) async {
    if (userId == null) return;
    for (final o in await staffFor(companyId)) {
      if (o.userId == userId && o.id != exceptId) {
        throw ArgumentError(trf('That login is already linked to {name}.', {'name': o.name}));
      }
    }
  }

  Future<StaffAdvance> giveAdvance(
      {required String staffId, required double amount, required String by, String? note, DateTime? on}) async {
    if (!(amount > 0)) throw ArgumentError('Enter the amount given.');
    return transaction(() async {
      final s = await staffById(staffId);
      if (s == null) throw ArgumentError('That person is no longer here.');
      final row = await into(staffAdvances).insertReturning(StaffAdvancesCompanion.insert(
        id: _uuid.v4(),
        companyId: s.companyId,
        staffId: staffId,
        amount: amount,
        givenOn: on ?? DateTime.now(),
        note: Value(_blankW(note, 200)),
        createdBy: by,
      ));
      await _queue('staff_advances', row.id, 'insert', staffAdvanceToSupabaseJson(row));
      return row;
    });
  }

  Future<double> owedBy(String staffId, {String? exceptLineId}) async {
    final s = await staffById(staffId);
    if (s == null) return 0;
    return advanceOwed(staffId, await advancesFor(s.companyId), await linesFor(s.companyId),
        exceptLineId: exceptLineId);
  }

  /// Makes the month's payslips for every active staff member who has none
  /// yet: the full month paid, and up to the whole advance owed recovered.
  /// Returns how many were made.
  Future<int> makeMonth(String companyId, String month, {required String by}) => transaction(() async {
        final days = daysInMonth(month);
        final have = {for (final l in await linesForMonth(companyId, month)) l.staffId};
        final advances = await advancesFor(companyId);
        final lines = await linesFor(companyId);
        var made = 0;
        for (final s in await staffFor(companyId)) {
          if (!s.active || have.contains(s.id)) continue;
          final joined = s.joinedOn;
          final start = monthStart(month);
          if (joined != null && !joined.isBefore(DateTime(start.year, start.month + 1))) continue;
          // Joined in the month: paid from the day they joined.
          final paidDays = joined != null && joined.year == start.year && joined.month == start.month
              ? (days - joined.day + 1).toDouble()
              : days.toDouble();
          final owed = advanceOwed(s.id, advances, lines);
          final calc = computePay(s, days: days, paidDays: paidDays, advanceWanted: owed, advanceOwed: owed);
          await _insertLine(s, month, calc, by);
          made++;
        }
        return made;
      });

  Future<PayrollLine> _insertLine(StaffMember s, String month, PayCalc c, String by) async {
    final row = await into(payrollLines).insertReturning(PayrollLinesCompanion.insert(
      id: _uuid.v4(),
      companyId: s.companyId,
      staffId: s.id,
      month: month,
      daysInMonth: c.daysInMonth,
      paidDays: c.paidDays,
      basic: c.basic,
      hra: c.hra,
      otherAllowance: c.otherAllowance,
      gross: c.gross,
      pfEmployee: c.pfEmployee,
      esiEmployee: c.esiEmployee,
      pt: c.pt,
      advanceRecovery: c.advanceRecovery,
      otherDeduction: c.otherDeduction,
      net: c.net,
      pfEmployer: c.pfEmployer,
      esiEmployer: c.esiEmployer,
      projectId: Value(s.projectId),
      createdBy: by,
    ));
    await _queue('payroll_lines', row.id, 'insert', payrollLineToSupabaseJson(row));
    return row;
  }

  /// Works a draft payslip out again with new days, recovery or other
  /// deduction (and the person's current salary). A paid one is kept.
  Future<PayrollLine> recalculate(String lineId,
          {required double paidDays, required double advanceRecovery, double otherDeduction = 0}) =>
      transaction(() async {
        final l = await lineById(lineId);
        if (l == null) throw ArgumentError('That payslip is no longer here.');
        if (l.status == 'paid') throw ArgumentError('A paid salary is kept as it was paid.');
        final s = await staffById(l.staffId);
        if (s == null) throw ArgumentError('That person is no longer here.');
        if (paidDays < 0 || paidDays > l.daysInMonth) {
          throw ArgumentError(trf('Paid days are 0 to {n}.', {'n': l.daysInMonth}));
        }
        final owed = await owedBy(s.id, exceptLineId: l.id);
        final c = computePay(s,
            days: l.daysInMonth,
            paidDays: paidDays,
            advanceWanted: advanceRecovery,
            advanceOwed: owed,
            otherDeduction: otherDeduction);
        await (update(payrollLines)..where((x) => x.id.equals(lineId))).write(PayrollLinesCompanion(
          paidDays: Value(c.paidDays),
          basic: Value(c.basic),
          hra: Value(c.hra),
          otherAllowance: Value(c.otherAllowance),
          gross: Value(c.gross),
          pfEmployee: Value(c.pfEmployee),
          esiEmployee: Value(c.esiEmployee),
          pt: Value(c.pt),
          advanceRecovery: Value(c.advanceRecovery),
          otherDeduction: Value(c.otherDeduction),
          net: Value(c.net),
          pfEmployer: Value(c.pfEmployer),
          esiEmployer: Value(c.esiEmployer),
          projectId: Value(s.projectId),
          updatedAt: Value(DateTime.now()),
        ));
        final row = (await lineById(lineId))!;
        await _queue('payroll_lines', lineId, 'update', payrollLineToSupabaseJson(row));
        return row;
      });

  /// Marks a payslip paid. When the person is posted at a site and
  /// [addSiteExpense] is set, the net pay goes in that site's money book
  /// as a salary expense, so the site's spending includes it.
  Future<PayrollLine> markPaid(String lineId,
          {required String mode, required String by, bool addSiteExpense = true, DateTime? on}) =>
      transaction(() async {
        final l = await lineById(lineId);
        if (l == null) throw ArgumentError('That payslip is no longer here.');
        if (l.status == 'paid') return l;
        if (!payModes.containsKey(mode)) throw ArgumentError('Pick how it was paid.');
        final s = await staffById(l.staffId);
        final when = on ?? DateTime.now();
        String? expenseId;
        if (addSiteExpense && l.projectId != null && l.net > 0) {
          final e = await db.expenseDao.create(SiteExpensesCompanion.insert(
            id: _uuid.v4(),
            projectId: l.projectId!,
            category: staffSalaryCategory,
            amount: l.net,
            incurredOn: when.toIso8601String().substring(0, 10),
            recordedBy: by,
            note: Value(_clip(trf('Salary {month}', {'month': l.month}), 300)),
            paidTo: Value(_clip(s?.name, 120)),
            mode: Value(mode),
          ));
          expenseId = e.id;
        }
        await (update(payrollLines)..where((x) => x.id.equals(lineId))).write(PayrollLinesCompanion(
          status: const Value('paid'),
          paidOn: Value(when),
          paidMode: Value(mode),
          expenseId: Value(expenseId),
          updatedAt: Value(DateTime.now()),
        ));
        final row = (await lineById(lineId))!;
        await _queue('payroll_lines', lineId, 'update', payrollLineToSupabaseJson(row));
        return row;
      });

  /// Removes a draft payslip (made by mistake, or the person left). A paid
  /// one is kept.
  Future<void> deleteDraft(String lineId) => transaction(() async {
        final l = await lineById(lineId);
        if (l == null) return;
        if (l.status == 'paid') throw ArgumentError('A paid salary is kept as it was paid.');
        await (delete(payrollLines)..where((x) => x.id.equals(lineId))).go();
        await _queue('payroll_lines', lineId, 'delete', {'id': lineId});
      });

  Future<void> upsertStaffFromRemote(StaffMembersCompanion c) => into(staffMembers).insertOnConflictUpdate(c);
  Future<void> upsertAdvanceFromRemote(StaffAdvancesCompanion c) => into(staffAdvances).insertOnConflictUpdate(c);
  Future<void> upsertLineFromRemote(PayrollLinesCompanion c) => into(payrollLines).insertOnConflictUpdate(c);
}

/// The money-book category for salaries paid from a site.
const staffSalaryCategory = 'Staff salary';

String? _blankW(String? s, int max) {
  final t = s?.trim() ?? '';
  return t.isEmpty ? null : _clip(t, max);
}

/// Supplier quotes for a purchase request, and turning the chosen one into
/// the PO.
@DriftAccessor(tables: [SupplierQuotes, PurchaseRequests, PurchaseOrders])
class SupplierQuoteDao extends DatabaseAccessor<AppDatabase> with _$SupplierQuoteDaoMixin {
  SupplierQuoteDao(super.db);

  Future<void> _queue(String id, String op, SupplierQuote row) => db.syncOutboxDao.enqueue(
      targetTable: 'site_supplier_quotes', recordId: id, operation: op, payloadJson: jsonEncode(supplierQuoteToSupabaseJson(row)));

  Future<List<SupplierQuote>> forRequest(String requestId) => (select(supplierQuotes)
        ..where((q) => q.requestId.equals(requestId))
        ..orderBy([(q) => OrderingTerm.asc(q.createdAt)]))
      .get();

  Future<List<SupplierQuote>> forProject(String projectId) =>
      (select(supplierQuotes)..where((q) => q.projectId.equals(projectId))).get();

  Future<SupplierQuote?> byId(String id) => (select(supplierQuotes)..where((q) => q.id.equals(id))).getSingleOrNull();

  static void _check(double rate, double gstPct, double transport, int? days) {
    if (!(rate > 0)) throw ArgumentError('Enter the rate a unit.');
    if (gstPct < 0 || gstPct > 28) throw ArgumentError('GST is 0 to 28%.');
    if (transport < 0) throw ArgumentError('An amount is not below zero.');
    if (days != null && days < 0) throw ArgumentError('Delivery days are not below zero.');
  }

  /// A supplier's price. A second quote from the same supplier replaces
  /// their first while neither has been decided.
  Future<SupplierQuote> addQuote({
    required String requestId,
    required String supplierId,
    required double rate,
    required String by,
    double gstPct = 18,
    double transport = 0,
    int? deliveryDays,
    String? paymentTerms,
    DateTime? validUntil,
    String? notes,
  }) async {
    _check(rate, gstPct, transport, deliveryDays);
    return transaction(() async {
      final r = await (select(purchaseRequests)..where((x) => x.id.equals(requestId))).getSingleOrNull();
      if (r == null) throw ArgumentError('That purchase request is no longer here.');
      if (r.status != 'pending') throw ArgumentError('This request already has a PO.');
      final same = (await forRequest(requestId)).where((q) => q.supplierId == supplierId && q.status == 'received');
      final values = SupplierQuotesCompanion(
        rate: Value(rate),
        gstPct: Value(gstPct),
        transport: Value(transport),
        deliveryDays: Value(deliveryDays),
        paymentTerms: Value(_blankW(paymentTerms, 120)),
        validUntil: Value(validUntil),
        notes: Value(_blankW(notes, 300)),
      );
      if (same.isNotEmpty) {
        final id = same.first.id;
        await (update(supplierQuotes)..where((q) => q.id.equals(id))).write(values);
        final row = (await byId(id))!;
        await _queue(id, 'update', row);
        return row;
      }
      final row = await into(supplierQuotes).insertReturning(values.copyWith(
        id: Value(_uuid.v4()),
        projectId: Value(r.projectId),
        requestId: Value(requestId),
        supplierId: Value(supplierId),
        createdBy: Value(by),
      ));
      await _queue(row.id, 'insert', row);
      return row;
    });
  }

  Future<void> reject(String quoteId) => transaction(() async {
        final q = await byId(quoteId);
        if (q == null || q.status != 'received') return;
        await (update(supplierQuotes)..where((x) => x.id.equals(quoteId))).write(const SupplierQuotesCompanion(status: Value('rejected')));
        await _queue(quoteId, 'update', (await byId(quoteId))!);
      });

  /// Gives the order to [quoteId]'s supplier: the PO for the request at the
  /// quote's landed total, the quote accepted, the others turned down. A
  /// second tap returns the same PO.
  Future<PurchaseOrder> award(String quoteId, {required String by, DateTime? deliveryDate}) => transaction(() async {
        final q = await byId(quoteId);
        if (q == null) throw ArgumentError('That quote is no longer here.');
        if (q.status == 'rejected') throw ArgumentError('This quote was turned down.');
        final r = await (select(purchaseRequests)..where((x) => x.id.equals(q.requestId))).getSingle();
        final landed = compareQuotes(r, [q], DateTime.now()).lines.single.landed;
        final po = await db.purchaseDao.orderFromRequest(
            r.id,
            PurchaseOrdersCompanion.insert(
              id: _uuid.v4(),
              projectId: r.projectId,
              supplierId: q.supplierId,
              raisedBy: by,
              totalAmount: Value((landed * 100).roundToDouble() / 100),
              deliveryDate: Value(deliveryDate ?? (q.deliveryDays == null ? null : DateTime.now().add(Duration(days: q.deliveryDays!)))),
              notes: Value(_clip(awardNote(q), 500)),
            ));
        for (final other in await forRequest(r.id)) {
          final status = other.id == quoteId ? 'accepted' : (other.status == 'received' ? 'rejected' : other.status);
          final poId = other.id == quoteId ? po.id : other.poId;
          if (status == other.status && poId == other.poId) continue;
          await (update(supplierQuotes)..where((x) => x.id.equals(other.id)))
              .write(SupplierQuotesCompanion(status: Value(status), poId: Value(poId)));
          await _queue(other.id, 'update', (await byId(other.id))!);
        }
        return po;
      });

  Future<void> upsertFromRemote(SupplierQuotesCompanion c) => into(supplierQuotes).insertOnConflictUpdate(c);
}

// ---------------------------------------------------------------------------
// Selfie and geofence attendance
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [StaffAttendance, AttendancePhotos])
class StaffAttendanceDao extends DatabaseAccessor<AppDatabase> with _$StaffAttendanceDaoMixin {
  StaffAttendanceDao(super.db);

  Future<void> _queue(StaffAttendanceData row, String op) => db.syncOutboxDao.enqueue(
      targetTable: 'staff_attendance', recordId: row.id, operation: op, payloadJson: jsonEncode(staffAttendanceToSupabaseJson(row)));

  /// Keeps a punch or check-in photo (already on the phone) and queues it
  /// for the cloud.
  Future<AttendancePhoto> addPhoto({
    required String projectId,
    required String filePath,
    required String by,
    DateTime? takenAt,
    double? lat,
    double? lng,
  }) =>
      transaction(() async {
        final row = await into(attendancePhotos).insertReturning(AttendancePhotosCompanion.insert(
          id: _uuid.v4(),
          projectId: projectId,
          filePath: filePath,
          mimeType: Value(attachmentMimeType(filePath)),
          takenBy: by,
          takenAt: takenAt ?? DateTime.now(),
          lat: Value(lat),
          lng: Value(lng),
        ));
        await db.syncOutboxDao.enqueue(
            targetTable: 'attendance_photos',
            recordId: row.id,
            operation: 'insert',
            payloadJson: jsonEncode(attendancePhotoToSupabaseJson(row)));
        return row;
      });

  Future<AttendancePhoto?> photoById(String? id) => id == null
      ? Future.value(null)
      : (select(attendancePhotos)..where((p) => p.id.equals(id))).getSingleOrNull();

  Future<Map<String, AttendancePhoto>> photosFor(Iterable<String> ids) async {
    final list = ids.toSet().toList();
    if (list.isEmpty) return const {};
    final rows = await (select(attendancePhotos)..where((p) => p.id.isIn(list))).get();
    return {for (final r in rows) r.id: r};
  }

  Future<StaffAttendanceData?> byId(String id) =>
      (select(staffAttendance)..where((a) => a.id.equals(id))).getSingleOrNull();

  /// Checks [userId] in at [projectId] with a selfie. Inside the geofence
  /// it counts at once; otherwise [reason] is needed and it waits for an OK.
  Future<StaffAttendanceData> checkIn({
    required String companyId,
    required String projectId,
    required String userId,
    required String? selfiePath,
    required ProjectGeofence? fence,
    double? lat,
    double? lng,
    double? accuracyM,
    String? reason,
    DateTime? now,
  }) {
    if (selfiePath == null || selfiePath.isEmpty) throw ArgumentError('Take a selfie to check in.');
    final at = now ?? DateTime.now();
    final day = dayKey(at);
    final geo = geoCheck(lat, lng, fence);
    final why = _clip(reason, 300);
    if (geo.within != true && why == null) {
      throw ArgumentError(fence == null
          ? 'This site has no location set. Say where you are, for your manager to approve.'
          : lat == null
              ? 'No GPS fix. Say where you are, for your manager to approve.'
              : 'You are away from the site. Say why, for your manager to approve.');
    }
    return transaction(() async {
      final same = await (select(staffAttendance)
            ..where((a) => a.userId.equals(userId) & a.projectId.equals(projectId) & a.day.equals(day)))
          .getSingleOrNull();
      if (same != null) {
        throw ArgumentError(same.checkOut == null
            ? 'You are already checked in at this site.'
            : 'You have checked in and out at this site today already.');
      }
      final photo = await addPhoto(projectId: projectId, filePath: selfiePath, by: userId, takenAt: at, lat: lat, lng: lng);
      final row = await into(staffAttendance).insertReturning(StaffAttendanceCompanion.insert(
        id: _uuid.v4(),
        companyId: companyId,
        projectId: projectId,
        userId: userId,
        day: day,
        checkIn: at,
        inLat: Value(lat),
        inLng: Value(lng),
        inAccuracyM: Value(accuracyM),
        inDistanceM: Value(geo.distanceM),
        inPhotoId: Value(photo.id),
        withinGeofence: Value(geo.within),
        status: Value(geo.within == true ? 'ok' : 'pending'),
        reason: Value(why),
        createdAt: Value(at),
      ));
      await _queue(row, 'insert');
      return row;
    });
  }

  /// Closes today's check-in, with a selfie and fix where there is one.
  Future<StaffAttendanceData> checkOut(
    String id, {
    required ProjectGeofence? fence,
    String? selfiePath,
    double? lat,
    double? lng,
    DateTime? now,
  }) =>
      transaction(() async {
        final r = await byId(id);
        if (r == null) throw ArgumentError('That check-in is no longer here.');
        if (r.checkOut != null) throw ArgumentError('You have checked out already.');
        final at = now ?? DateTime.now();
        if (!at.isAfter(r.checkIn)) throw ArgumentError('Check-out is after check-in.');
        final geo = geoCheck(lat, lng, fence);
        final photo = selfiePath == null || selfiePath.isEmpty
            ? null
            : await addPhoto(projectId: r.projectId, filePath: selfiePath, by: r.userId, takenAt: at, lat: lat, lng: lng);
        await (update(staffAttendance)..where((a) => a.id.equals(id))).write(StaffAttendanceCompanion(
          checkOut: Value(at),
          outLat: Value(lat),
          outLng: Value(lng),
          outDistanceM: Value(geo.distanceM),
          outPhotoId: Value(photo?.id),
          outWithin: Value(geo.within),
        ));
        final row = (await byId(id))!;
        await _queue(row, 'update');
        return row;
      });

  /// An owner or project manager approves or turns down a check-in.
  Future<StaffAttendanceData> review(String id, {required bool approve, required String by, String? note, DateTime? now}) =>
      transaction(() async {
        final r = await byId(id);
        if (r == null) throw ArgumentError('That check-in is no longer here.');
        if (r.userId == by) throw ArgumentError('Someone else approves your own attendance.');
        await (update(staffAttendance)..where((a) => a.id.equals(id))).write(StaffAttendanceCompanion(
          status: Value(approve ? 'approved' : 'rejected'),
          reviewedBy: Value(by),
          reviewedAt: Value(now ?? DateTime.now()),
          reviewNote: Value(_clip(note, 300)),
        ));
        final row = (await byId(id))!;
        await _queue(row, 'update');
        return row;
      });

  /// Newest first.
  Future<List<StaffAttendanceData>> forUsers(Iterable<String> userIds, {String? fromDay, String? toDay}) {
    final ids = userIds.toSet().toList();
    if (ids.isEmpty) return Future.value(const []);
    final q = select(staffAttendance)..where((a) => a.userId.isIn(ids));
    if (fromDay != null) q.where((a) => a.day.isBiggerOrEqualValue(fromDay));
    if (toDay != null) q.where((a) => a.day.isSmallerOrEqualValue(toDay));
    q.orderBy([(a) => OrderingTerm.desc(a.checkIn)]);
    return q.get();
  }

  /// Newest first.
  Future<List<StaffAttendanceData>> forCompany(String companyId, {String? fromDay, String? toDay}) {
    final q = select(staffAttendance)..where((a) => a.companyId.equals(companyId));
    if (fromDay != null) q.where((a) => a.day.isBiggerOrEqualValue(fromDay));
    if (toDay != null) q.where((a) => a.day.isSmallerOrEqualValue(toDay));
    q.orderBy([(a) => OrderingTerm.desc(a.checkIn)]);
    return q.get();
  }

  Future<void> upsertFromRemote(StaffAttendanceCompanion c) => into(staffAttendance).insertOnConflictUpdate(c);
  Future<void> upsertPhotoFromRemote(AttendancePhotosCompanion c) => into(attendancePhotos).insertOnConflictUpdate(c);
}

// ---------------------------------------------------------------------------
// Daily site close (v31). Rules in features/daily/day_close.dart; the
// server's copy in supabase/migrations/20261110200000_daily_site_close.sql.
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [SiteDayEvents, SiteCloseSettings, MemberSyncStatus])
class DayCloseDao extends DatabaseAccessor<AppDatabase> with _$DayCloseDaoMixin {
  DayCloseDao(super.db);

  /// A site's day events, oldest first, optionally from [fromDay] to
  /// [toDay] (yyyy-mm-dd, inclusive).
  Future<List<SiteDayEvent>> eventsFor(String projectId, {String? fromDay, String? toDay}) {
    final q = select(siteDayEvents)..where((e) => e.projectId.equals(projectId));
    if (fromDay != null) q.where((e) => e.workDate.isBiggerOrEqualValue(fromDay));
    if (toDay != null) q.where((e) => e.workDate.isSmallerOrEqualValue(toDay));
    q.orderBy([(e) => OrderingTerm.asc(e.createdAt), (e) => OrderingTerm.asc(e.rowId)]);
    return q.get();
  }

  /// Adds one event. Never changed afterwards: a correction is a new row.
  Future<SiteDayEvent> record({
    required String projectId,
    required String workDate,
    required String kind,
    required String by,
    bool siteClosed = false,
    bool noDeliveries = false,
    bool noExpenses = false,
    String? reason,
    String? note,
    String? fingerprint,
    double? amount,
    String? itemRef,
    DateTime? now,
  }) =>
      transaction(() async {
        final row = await into(siteDayEvents).insertReturning(SiteDayEventsCompanion.insert(
          id: _uuid.v4(),
          projectId: projectId,
          workDate: workDate,
          kind: kind,
          siteClosed: Value(siteClosed),
          noDeliveries: Value(noDeliveries),
          noExpenses: Value(noExpenses),
          reason: Value(_clip(reason, 20)),
          note: Value(_clip(note, 300)),
          fingerprint: Value(_clip(fingerprint, 200)),
          amount: Value(amount),
          itemRef: Value(_clip(itemRef, 160)),
          recordedBy: by,
          createdAt: Value(now ?? DateTime.now()),
        ));
        await db.syncOutboxDao.enqueue(
          targetTable: 'site_day_events',
          recordId: row.id,
          operation: 'insert',
          payloadJson: jsonEncode(siteDayEventToSupabaseJson(row)),
        );
        return row;
      });

  Future<SiteCloseSetting?> settingsFor(String projectId) =>
      (select(siteCloseSettings)..where((s) => s.id.equals(projectId))).getSingleOrNull();

  Future<SiteCloseSetting> saveSettings({
    required String projectId,
    required int cutoffMinutes,
    required String by,
    String? supervisorId,
    String? backupId,
    String? backupUntil,
    DateTime? now,
  }) =>
      transaction(() async {
        if (cutoffMinutes < 0 || cutoffMinutes >= 24 * 60) throw ArgumentError('cutoff outside the day');
        final row = SiteCloseSettingsCompanion.insert(
          id: projectId,
          projectId: projectId,
          cutoffMinutes: Value(cutoffMinutes),
          supervisorId: Value(supervisorId),
          backupId: Value(backupId),
          backupUntil: Value(backupId == null ? null : backupUntil),
          updatedBy: by,
          updatedAt: Value(now ?? DateTime.now()),
        );
        await into(siteCloseSettings).insertOnConflictUpdate(row);
        final saved = (await settingsFor(projectId))!;
        await db.syncOutboxDao.enqueue(
          targetTable: 'site_close_settings',
          recordId: projectId,
          operation: 'upsert',
          payloadJson: jsonEncode(siteCloseSettingToSupabaseJson(saved)),
        );
        return saved;
      });

  /// Whether this phone still has [eventId] waiting to send.
  Future<bool> isWaitingToSync(String eventId) async =>
      (await db.syncOutboxDao.dirtyKeys()).contains(SyncOutboxDao.key('site_day_events', eventId));

  Future<List<MemberSyncStatusData>> syncStatusFor(String companyId) =>
      (select(memberSyncStatus)..where((s) => s.companyId.equals(companyId))).get();

  /// What the server says about the company's phones now.
  Future<void> replaceSyncStatus(String companyId, List<MemberSyncStatusCompanion> rows) => transaction(() async {
        await (delete(memberSyncStatus)..where((s) => s.companyId.equals(companyId))).go();
        for (final r in rows) {
          await into(memberSyncStatus).insertOnConflictUpdate(r);
        }
      });

  Future<void> upsertEventFromRemote(SiteDayEventsCompanion c) => into(siteDayEvents).insertOnConflictUpdate(c);
  Future<void> upsertSettingsFromRemote(SiteCloseSettingsCompanion c) =>
      into(siteCloseSettings).insertOnConflictUpdate(c);
}

// ---------------------------------------------------------------------------
// The site cash book (v36)
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [CashMoves])
class CashBookDao extends DatabaseAccessor<AppDatabase> with _$CashBookDaoMixin {
  CashBookDao(super.db);

  static const kinds = ['given', 'returned', 'counted'];

  /// Every entry on a site, cancelled ones too, oldest first.
  Future<List<CashMove>> forProject(String projectId) => (select(cashMoves)
        ..where((c) => c.projectId.equals(projectId))
        ..orderBy([(c) => OrderingTerm.asc(c.movedOn), (c) => OrderingTerm.asc(c.createdAt)]))
      .get();

  Future<List<CashMove>> forProjects(Iterable<String> projectIds) =>
      (select(cashMoves)..where((c) => c.projectId.isIn(projectIds.toList()))).get();

  Future<CashMove?> byId(String id) => (select(cashMoves)..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<CashMove> record({
    required String projectId,
    required String holderId,
    required String kind,
    required double amount,
    required String movedOn,
    required String by,
    String? note,
    DateTime? now,
  }) {
    if (!kinds.contains(kind)) throw ArgumentError('Unknown cash entry: $kind');
    if (amount.isNaN || amount < 0 || (kind != 'counted' && amount <= 0)) {
      throw ArgumentError('Enter an amount above zero');
    }
    return transaction(() async {
      final row = await into(cashMoves).insertReturning(CashMovesCompanion.insert(
        id: _uuid.v4(),
        projectId: projectId,
        holderId: holderId,
        kind: kind,
        amount: (amount * 100).roundToDouble() / 100,
        movedOn: movedOn,
        note: Value(_clip(note, 300)),
        recordedBy: by,
        createdAt: Value(now ?? DateTime.now()),
      ));
      await _queue(row, 'insert');
      return row;
    });
  }

  /// Cancels an entry. It stays in the book, struck through.
  Future<CashMove> cancel(String id, {required String reason}) {
    return transaction(() async {
      await (update(cashMoves)..where((c) => c.id.equals(id)))
          .write(CashMovesCompanion(voided: const Value(true), voidReason: Value(_clip(reason, 200))));
      final row = await (select(cashMoves)..where((c) => c.id.equals(id))).getSingle();
      await _queue(row, 'update');
      return row;
    });
  }

  Future<void> _queue(CashMove row, String operation) => db.syncOutboxDao.enqueue(
        targetTable: 'site_cash_moves',
        recordId: row.id,
        operation: operation,
        payloadJson: jsonEncode(cashMoveToSupabaseJson(row)),
      );

  Future<void> upsertFromRemote(CashMovesCompanion c) => into(cashMoves).insertOnConflictUpdate(c);
}
