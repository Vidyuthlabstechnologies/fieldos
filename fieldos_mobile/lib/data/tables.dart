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

  /// How much of the task is done, 0-100. Moved forward from the daily
  /// report, or by hand on the task.
  IntColumn get progress => integer().withDefault(const Constant(0))();

  /// 'high', 'normal' or 'low'. High ones sort to the top of the list.
  TextColumn get priority => text().withLength(min: 1, max: 10).withDefault(const Constant('normal'))();

  /// When work is planned to start. With [progress] it gives the forecast
  /// finish, which the delay view compares against [dueDate].
  DateTimeColumn get startDate => dateTime().nullable()();

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
  // Full parity with supabase `vendors` so the sync mapper never has to drop
  // business fields in either direction -- these were added when vendors
  // entered cloud sync (all nullable in Postgres too).
  TextColumn get contactPerson => text().withLength(max: 200).nullable()();
  TextColumn get address => text().withLength(max: 500).nullable()();
  TextColumn get gstNumber => text().withLength(max: 50).nullable()();
  TextColumn get category => text().withLength(max: 100).nullable()();
  TextColumn get notes => text().withLength(max: 500).nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// v13: what was owed to the supplier when the company started using
  /// FieldOS (negative: an advance they still hold).
  RealColumn get openingBalance => real().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// RFQ / purchase request raised by site, awaiting approval + ordering.
/// Column set mirrors supabase purchase_requisitions 1:1 (including the
/// status vocabulary -- 'pending'/'approved'/'rejected'/'ordered', NOT a
/// local 'draft') so rows can sync without violating the remote CHECK
/// constraints. See sync_mappers.dart's docstring for the full story.
class PurchaseRequests extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get raisedBy => text().withLength(min: 1, max: 64)();
  TextColumn get materialName => text().withLength(min: 1, max: 200)();
  RealColumn get quantity => real().withDefault(const Constant(1))();
  // Postgres has unit NOT NULL -- locally non-null defaulting to '' keeps
  // every local row pushable instead of failing the remote constraint.
  TextColumn get unit => text().withDefault(const Constant(''))();
  RealColumn get estimatedAmount => real().nullable()();
  TextColumn get urgency =>
      text().withLength(min: 1, max: 10).withDefault(const Constant('normal'))();
  TextColumn get status =>
      text().withLength(min: 1, max: 20).withDefault(const Constant('pending'))();
  TextColumn get approvedBy => text().withLength(max: 64).nullable()();
  DateTimeColumn get approvedAt => dateTime().nullable()();
  TextColumn get notes => text().withLength(max: 500).nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Approved purchase order issued to a supplier (originates from an RFQ).
/// Mirrors supabase purchase_orders: statuses are the remote CHECK values
/// ('issued'/'acknowledged'/'delivered'/'cancelled'). requestId/requisitionId
/// and quoteId carry both possible origins -- Postgres got requisition_id in
/// a follow-up migration so a mobile-raised PO round-trips its origin link;
/// quoteId is stored as an opaque uuid (no local quotes table) purely so a
/// remotely-created PO doesn't lose that linkage on pull.
class PurchaseOrders extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get supplierId => text().withLength(min: 1, max: 36)();
  TextColumn get requestId => text().withLength(max: 36).nullable()();
  TextColumn get quoteId => text().withLength(max: 36).nullable()();
  TextColumn get raisedBy => text().withLength(min: 1, max: 64)();
  TextColumn get poNumber => text().withLength(max: 50).nullable()();
  RealColumn get totalAmount => real().nullable()();
  DateTimeColumn get deliveryDate => dateTime().nullable()();
  TextColumn get status =>
      text().withLength(min: 1, max: 20).withDefault(const Constant('issued'))();
  TextColumn get notes => text().withLength(max: 500).nullable()();
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
  TextColumn get notes => text().withLength(max: 500).nullable()();

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
  /// Set when the money went to a worker (wages or an advance), so the wage
  /// sheet can show what each person has already been paid.
  TextColumn get workerId => text().withLength(max: 36).nullable()();

  // v10, the money book (Onsite customers asked for vouchers an accountant
  // can work with): who was paid, how, GST, a voucher number, and edits
  // and cancellations that keep a trail instead of deleting.
  /// Who the money went to when it isn't one of the site's workers
  /// ("Balaji Hardware", "Tractor driver").
  TextColumn get paidTo => text().withLength(max: 120).nullable()();
  /// cash, upi, bank or cheque, like PaymentsReceived.mode.
  TextColumn get mode => text().withLength(max: 20).nullable()();
  /// GST rate in percent when the bill carried GST. [amount] is always what
  /// was paid in total, GST included.
  RealColumn get gstPct => real().nullable()();
  /// IGST (another state) instead of CGST + SGST.
  BoolColumn get gstInterState => boolean().withDefault(const Constant(false))();
  /// Voucher number within the site: 1, 2, 3...
  IntColumn get voucherNo => integer().nullable()();
  /// Cancelled entries stay (struck through, with the reason) so the
  /// voucher numbers have no gaps; they count in no total.
  BoolColumn get voided => boolean().withDefault(const Constant(false))();
  TextColumn get voidReason => text().withLength(max: 200).nullable()();
  DateTimeColumn get editedAt => dateTime().nullable()();
  TextColumn get editedBy => text().withLength(max: 64).nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Material taken out of the site store and used. Received (MaterialReceipts)
/// minus used is the stock on site, matched by material name and unit.
class MaterialUsage extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get materialName => text().withLength(min: 1, max: 200)();
  RealColumn get quantity => real()();
  TextColumn get unit => text().withLength(max: 20).nullable()();
  TextColumn get recordedBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get usedOn => dateTime()();
  TextColumn get note => text().withLength(max: 300).nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Money received for a project (client running-bill payments, advances).
/// With SiteExpenses this gives each site's cash in vs cash out.
class PaymentsReceived extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  RealColumn get amount => real()();
  DateTimeColumn get receivedOn => dateTime()();
  TextColumn get fromParty => text().withLength(min: 1, max: 120)();
  TextColumn get mode => text().withLength(min: 1, max: 20)(); // cash, upi, bank, cheque
  TextColumn get recordedBy => text().withLength(min: 1, max: 64)();
  TextColumn get note => text().withLength(max: 300).nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // v10: corrected or cancelled with a trail, like SiteExpenses.
  BoolColumn get voided => boolean().withDefault(const Constant(false))();
  TextColumn get voidReason => text().withLength(max: 200).nullable()();
  DateTimeColumn get editedAt => dateTime().nullable()();
  TextColumn get editedBy => text().withLength(max: 64).nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A bill to the client: a running account (RA) bill of work measured, or
/// a GST tax invoice. Lines are kept as JSON (description, unit, rate,
/// quantity); [gross] and [netPayable] are stored so lists and totals need
/// no recalculation.
class ClientBills extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get kind => text().withLength(min: 1, max: 20)(); // ra | tax_invoice
  TextColumn get billNumber => text().withLength(min: 1, max: 30)();
  DateTimeColumn get billDate => dateTime()();
  TextColumn get clientName => text().withLength(min: 1, max: 200)();
  TextColumn get clientGstin => text().withLength(max: 15).nullable()();
  TextColumn get sac => text().withLength(max: 10).withDefault(const Constant('995411'))();
  TextColumn get linesJson => text()();
  RealColumn get gstRate => real().withDefault(const Constant(18))();
  BoolColumn get interState => boolean().withDefault(const Constant(false))();
  RealColumn get retentionPct => real().withDefault(const Constant(0))();
  RealColumn get tdsPct => real().withDefault(const Constant(0))();
  RealColumn get gross => real()();
  RealColumn get netPayable => real()();
  TextColumn get status => text().withLength(min: 1, max: 20).withDefault(const Constant('issued'))(); // issued | paid
  TextColumn get notes => text().withLength(max: 500).nullable()();
  TextColumn get recordedBy => text().withLength(min: 1, max: 64)();
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
  /// Optional reference to a Workers directory entry. Nullable for backward
  /// compatibility — free-text workerName still works without a directory link.
  TextColumn get workerId => text().withLength(max: 36).nullable()();
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

/// A day's attendance marked by hand for one worker: absent, a quarter,
/// half or full day, or 1½, double or triple for overtime. It takes the
/// place of what that day's punches would count, so sites that keep a
/// muster roll instead of GPS punches still get a right wage sheet. One
/// row per worker per day; [units] null means "count the punches again".
class AttendanceMarks extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get workerId => text().withLength(min: 1, max: 36)();

  /// yyyy-mm-dd, local day.
  TextColumn get day => text().withLength(min: 10, max: 10)();
  RealColumn get units => real().nullable()();
  TextColumn get recordedBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

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

/// --- New feature tables (mirror desktop fieldos/models.py) ---

/// Equipment tracked per project: machinery, tools, vehicles.
class Equipment extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get equipmentType => text().withLength(max: 100).nullable()();
  TextColumn get model => text().withLength(max: 100).nullable()();
  TextColumn get registrationNumber => text().withLength(max: 100).nullable()();
  TextColumn get status => text().withLength(min: 1, max: 20).withDefault(const Constant('available'))();
  RealColumn get dailyRate => real().nullable()();
  TextColumn get notes => text().withLength(max: 500).nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  // v12 (Onsite review batch R4): machines charged by the hour, and the
  // hire register for machines taken on rent.
  RealColumn get hourlyRate => real().nullable()();

  /// 'own' or 'hired'.
  TextColumn get ownership => text().withLength(min: 1, max: 10).withDefault(const Constant('own'))();
  TextColumn get hiredFrom => text().withLength(max: 120).nullable()();
  DateTimeColumn get hiredOn => dateTime().nullable()();
  DateTimeColumn get returnDueOn => dateTime().nullable()();
  DateTimeColumn get returnedOn => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Logs for equipment usage, maintenance, fuel, repairs, inspections.
class EquipmentLogs extends Table {
  TextColumn get id => text()();
  TextColumn get equipmentId => text().withLength(min: 1, max: 36)();
  DateTimeColumn get logDate => dateTime()();
  TextColumn get logType => text().withLength(min: 1, max: 20)(); // usage, maintenance, repair, fuel, inspection
  RealColumn get hoursUsed => real().nullable()();
  TextColumn get description => text().withLength(max: 500).nullable()();
  RealColumn get cost => real().nullable()();
  TextColumn get createdBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Inspections (safety, quality, structural, etc.) with checklist items.
class Inspections extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get inspectionType => text().withLength(min: 1, max: 20)(); // safety, quality, structural, mep, environmental, final, other
  TextColumn get status => text().withLength(min: 1, max: 20).withDefault(const Constant('open'))(); // open, in_progress, completed
  TextColumn get inspectorId => text().withLength(max: 64).nullable()();
  DateTimeColumn get scheduledDate => dateTime().nullable()();
  DateTimeColumn get completedDate => dateTime().nullable()();
  TextColumn get overallResult => text().withLength(max: 20).nullable()(); // pass, fail, partial
  TextColumn get notes => text().withLength(max: 500).nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Checklist items belonging to an inspection.
class InspectionItems extends Table {
  TextColumn get id => text()();
  TextColumn get inspectionId => text().withLength(min: 1, max: 36)();
  TextColumn get itemDescription => text().withLength(min: 1, max: 300)();
  TextColumn get status => text().withLength(min: 1, max: 20).withDefault(const Constant('pending'))(); // pending, pass, fail, na
  TextColumn get notes => text().withLength(max: 300).nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Project documents with versioning (drawings, specs, contracts, permits, etc.).
class Documents extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get category => text().withLength(min: 1, max: 20).withDefault(const Constant('other'))(); // drawing, specification, contract, permit, report, photo, correspondence, safety, other
  IntColumn get version => integer().withDefault(const Constant(1))();
  /// Local on-device file path (copied into the app's documents dir by
  /// file_picker), same pattern as DprPhotos.photoPath.
  TextColumn get filePath => text().withLength(min: 1, max: 500)();
  IntColumn get fileSize => integer().nullable()();
  TextColumn get mimeType => text().withLength(max: 100).nullable()();
  TextColumn get notes => text().withLength(max: 300).nullable()();
  TextColumn get uploadedBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Worker directory per project (name, role, phone, daily wage, active/inactive).
class Workers extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get role => text().withLength(max: 100).nullable()();
  TextColumn get phone => text().withLength(max: 30).nullable()();
  RealColumn get dailyWage => real().nullable()();
  TextColumn get status => text().withLength(min: 1, max: 20).withDefault(const Constant('active'))(); // active, inactive
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Per-project team chat. Append-only, like its Postgres counterpart
/// (supabase/migrations/20261105010000_project_messages.sql): a sent
/// message is a site record, so there is no edit or delete path.
class ProjectMessages extends Table {
  TextColumn get id => text().withLength(min: 1, max: 36)();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get senderId => text().withLength(min: 1, max: 36)();
  TextColumn get senderName => text().withLength(min: 1, max: 120)();
  TextColumn get body => text().withLength(min: 1, max: 4000)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Outbound sync queue (see docs/SUPABASE_SYNC_RESEARCH.md and
/// lib/sync/sync_engine.dart). Every local write that should propagate to
/// Supabase gets enqueued here; a background push drains it in order and
/// deletes each row on success. `recordId` and `payload` are stored as text
/// (payload as JSON) rather than typed per-table, since one outbox handles
/// every syncable table generically.
class SyncOutbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  // Named targetTable, not tableName: the latter collides with Drift's own
  // internal table-metadata naming convention (drift_dev warns on it).
  TextColumn get targetTable => text().withLength(min: 1, max: 64)();
  TextColumn get recordId => text().withLength(min: 1, max: 36)();
  TextColumn get operation => text().withLength(min: 1, max: 10)(); // insert | update | delete
  TextColumn get payload => text()(); // JSON-encoded row snapshot
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
}
