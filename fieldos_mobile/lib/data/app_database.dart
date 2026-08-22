/// FieldOS Mobile SQLite database (drift) + data-access methods.
///
/// Offline-first: the whole database lives in the app's documents directory.
/// Nothing here touches the network.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

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
  int get schemaVersion => 1;

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

  Future<Project> create(ProjectsCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(projects).insert(companion.copyWith(id: Value(id)));
      return (await (select(projects)..where((p) => p.id.equals(id))).getSingle());
    });
  }

  Future<List<Project>> forCompany(String companyId) =>
      (select(projects)..where((p) => p.companyId.equals(companyId))).get();

  Future<Project?> byId(String id) =>
      (select(projects)..where((p) => p.id.equals(id))).getSingleOrNull();
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
      return (await (select(tasks)..where((t) => t.id.equals(id))).getSingle());
    });
  }

  Future<List<Task>> forProject(String projectId) =>
      (select(tasks)..where((t) => t.projectId.equals(projectId))).get();

  Future<void> updateStatus(String id, String status) =>
      (update(tasks)..where((t) => t.id.equals(id)))
          .write(TasksCompanion(status: Value(status), updatedAt: Value(DateTime.now())));
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
      return (await (select(dprEntries)..where((d) => d.id.equals(id))).getSingle());
    });
  }

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
      return (await (select(issues)..where((i) => i.id.equals(id))).getSingle());
    });
  }

  Future<List<Issue>> forProject(String projectId) =>
      (select(issues)..where((i) => i.projectId.equals(projectId))).get();

  Future<void> resolve(String id) =>
      (update(issues)..where((i) => i.id.equals(id))).write(IssuesCompanion(
        status: const Value('resolved'),
        resolvedAt: Value(DateTime.now()),
      ));
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
      return (await (select(estimations)..where((e) => e.id.equals(id))).getSingle());
    });
  }

  Future<List<Estimation>> forProject(String projectId) =>
      (select(estimations)..where((e) => e.projectId.equals(projectId))).get();

  Future<CostHead> addCostHead(CostHeadsCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(costHeads).insert(companion.copyWith(id: Value(id)));
      return (await (select(costHeads)..where((c) => c.id.equals(id))).getSingle());
    });
  }

  Future<void> addMeasurement(MeasurementEntriesCompanion companion) =>
      into(measurementEntries).insert(companion.copyWith(id: Value(_uuid.v4())));

  Future<void> addSteel(SteelEntriesCompanion companion) =>
      into(steelEntries).insert(companion.copyWith(id: Value(_uuid.v4())));

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
      return (await (select(suppliers)..where((s) => s.id.equals(id))).getSingle());
    });
  }

  Future<List<Supplier>> forCompany(String companyId) =>
      (select(suppliers)..where((s) => s.companyId.equals(companyId))).get();
}

@DriftAccessor(tables: [Subcontractors])
class SubcontractorDao extends DatabaseAccessor<AppDatabase> with _$SubcontractorDaoMixin {
  SubcontractorDao(super.db);

  Future<Subcontractor> create(SubcontractorsCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(subcontractors).insert(companion.copyWith(id: Value(id)));
      return (await (select(subcontractors)..where((s) => s.id.equals(id))).getSingle());
    });
  }

  Future<List<Subcontractor>> forCompany(String companyId) =>
      (select(subcontractors)..where((s) => s.companyId.equals(companyId))).get();
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
      return (await (select(purchaseRequests)..where((r) => r.id.equals(id))).getSingle());
    });
  }

  Future<PurchaseOrder> createOrder(PurchaseOrdersCompanion companion) {
    final id = companion.id.present ? companion.id.value : _uuid.v4();
    return transaction(() async {
      await into(purchaseOrders).insert(companion.copyWith(id: Value(id)));
      return (await (select(purchaseOrders)..where((o) => o.id.equals(id))).getSingle());
    });
  }

  Future<List<PurchaseRequest>> requestsFor(String projectId) =>
      (select(purchaseRequests)..where((r) => r.projectId.equals(projectId))).get();

  Future<List<PurchaseOrder>> ordersFor(String projectId) =>
      (select(purchaseOrders)..where((o) => o.projectId.equals(projectId))).get();

  Future<void> setRequestStatus(String id, String status) =>
      (update(purchaseRequests)..where((r) => r.id.equals(id)))
          .write(PurchaseRequestsCompanion(status: Value(status)));

  Future<void> setOrderStatus(String id, String status) =>
      (update(purchaseOrders)..where((o) => o.id.equals(id)))
          .write(PurchaseOrdersCompanion(status: Value(status)));
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
      return (await (select(workOrders)..where((w) => w.id.equals(id))).getSingle());
    });
  }

  Future<List<WorkOrder>> workOrdersFor(String projectId) =>
      (select(workOrders)..where((w) => w.projectId.equals(projectId))).get();

  Future<void> billWorkOrder(String id, double additional) =>
      (update(workOrders)..where((w) => w.id.equals(id)))
          .write(WorkOrdersCompanion(billedAmount: Value(additional)));
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
      return (await (select(approvals)..where((a) => a.id.equals(id))).getSingle());
    });
  }

  Future<List<Approval>> pendingFor(String? projectId) {
    final q = select(approvals)..where((a) => a.status.equals('pending'));
    if (projectId != null) {
      q.where((a) => a.projectId.equals(projectId));
    }
    return q.get();
  }

  Future<void> decide(String id, bool approved, String approverId, String? note) =>
      (update(approvals)..where((a) => a.id.equals(id))).write(ApprovalsCompanion(
        status: Value(approved ? 'approved' : 'rejected'),
        approverId: Value(approverId),
        decisionNote: Value(note),
        decidedAt: Value(DateTime.now()),
      ));
}
