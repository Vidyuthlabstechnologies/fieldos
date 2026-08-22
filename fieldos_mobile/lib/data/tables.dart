/// Drift table definitions for FieldOS Mobile.
///
/// These mirror the server-side SQLAlchemy models in `fieldos/models.py`
/// so a project exported from the desktop app imports cleanly into mobile.
/// Numeric columns use [RealColumn] (double); all precision-critical BOQ
/// math is done in-memory with [Decimal] by the estimation engine, not in SQL.
library;

import 'package:drift/drift.dart';

class Users extends Table {
  TextColumn get id => text()();
  TextColumn get username => text().withLength(min: 1, max: 100)();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get passwordHash => text().withLength(min: 1, max: 200)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {username},
      ];
}

class Sessions extends Table {
  TextColumn get token => text().withLength(min: 1, max: 64)();
  TextColumn get userId => text().withLength(min: 1, max: 36)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get expiresAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {token};
}

class AppSettings extends Table {
  /// Installation-wide config. Currently only the optional Sarvam API key
  /// (write-only, owner-gated) lives here, mirroring the desktop app.
  TextColumn get key => text().withLength(min: 1, max: 100)();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class Companies extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class CompanyMembers extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withLength(min: 1, max: 36)();
  TextColumn get userId => text().withLength(min: 1, max: 64)();
  TextColumn get role => text().withLength(min: 1, max: 30)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {companyId, userId},
      ];
}

class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withLength(min: 1, max: 36)();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get clientName => text().withLength(max: 200).nullable()();
  RealColumn get locationLat => real().nullable()();
  RealColumn get locationLng => real().nullable()();
  IntColumn get geofenceRadiusM => integer().nullable()();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();
  TextColumn get status => text().withLength(min: 1, max: 20).withDefault(const Constant('planning'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ProjectMembers extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get userId => text().withLength(min: 1, max: 64)();
  TextColumn get role => text().withLength(min: 1, max: 30)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {projectId, userId},
      ];
}

class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get assigneeId => text().withLength(max: 64).nullable()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  TextColumn get status => text().withLength(min: 1, max: 20).withDefault(const Constant('todo'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class DprEntries extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get createdBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get entryDate => dateTime()();
  TextColumn get workSummary => text()();
  IntColumn get manpowerCount => integer().withDefault(const Constant(0))();
  TextColumn get weather => text().withLength(max: 50).nullable()();
  TextColumn get status => text().withLength(min: 1, max: 20).withDefault(const Constant('confirmed'))();
  TextColumn get source => text().withLength(min: 1, max: 20).withDefault(const Constant('manual'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class DprPhotos extends Table {
  TextColumn get id => text()();
  TextColumn get dprEntryId => text().withLength(min: 1, max: 36)();
  /// Local on-device file path (under the app's documents dir). The desktop
  /// app only ever stored a `photo_url` string with no storage behind it;
  /// mobile stores the real file locally, fully offline.
  TextColumn get photoPath => text().withLength(min: 1, max: 500)();
  TextColumn get caption => text().withLength(max: 200).nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Issues extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get dprEntryId => text().withLength(max: 36).nullable()();
  TextColumn get description => text()();
  TextColumn get severity => text().withLength(min: 1, max: 20).withDefault(const Constant('medium'))();
  TextColumn get status => text().withLength(min: 1, max: 20).withDefault(const Constant('open'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get resolvedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Estimations extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get status => text().withLength(min: 1, max: 20).withDefault(const Constant('draft'))();
  RealColumn get contractorProfitPercent => real().nullable()();
  TextColumn get createdBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class CostHeads extends Table {
  TextColumn get id => text()();
  TextColumn get estimationId => text().withLength(min: 1, max: 36)();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get calculationType => text().withLength(min: 1, max: 20)();
  TextColumn get rawUnit => text().withLength(min: 1, max: 20)();
  TextColumn get billingUnit => text().withLength(min: 1, max: 20)();
  RealColumn get conversionFactor => real().withDefault(const Constant(1))();
  RealColumn get ratePerUnit => real().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class MeasurementEntries extends Table {
  TextColumn get id => text()();
  TextColumn get costHeadId => text().withLength(min: 1, max: 36)();
  TextColumn get description => text().withLength(min: 1, max: 200)();
  RealColumn get length => real().nullable()();
  RealColumn get width => real().nullable()();
  RealColumn get depth => real().nullable()();
  RealColumn get nos => real().withDefault(const Constant(1))();
  BoolColumn get isDeduction => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SteelEntries extends Table {
  TextColumn get id => text()();
  TextColumn get costHeadId => text().withLength(min: 1, max: 36)();
  TextColumn get description => text().withLength(min: 1, max: 200)();
  RealColumn get barDiaMm => real()();
  RealColumn get nos => real()();
  RealColumn get lengthFt => real()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// --- ERP backbone (materials, labour, subcontractors, finance, approvals) ---
/// Mirrors the modules Onsite advertises. The desktop `fieldos` app had none
/// of these; they are greenfield here and wired into the agentic cost engine.

class Suppliers extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withLength(min: 1, max: 36)();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get contactPhone => text().withLength(max: 30).nullable()();
  TextColumn get email => text().withLength(max: 120).nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// RFQ / purchase request raised by site, awaiting approval + ordering.
class PurchaseRequests extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get raisedBy => text().withLength(min: 1, max: 64)();
  TextColumn get materialName => text().withLength(min: 1, max: 200)();
  RealColumn get quantity => real().withDefault(const Constant(1))();
  TextColumn get unit => text().withLength(max: 20).nullable()();
  RealColumn get estimatedAmount => real().nullable()();
  TextColumn get status =>
      text().withLength(min: 1, max: 20).withDefault(const Constant('draft'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Approved purchase order issued to a supplier (originates from an RFQ).
class PurchaseOrders extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get supplierId => text().withLength(min: 1, max: 36)();
  TextColumn get requestId => text().withLength(max: 36).nullable()();
  TextColumn get raisedBy => text().withLength(min: 1, max: 64)();
  RealColumn get totalAmount => real().nullable()();
  TextColumn get status =>
      text().withLength(min: 1, max: 20).withDefault(const Constant('open'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Goods receipt (GRN). Material actually delivered on site. Feeds the
/// material actuals used by the cost engine; may be linked to a cost head
/// and/or a PO for reconciliation.
class MaterialReceipts extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get poId => text().withLength(max: 36).nullable()();
  TextColumn get supplierId => text().withLength(max: 36).nullable()();
  TextColumn get costHeadId => text().withLength(max: 36).nullable()();
  TextColumn get materialName => text().withLength(min: 1, max: 200)();
  RealColumn get quantity => real()();
  TextColumn get unit => text().withLength(max: 20).nullable()();
  RealColumn get amount => real()();
  TextColumn get receivedBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get receivedOn => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Any site expense. When `costHeadId` is set it rolls into that BOQ line's
/// actuals; otherwise it's a project-level actual.
class SiteExpenses extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get costHeadId => text().withLength(max: 36).nullable()();
  TextColumn get category => text().withLength(min: 1, max: 50)();
  RealColumn get amount => real()();
  TextColumn get incurredOn => text().withLength(min: 1, max: 30)();
  TextColumn get recordedBy => text().withLength(min: 1, max: 64)();
  TextColumn get note => text().withLength(max: 300).nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// GPS-based attendance. `punchIn`/`punchOut` timestamps plus the captured
/// coordinates let the cost engine compute attendance vs geofence and labour
/// productivity, not just a headcount.
class LabourAttendance extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get workerName => text().withLength(min: 1, max: 120)();
  TextColumn get recordedBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get punchIn => dateTime()();
  DateTimeColumn get punchOut => dateTime().nullable()();
  RealColumn get lat => real().nullable()();
  RealColumn get lng => real().nullable()();
  BoolColumn get withinGeofence => boolean().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Per-project GPS geofence. A punch is flagged `withinGeofence` when the
/// captured coordinates fall within `radiusMeters` of (centerLat, centerLng).
class ProjectGeofences extends Table {
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  RealColumn get centerLat => real()();
  RealColumn get centerLng => real()();
  RealColumn get radiusMeters => real().withDefault(const Constant(100))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {projectId};
}

class Subcontractors extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withLength(min: 1, max: 36)();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get contactPhone => text().withLength(max: 30).nullable()();
  TextColumn get trade => text().withLength(max: 100).nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class WorkOrders extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get subcontractorId => text().withLength(min: 1, max: 36)();
  TextColumn get description => text().withLength(min: 1, max: 300)();
  RealColumn get agreedAmount => real().nullable()();
  RealColumn get billedAmount => real().withDefault(const Constant(0))();
  TextColumn get status =>
      text().withLength(min: 1, max: 20).withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Multi-level approval chain. Every purchase request, PO, vendor bill and
/// site expense routes through here; the agentic layer proposes the next
/// approver and flags stale pending items.
class Approvals extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(max: 36).nullable()();
  TextColumn get entityType => text().withLength(min: 1, max: 40)();
  TextColumn get entityId => text().withLength(min: 1, max: 36)();
  TextColumn get requestedBy => text().withLength(min: 1, max: 64)();
  TextColumn get status =>
      text().withLength(min: 1, max: 20).withDefault(const Constant('pending'))();
  TextColumn get approverId => text().withLength(max: 64).nullable()();
  TextColumn get decisionNote => text().withLength(max: 300).nullable()();
  DateTimeColumn get decidedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
