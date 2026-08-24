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

import 'package:fieldos_mobile/sync/sync_mappers.dart';

import 'tables.dart';

part 'app_database.g.dart';

final _uuid = Uuid();

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
  SiteExpenses,
  LabourAttendance,
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
                  final docs = await getApplicationDocumentsDirectory();
                  return p.join(docs.path, 'fieldos.sqlite');
                },
              ),
            ));

  /// In-memory database for tests (no filesystem / path_provider needed).
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 4;

  // v3 shipped with no MigrationStrategy at all -- the default only creates
  // missing tables, never adds columns, so any additive change to an
  // existing table would crash on upgrade. v4 catches up both the suppliers
  // `vendors`-parity columns and the procurement alignment columns.
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
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
        },
      );

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
}

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

  Future<User?> byId(String id) =>
      (select(users)..where((u) => u.id.equals(id))).getSingleOrNull();

  Future<void> create(UsersCompanion user) => into(users).insert(user);
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

@DriftAccessor(tables: [Tasks])
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

  Future<void> updateStatus(String id, String status) {
    return transaction(() async {
      await (update(tasks)..where((t) => t.id.equals(id)))
          .write(TasksCompanion(status: Value(status), updatedAt: Value(DateTime.now())));
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

  Future<void> addPhoto(DprPhotosCompanion companion) =>
      into(dprPhotos).insert(companion.copyWith(id: Value(_uuid.v4())));

  Future<List<DprPhoto>> photosFor(String dprEntryId) =>
      (select(dprPhotos)..where((p) => p.dprEntryId.equals(dprEntryId))).get();
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

  /// See ProjectDao.upsertFromRemote -- same server-wins merge pattern.
  Future<void> upsertFromRemoteRequest(PurchaseRequestsCompanion companion) =>
      into(purchaseRequests).insertOnConflictUpdate(companion);

  Future<void> upsertFromRemoteOrder(PurchaseOrdersCompanion companion) =>
      into(purchaseOrders).insertOnConflictUpdate(companion);
}

@DriftAccessor(tables: [MaterialReceipts])
class MaterialDao extends DatabaseAccessor<AppDatabase> with _$MaterialDaoMixin {
  MaterialDao(super.db);

  Future<MaterialReceipt> createReceipt(MaterialReceiptsCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(materialReceipts).insert(companion.copyWith(id: Value(id)));
      return (await (select(materialReceipts)..where((m) => m.id.equals(id))).getSingle());
    });
  }

  Future<List<MaterialReceipt>> forProject(String projectId) =>
      (select(materialReceipts)..where((m) => m.projectId.equals(projectId))).get();
}

// ---------------------------------------------------------------------------
// Finance actuals (expenses + work-order billing)
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [SiteExpenses, WorkOrders])
class ExpenseDao extends DatabaseAccessor<AppDatabase> with _$ExpenseDaoMixin {
  ExpenseDao(super.db);

  Future<SiteExpense> create(SiteExpensesCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(siteExpenses).insert(companion.copyWith(id: Value(id)));
      return (await (select(siteExpenses)..where((e) => e.id.equals(id))).getSingle());
    });
  }

  Future<List<SiteExpense>> forProject(String projectId) =>
      (select(siteExpenses)..where((e) => e.projectId.equals(projectId))).get();

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

@DriftAccessor(tables: [LabourAttendance])
class AttendanceDao extends DatabaseAccessor<AppDatabase> with _$AttendanceDaoMixin {
  AttendanceDao(super.db);

  Future<LabourAttendanceData> punchIn(LabourAttendanceCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(labourAttendance).insert(companion.copyWith(id: Value(id)));
      return (await (select(labourAttendance)..where((a) => a.id.equals(id))).getSingle());
    });
  }

  Future<void> punchOut(String id, {double? lat, double? lng, bool? withinGeofence}) =>
      (update(labourAttendance)..where((a) => a.id.equals(id))).write(LabourAttendanceCompanion(
        punchOut: Value(DateTime.now()),
        lat: lat == null ? const Value.absent() : Value(lat),
        lng: lng == null ? const Value.absent() : Value(lng),
        withinGeofence: withinGeofence == null ? const Value.absent() : Value(withinGeofence),
      ));

  Future<List<LabourAttendanceData>> forProject(String projectId) =>
      (select(labourAttendance)..where((a) => a.projectId.equals(projectId))).get();
}

@DriftAccessor(tables: [ProjectGeofences])
class GeofenceDao extends DatabaseAccessor<AppDatabase> with _$GeofenceDaoMixin {
  GeofenceDao(super.db);

  Future<ProjectGeofence?> forProject(String projectId) =>
      (select(projectGeofences)..where((g) => g.projectId.equals(projectId))).getSingleOrNull();

  Future<void> set(String projectId, double lat, double lng, double radiusMeters) =>
      into(projectGeofences).insertOnConflictUpdate(ProjectGeofencesCompanion(
        projectId: Value(projectId),
        centerLat: Value(lat),
        centerLng: Value(lng),
        radiusMeters: Value(radiusMeters),
      ));
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

  Future<void> decide(String id, bool approved, String approverId, String? note) {
    return transaction(() async {
      await (update(approvals)..where((a) => a.id.equals(id))).write(ApprovalsCompanion(
        status: Value(approved ? 'approved' : 'rejected'),
        approverId: Value(approverId),
        decisionNote: Value(note),
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

  Future<void> updateStatus(String id, String status) {
    return transaction(() async {
      await (update(equipment)..where((e) => e.id.equals(id)))
          .write(EquipmentCompanion(status: Value(status)));
      final row = await (select(equipment)..where((e) => e.id.equals(id))).getSingle();
      await db.syncOutboxDao.enqueue(
        targetTable: 'equipment',
        recordId: row.id,
        operation: 'update',
        payloadJson: jsonEncode(equipmentToSupabaseJson(row)),
      );
    });
  }

  /// See ProjectDao.upsertFromRemote -- same server-wins merge pattern.
  Future<void> upsertFromRemote(EquipmentCompanion companion) =>
      into(equipment).insertOnConflictUpdate(companion);

  Future<EquipmentLog> addLog(EquipmentLogsCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(equipmentLogs).insert(companion.copyWith(id: Value(id)));
      return (await (select(equipmentLogs)..where((l) => l.id.equals(id))).getSingle());
    });
  }

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
      return (await (select(inspectionItems)..where((item) => item.id.equals(id))).getSingle());
    });
  }

  Future<List<InspectionItem>> itemsFor(String inspectionId) {
    return (select(inspectionItems)
          ..where((item) => item.inspectionId.equals(inspectionId))
          ..orderBy([(item) => OrderingTerm.asc(item.sortOrder)]))
        .get();
  }

  Future<void> updateItemStatus(String id, String status, {String? notes}) {
    final companion = InspectionItemsCompanion(
      status: Value(status),
      notes: notes != null ? Value(notes) : const Value.absent(),
    );
    return (update(inspectionItems)..where((item) => item.id.equals(id))).write(companion);
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

@DriftAccessor(tables: [SyncOutbox])
class SyncOutboxDao extends DatabaseAccessor<AppDatabase> with _$SyncOutboxDaoMixin {
  SyncOutboxDao(super.db);

  Future<void> enqueue({
    required String targetTable,
    required String recordId,
    required String operation,
    required String payloadJson,
  }) {
    return into(syncOutbox).insert(SyncOutboxCompanion.insert(
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

  Future<int> pendingCount() async {
    final rows = await pending();
    return rows.length;
  }
}
