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

/// A site's team (v17, synced as project_members): who works on the site,
/// in which site role (owner, project_manager, site_engineer, accounts,
/// storekeeper, viewer), and a site manager's approval limit in rupees.
class ProjectMembers extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get userId => text().withLength(min: 1, max: 64)();
  TextColumn get role => text().withLength(min: 1, max: 30)();
  RealColumn get approvalLimit => real().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

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
  /// v16: the budget line this order is committed against.
  TextColumn get costCodeId => text().withLength(max: 36).nullable()();

  /// v32: the supplier says it is on its way, from their free portal
  /// (pulled only; the builder's phone never sends these).
  DateTimeColumn get dispatchedOn => dateTime().nullable()();
  TextColumn get dispatchVehicle => text().withLength(max: 60).nullable()();
  TextColumn get supplierNote => text().withLength(max: 500).nullable()();

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
  /// v16: the budget line this expense is an actual cost of.
  TextColumn get costCodeId => text().withLength(max: 36).nullable()();

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

  /// The photo taken at punch-in ([AttendancePhotos]); one roll-call photo
  /// can stand for everyone punched in together.
  TextColumn get photoId => text().withLength(max: 36).nullable()();

  /// How far from the site's centre the GPS put the punch, and how sure
  /// the phone was of it.
  RealColumn get distanceM => real().nullable()();
  RealColumn get accuracyM => real().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A photo taken when someone is punched in or checks in: the worker or
/// the morning roll call, or a staff member's selfie. Stamped with the
/// time and GPS, and kept as evidence (never edited).
class AttendancePhotos extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get filePath => text().withLength(min: 1, max: 500)();
  TextColumn get mimeType => text().withLength(max: 100).withDefault(const Constant('image/jpeg'))();
  TextColumn get takenBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get takenAt => dateTime()();
  RealColumn get lat => real().nullable()();
  RealColumn get lng => real().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A staff member marking their own day at a site: a selfie and a GPS fix
/// at check-in and check-out. Inside the site's geofence the day counts
/// at once; outside it (or with no fix) it waits for an owner or manager.
class StaffAttendance extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withLength(min: 1, max: 36)();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get userId => text().withLength(min: 1, max: 64)();

  /// yyyy-MM-dd, the phone's local day of the check-in.
  TextColumn get day => text().withLength(min: 10, max: 10)();
  DateTimeColumn get checkIn => dateTime()();
  DateTimeColumn get checkOut => dateTime().nullable()();
  RealColumn get inLat => real().nullable()();
  RealColumn get inLng => real().nullable()();
  RealColumn get inAccuracyM => real().nullable()();
  RealColumn get inDistanceM => real().nullable()();
  TextColumn get inPhotoId => text().withLength(max: 36).nullable()();
  BoolColumn get withinGeofence => boolean().nullable()();
  RealColumn get outLat => real().nullable()();
  RealColumn get outLng => real().nullable()();
  RealColumn get outDistanceM => real().nullable()();
  TextColumn get outPhotoId => text().withLength(max: 36).nullable()();
  BoolColumn get outWithin => boolean().nullable()();

  /// ok (inside the site) | pending (waits for a manager) | approved | rejected
  TextColumn get status => text().withLength(min: 1, max: 10).withDefault(const Constant('pending'))();

  /// Why they checked in away from the site (meeting, supplier's yard...).
  TextColumn get reason => text().withLength(max: 300).nullable()();
  TextColumn get reviewedBy => text().withLength(max: 64).nullable()();
  DateTimeColumn get reviewedAt => dateTime().nullable()();
  TextColumn get reviewNote => text().withLength(max: 300).nullable()();
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

/// A bill, receipt or quotation kept with an expense: a photo or a PDF.
/// The file stays on the phone that added it, like DPR photos (v14).
class ExpenseAttachments extends Table {
  TextColumn get id => text()();
  TextColumn get expenseId => text().withLength(min: 1, max: 36)();
  TextColumn get filePath => text().withLength(min: 1, max: 500)();
  /// image/jpeg, image/png or application/pdf.
  TextColumn get mimeType => text().withLength(max: 100)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The site's notebook: what was agreed with the client, measurements to
/// check, phone numbers, reminders (v14, synced as site_notes). A removed
/// note is marked [deleted] rather than dropped, because pulls don't carry
/// deletes.
class ProjectNotes extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get body => text().withLength(min: 1, max: 4000)();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  TextColumn get createdBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
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

  // v16, commercial controls: the agreed quantity, unit and rate are the
  // baseline. Approved variations add to the order; the baseline itself is
  // never rewritten once work is certified (the server refuses it).
  TextColumn get unit => text().withLength(max: 20).nullable()();
  RealColumn get contractQty => real().nullable()();
  RealColumn get rate => real().nullable()();
  TextColumn get costCodeId => text().withLength(max: 36).nullable()();

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

/// The delivery slip or challan photographed when material arrives (v15,
/// synced as site_receipt_attachments with the file in Storage). It used
/// to sit in the receipt's note as a path on the supervisor's phone, so
/// the manager approving the delivery never saw it.
class ReceiptAttachments extends Table {
  TextColumn get id => text()();
  TextColumn get receiptId => text().withLength(min: 1, max: 36)();
  TextColumn get filePath => text().withLength(min: 1, max: 500)();
  TextColumn get mimeType => text().withLength(max: 100)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The weekly site close (v15, synced as site_close_reviews): one row per
/// decision on one item of one site's week (a worker's wages, an expense,
/// a delivery, a day without attendance, or the week itself). Rows are
/// never changed or removed, so the week keeps a dated record of what was
/// approved, sent back and corrected, and by whom. What the item looked
/// like when it was decided is kept in [fingerprint]; an item edited after
/// its approval comes back to the queue.
class CloseReviews extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();

  /// Monday of the week, yyyy-mm-dd.
  TextColumn get weekStart => text().withLength(min: 10, max: 10)();

  /// wages | expense | receipt | attendance | week
  TextColumn get itemKind => text().withLength(min: 1, max: 20)();

  /// The record's id; a worker's wage line key; a day (yyyy-mm-dd); 'week'.
  TextColumn get itemId => text().withLength(min: 1, max: 160)();

  /// approved | sent_back | fixed | closed | reopened
  TextColumn get decision => text().withLength(min: 1, max: 20)();
  TextColumn get note => text().withLength(max: 300).nullable()();
  TextColumn get fingerprint => text().withLength(max: 200).nullable()();

  /// The money the decision covered (wages earned, expense, invoice).
  RealColumn get amount => real().nullable()();

  /// For a delivery: the quantity the manager accepted.
  RealColumn get acceptedQty => real().nullable()();
  TextColumn get decidedBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// --- v16: commercial controls (FOS-201 to FOS-204) --------------------------
// See supabase/migrations/20261110100000_commercial_controls.sql. Claims,
// certifications, variation decisions and exception actions are only ever
// added, never changed, so a payment can be traced back to the agreement
// and the site evidence as it happened.

/// A budget line of one site (synced as cost_codes).
class CostCodes extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get code => text().withLength(min: 1, max: 30)();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  RealColumn get originalBudget => real().withDefault(const Constant(0))();

  /// Still to be bought or let, beyond what is already committed.
  RealColumn get uncommittedEstimate => real().withDefault(const Constant(0))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Whether a site is seen only by its team (v17, synced as site_access).
/// [id] is the project's id. Sites without a row are open to the company.
class SiteAccess extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  BoolColumn get membersOnly => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Quantity a subcontractor says is complete against a work order.
class WorkClaims extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get workOrderId => text().withLength(min: 1, max: 36)();
  RealColumn get qty => real()();
  TextColumn get location => text().withLength(max: 120).nullable()();
  TextColumn get note => text().withLength(max: 300).nullable()();
  TextColumn get submittedBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The engineer's decision on (part of) a claim.
class WorkCertifications extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get workOrderId => text().withLength(min: 1, max: 36)();
  TextColumn get claimId => text().withLength(min: 1, max: 36)();
  RealColumn get acceptedQty => real().withDefault(const Constant(0))();
  RealColumn get rejectedQty => real().withDefault(const Constant(0))();
  TextColumn get variationId => text().withLength(max: 36).nullable()();
  TextColumn get note => text().withLength(max: 300).nullable()();
  TextColumn get certifiedBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A scope change (change order). Pending until it has a decision.
class Variations extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get workOrderId => text().withLength(max: 36).nullable()();
  TextColumn get costCodeId => text().withLength(max: 36).nullable()();
  TextColumn get title => text().withLength(min: 1, max: 200)();

  /// claim_over_order | client_instruction | design_change | site_condition | other
  TextColumn get origin => text().withLength(min: 1, max: 30)();
  TextColumn get sourceClaimId => text().withLength(max: 36).nullable()();
  RealColumn get qty => real().nullable()();
  TextColumn get unit => text().withLength(max: 20).nullable()();
  RealColumn get estimatedCost => real().withDefault(const Constant(0))();
  IntColumn get scheduleDays => integer().withDefault(const Constant(0))();
  TextColumn get ownerId => text().withLength(max: 64).nullable()();
  TextColumn get note => text().withLength(max: 500).nullable()();
  TextColumn get raisedBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The one decision on a variation.
class VariationDecisions extends Table {
  TextColumn get id => text()();
  TextColumn get variationId => text().withLength(min: 1, max: 36)();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();

  /// approved | rejected
  TextColumn get decision => text().withLength(min: 1, max: 20)();
  RealColumn get approvedQty => real().nullable()();
  RealColumn get approvedCost => real().nullable()();
  TextColumn get note => text().withLength(max: 300).nullable()();
  TextColumn get decidedBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {variationId},
      ];
}

/// Site evidence (photos) for a claim, a certification or a variation.
class CommercialAttachments extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();

  /// claim | certification | variation
  TextColumn get parentKind => text().withLength(min: 1, max: 20)();
  TextColumn get parentId => text().withLength(min: 1, max: 36)();
  TextColumn get filePath => text().withLength(min: 1, max: 500)();
  TextColumn get mimeType => text().withLength(max: 100)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Who owns a commercial exception, by when, and what was decided.
class ExceptionActions extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get exceptionKey => text().withLength(min: 3, max: 120)();

  /// assigned | resolved | reopened
  TextColumn get action => text().withLength(min: 1, max: 20)();
  TextColumn get ownerId => text().withLength(max: 64).nullable()();

  /// yyyy-mm-dd
  TextColumn get dueOn => text().withLength(max: 10).nullable()();
  TextColumn get note => text().withLength(max: 300).nullable()();
  TextColumn get fingerprint => text().withLength(max: 200).nullable()();
  TextColumn get actedBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The measurement book for the client (v18, synced as
/// site_work_measurements): work measured against a BOQ item. Never
/// edited; a negative quantity corrects an earlier one.
class WorkMeasurements extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get costHeadId => text().withLength(max: 36).nullable()();
  TextColumn get description => text().withLength(min: 1, max: 200)();
  TextColumn get unit => text().withLength(min: 1, max: 20)();
  RealColumn get rate => real().nullable()();
  RealColumn get qty => real()();
  DateTimeColumn get measuredOn => dateTime()();
  TextColumn get location => text().withLength(max: 200).nullable()();
  TextColumn get note => text().withLength(max: 300).nullable()();
  TextColumn get measuredBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The owner's or PM's decision on a measurement, one each (v18).
class WorkMeasurementDecisions extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get measurementId => text().withLength(min: 1, max: 36)();

  /// approved | rejected
  TextColumn get decision => text().withLength(min: 1, max: 20)();
  RealColumn get approvedQty => real().nullable()();
  TextColumn get note => text().withLength(max: 300).nullable()();
  TextColumn get decidedBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {measurementId},
      ];
}

/// Part of a payment received put against a bill, or against its
/// retention (v18, synced as site_bill_allocations).
class BillAllocations extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get paymentId => text().withLength(min: 1, max: 36)();
  TextColumn get billId => text().withLength(min: 1, max: 36)();

  /// bill | retention
  TextColumn get kind => text().withLength(min: 1, max: 20).withDefault(const Constant('bill'))();
  RealColumn get amount => real()();
  TextColumn get note => text().withLength(max: 300).nullable()();
  TextColumn get createdBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A supplier's invoice, matched against its PO and the GRNs (v18,
/// synced as site_supplier_invoices). Only ever cancelled, never edited.
class SupplierInvoices extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get supplierId => text().withLength(min: 1, max: 36)();
  TextColumn get poId => text().withLength(max: 36).nullable()();
  TextColumn get invoiceNumber => text().withLength(min: 1, max: 40)();
  DateTimeColumn get invoiceDate => dateTime()();
  RealColumn get amount => real()();
  RealColumn get gstAmount => real().withDefault(const Constant(0))();
  RealColumn get qty => real().nullable()();
  TextColumn get note => text().withLength(max: 300).nullable()();
  BoolColumn get voided => boolean().withDefault(const Constant(false))();
  TextColumn get voidReason => text().withLength(max: 200).nullable()();
  TextColumn get recordedBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// v21: CRM -- enquiries before they are sites. Company-wide, owner and
// project managers only (the server's row level security says the same).
// ---------------------------------------------------------------------------

/// Someone who may give the company work: a plot owner, a builder, a
/// society. Moves new -> contacted -> site_visit -> quoted -> negotiation,
/// and ends won (a site is made from it) or lost (with the reason).
class CrmLeads extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withLength(min: 1, max: 36)();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get phone => text().withLength(max: 30).nullable()();
  TextColumn get email => text().withLength(max: 120).nullable()();

  /// Where the work is: a plot, an area, a building.
  TextColumn get location => text().withLength(max: 300).nullable()();

  /// referral | walk_in | website | social | builder | repeat | other
  TextColumn get source => text().withLength(min: 1, max: 20).withDefault(const Constant('other'))();

  /// What they want built: "G+2 house", "Interiors, 3BHK".
  TextColumn get workType => text().withLength(max: 200).nullable()();
  RealColumn get estimatedValue => real().nullable()();

  /// new | contacted | site_visit | quoted | negotiation | won | lost
  TextColumn get stage => text().withLength(min: 1, max: 20).withDefault(const Constant('new'))();
  TextColumn get lostReason => text().withLength(max: 300).nullable()();

  /// Who is following it up (a user id).
  TextColumn get ownerId => text().withLength(max: 64).nullable()();
  DateTimeColumn get nextFollowUp => dateTime().nullable()();
  TextColumn get notes => text().withLength(max: 1000).nullable()();

  /// The site made from it once won.
  TextColumn get projectId => text().withLength(max: 36).nullable()();
  TextColumn get createdBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A call, visit, meeting or note on a lead. Never edited: the history is
/// what was said, in order.
class CrmActivities extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withLength(min: 1, max: 36)();
  TextColumn get leadId => text().withLength(min: 1, max: 36)();

  /// call | visit | meeting | whatsapp | note | stage
  TextColumn get kind => text().withLength(min: 1, max: 20)();
  TextColumn get note => text().withLength(max: 1000)();
  TextColumn get byUser => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A priced offer to a lead. Lines are kept as JSON (description, unit,
/// qty, rate), like a client bill's.
class CrmQuotes extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withLength(min: 1, max: 36)();
  TextColumn get leadId => text().withLength(min: 1, max: 36)();
  TextColumn get quoteNumber => text().withLength(min: 1, max: 40)();
  DateTimeColumn get quoteDate => dateTime()();
  DateTimeColumn get validUntil => dateTime().nullable()();

  /// draft | sent | accepted | rejected
  TextColumn get status => text().withLength(min: 1, max: 20).withDefault(const Constant('draft'))();
  TextColumn get linesJson => text().withDefault(const Constant('[]'))();
  RealColumn get gstRate => real().withDefault(const Constant(18))();
  BoolColumn get interState => boolean().withDefault(const Constant(false))();

  /// A flat amount off before GST.
  RealColumn get discount => real().withDefault(const Constant(0))();

  /// The grand total with GST, kept so lists and the pipeline don't decode
  /// every quote.
  RealColumn get total => real().withDefault(const Constant(0))();
  TextColumn get terms => text().withLength(max: 2000).nullable()();
  TextColumn get createdBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// --- v22: central stores, tools register, monthly staff salaries ----------

/// A company store or warehouse that holds material between purchase and
/// the sites (the yard, the godown behind the office).
class Stores extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withLength(min: 1, max: 36)();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get location => text().withLength(max: 300).nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  TextColumn get createdBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Material moving into a store, between stores and sites, or written off.
/// Each place is a store or a site, never both. A transfer is on the way
/// until the receiving end counts what arrived.
class StockMoves extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withLength(min: 1, max: 36)();

  /// inward (bought into a store) | transfer | adjust (count correction).
  TextColumn get kind => text().withLength(min: 1, max: 20)();
  TextColumn get fromStoreId => text().withLength(max: 36).nullable()();
  TextColumn get fromProjectId => text().withLength(max: 36).nullable()();
  TextColumn get toStoreId => text().withLength(max: 36).nullable()();
  TextColumn get toProjectId => text().withLength(max: 36).nullable()();
  TextColumn get supplierName => text().withLength(max: 120).nullable()();
  TextColumn get materialName => text().withLength(min: 1, max: 200)();
  TextColumn get unit => text().withLength(max: 20).nullable()();
  RealColumn get quantity => real()();

  /// Rupees a unit, for the value of what moved.
  RealColumn get rate => real().nullable()();

  /// in_transit | received | cancelled
  TextColumn get status => text().withLength(min: 1, max: 20).withDefault(const Constant('received'))();

  /// What the receiving end counted; less than [quantity] is a shortage.
  RealColumn get receivedQty => real().nullable()();
  TextColumn get vehicle => text().withLength(max: 40).nullable()();
  TextColumn get note => text().withLength(max: 300).nullable()();
  TextColumn get sentBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get sentOn => dateTime()();
  TextColumn get receivedBy => text().withLength(max: 64).nullable()();
  DateTimeColumn get receivedOn => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A tool or small machine the company owns (drill, vibrator, level).
/// Where it is and who has it come from its issues.
class Tools extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withLength(min: 1, max: 36)();
  TextColumn get name => text().withLength(min: 1, max: 120)();

  /// Asset tag painted on it.
  TextColumn get code => text().withLength(max: 40).nullable()();
  TextColumn get category => text().withLength(max: 60).nullable()();
  RealColumn get value => real().nullable()();
  TextColumn get storeId => text().withLength(max: 36).nullable()();

  /// in_use (normal) | repair | retired. Issued and lost come from issues.
  TextColumn get condition => text().withLength(min: 1, max: 20).withDefault(const Constant('in_use'))();
  TextColumn get notes => text().withLength(max: 300).nullable()();
  TextColumn get createdBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A tool handed to a person, and how it came back.
class ToolIssues extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withLength(min: 1, max: 36)();
  TextColumn get toolId => text().withLength(min: 1, max: 36)();
  TextColumn get projectId => text().withLength(max: 36).nullable()();
  TextColumn get issuedTo => text().withLength(min: 1, max: 120)();
  TextColumn get workerId => text().withLength(max: 36).nullable()();
  TextColumn get issuedBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get issuedOn => dateTime()();
  DateTimeColumn get dueBack => dateTime().nullable()();
  DateTimeColumn get returnedOn => dateTime().nullable()();

  /// ok | damaged | lost, once it is back (or known lost).
  TextColumn get returnCondition => text().withLength(max: 20).nullable()();

  /// To be recovered from the person for a damaged or lost tool.
  RealColumn get recoverAmount => real().nullable()();
  TextColumn get note => text().withLength(max: 300).nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Monthly salaried staff (engineers, supervisors, accounts, drivers), as
/// opposed to daily-wage workers on the wage sheet.
class StaffMembers extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withLength(min: 1, max: 36)();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get phone => text().withLength(max: 30).nullable()();
  TextColumn get designation => text().withLength(max: 80).nullable()();

  /// The site whose costs the salary is charged to, if any.
  TextColumn get projectId => text().withLength(max: 36).nullable()();

  /// Monthly salary parts, for a full month.
  RealColumn get basic => real()();
  RealColumn get hra => real().withDefault(const Constant(0))();
  RealColumn get otherAllowance => real().withDefault(const Constant(0))();
  BoolColumn get pf => boolean().withDefault(const Constant(true))();
  BoolColumn get esi => boolean().withDefault(const Constant(true))();

  /// Professional tax slabs: TS | AP | none.
  TextColumn get ptState => text().withLength(min: 1, max: 10).withDefault(const Constant('TS'))();
  TextColumn get uan => text().withLength(max: 20).nullable()();
  DateTimeColumn get joinedOn => dateTime().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();

  /// Their FieldOS login, so the days they check in at a site show
  /// beside their salary.
  TextColumn get userId => text().withLength(max: 64).nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Money given to a staff member ahead of salary, recovered from payslips.
class StaffAdvances extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withLength(min: 1, max: 36)();
  TextColumn get staffId => text().withLength(min: 1, max: 36)();
  RealColumn get amount => real()();
  DateTimeColumn get givenOn => dateTime()();
  TextColumn get note => text().withLength(max: 200).nullable()();
  TextColumn get createdBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One staff member's salary for one month: days, earnings, deductions,
/// what was paid. One row per person per month.
class PayrollLines extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withLength(min: 1, max: 36)();
  TextColumn get staffId => text().withLength(min: 1, max: 36)();

  /// 2026-11
  TextColumn get month => text().withLength(min: 7, max: 7)();
  IntColumn get daysInMonth => integer()();
  RealColumn get paidDays => real()();
  RealColumn get basic => real()();
  RealColumn get hra => real()();
  RealColumn get otherAllowance => real()();
  RealColumn get gross => real()();
  RealColumn get pfEmployee => real()();
  RealColumn get esiEmployee => real()();
  RealColumn get pt => real()();
  RealColumn get advanceRecovery => real()();
  RealColumn get otherDeduction => real()();
  RealColumn get net => real()();
  RealColumn get pfEmployer => real()();
  RealColumn get esiEmployer => real()();

  /// draft | paid
  TextColumn get status => text().withLength(min: 1, max: 10).withDefault(const Constant('draft'))();
  DateTimeColumn get paidOn => dateTime().nullable()();
  TextColumn get paidMode => text().withLength(max: 20).nullable()();
  TextColumn get projectId => text().withLength(max: 36).nullable()();
  TextColumn get expenseId => text().withLength(max: 36).nullable()();
  TextColumn get createdBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// --- v23: supplier quotes against a purchase request ------------------------

/// A supplier's price for a purchase request, so several can be compared
/// side by side and the best one turned into the PO.
class SupplierQuotes extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get requestId => text().withLength(min: 1, max: 36)();
  TextColumn get supplierId => text().withLength(min: 1, max: 36)();

  /// Rupees a unit of the request, before GST.
  RealColumn get rate => real()();
  RealColumn get gstPct => real().withDefault(const Constant(18))();

  /// Freight and unloading, as quoted.
  RealColumn get transport => real().withDefault(const Constant(0))();
  IntColumn get deliveryDays => integer().nullable()();
  TextColumn get paymentTerms => text().withLength(max: 120).nullable()();
  DateTimeColumn get validUntil => dateTime().nullable()();
  TextColumn get notes => text().withLength(max: 300).nullable()();

  /// received | accepted | rejected
  TextColumn get status => text().withLength(min: 1, max: 20).withDefault(const Constant('received'))();
  TextColumn get poId => text().withLength(max: 36).nullable()();
  TextColumn get createdBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// An owner's rule (v30, synced as site_approval_rules): above
/// [aboveAmount], a [kind] of item needs [role]'s approval. kind:
/// purchase_request | expense | purchase_order; role: project_manager |
/// owner. Changed by voiding and adding, or by a new amount.
class ApprovalRules extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withLength(min: 1, max: 36)();
  TextColumn get kind => text().withLength(min: 1, max: 20)();
  TextColumn get role => text().withLength(min: 1, max: 20)();
  RealColumn get aboveAmount => real()();
  BoolColumn get voided => boolean().withDefault(const Constant(false))();
  TextColumn get createdBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One signature on an item's approval chain (v30, synced as
/// site_approval_steps, insert-only). [level]: project_manager | owner;
/// [decision]: approved | rejected. [amount] is the item's amount when
/// signed (the server sets it from the record).
class ApprovalSteps extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get kind => text().withLength(min: 1, max: 20)();
  TextColumn get itemId => text().withLength(min: 1, max: 36)();
  TextColumn get level => text().withLength(min: 1, max: 20)();
  TextColumn get decision => text().withLength(min: 1, max: 20)();
  RealColumn get amount => real().nullable()();
  TextColumn get note => text().withLength(max: 300).nullable()();
  TextColumn get decidedBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Daily site close (v31). See features/daily/day_close.dart for the rules
// and supabase/migrations/20261110200000_daily_site_close.sql for the
// server's copy.
// ---------------------------------------------------------------------------

/// Everything said about one site's day, only ever added to: the
/// supervisor submitting it (with what was explicitly "nothing to report"),
/// reopening it, why it was missed, a manager following up, and an
/// approver's recorded override or partial release.
class SiteDayEvents extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();

  /// The day the work happened (yyyy-mm-dd). The entry date is [createdAt].
  TextColumn get workDate => text().withLength(min: 10, max: 10)();

  /// submitted | reopened | miss_reason | follow_up | override | partial
  TextColumn get kind => text().withLength(min: 1, max: 20)();
  BoolColumn get siteClosed => boolean().withDefault(const Constant(false))();
  BoolColumn get noDeliveries => boolean().withDefault(const Constant(false))();
  BoolColumn get noExpenses => boolean().withDefault(const Constant(false))();

  /// For a miss: forgot | poor_signal | too_much_work | other.
  TextColumn get reason => text().withLength(max: 20).nullable()();
  TextColumn get note => text().withLength(max: 300).nullable()();

  /// What a submission covered (people, deliveries, expenses), so the
  /// manager sees whether it changed after it was sent.
  TextColumn get fingerprint => text().withLength(max: 200).nullable()();

  /// Overrides and partial releases: the money and the weekly item
  /// (`wages:<key>`, `expense:<id>`, `receipt:<id>`).
  RealColumn get amount => real().nullable()();
  TextColumn get itemRef => text().withLength(max: 160).nullable()();
  TextColumn get recordedBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A site's daily close setup. [id] is the project id (one row per site).
class SiteCloseSettings extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();

  /// Minutes after midnight by which the day's report is due.
  IntColumn get cutoffMinutes => integer().withDefault(const Constant(19 * 60))();
  TextColumn get supervisorId => text().withLength(max: 64).nullable()();

  /// Covers the site's report while [backupUntil] (yyyy-mm-dd, inclusive)
  /// lasts.
  TextColumn get backupId => text().withLength(max: 64).nullable()();
  TextColumn get backupUntil => text().withLength(max: 10).nullable()();
  TextColumn get updatedBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// When each teammate's phone last reached the server, as the server saw
/// it. Read only; refreshed on every sync.
class MemberSyncStatus extends Table {
  TextColumn get userId => text().withLength(min: 1, max: 64)();
  TextColumn get companyId => text().withLength(min: 1, max: 36)();
  DateTimeColumn get lastSyncedAt => dateTime()();

  /// Changes still waiting on that phone when it last synced.
  IntColumn get pending => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {companyId, userId};
}

/// v36, the site cash book: cash handed to someone on site ([kind] given),
/// handed back (returned) and counted in their hand (counted). What they
/// spent is their own cash expenses on the site, so it is never stored
/// twice. Entries are only cancelled ([voided]), never changed. Synced as
/// site_cash_moves (20261111100000_site_cash_book.sql).
class CashMoves extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();

  /// The person holding the cash (a user id, like recordedBy).
  TextColumn get holderId => text().withLength(min: 1, max: 64)();

  /// given | returned | counted
  TextColumn get kind => text().withLength(min: 1, max: 10)();

  /// For a count, the cash found in hand (may be 0).
  RealColumn get amount => real()();

  /// yyyy-mm-dd
  TextColumn get movedOn => text().withLength(min: 10, max: 10)();
  TextColumn get note => text().withLength(max: 300).nullable()();
  TextColumn get recordedBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get voided => boolean().withDefault(const Constant(false))();
  TextColumn get voidReason => text().withLength(max: 200).nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// v37, progress by block and floor for the RERA quarterly report. Each
/// update is a new row; the latest on or before a date is the progress
/// then. Synced as site_floor_progress (20261111110000_floor_progress.sql).
class FloorProgress extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get block => text().withLength(min: 1, max: 60)();
  TextColumn get floor => text().withLength(min: 1, max: 30)();

  /// not_started | excavation | foundation | plinth | columns | slab |
  /// masonry | plastering | flooring | finishing | complete
  TextColumn get stage => text().withLength(min: 1, max: 20)();
  IntColumn get pct => integer()();

  /// yyyy-mm-dd
  TextColumn get asOf => text().withLength(min: 10, max: 10)();
  TextColumn get note => text().withLength(max: 300).nullable()();
  TextColumn get recordedBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// v38, change history: the row as it was (and became) each time an
/// expense, payment, receipt, usage, bill, punch, supplier invoice or work
/// measurement was changed or deleted, and who did it. Written only by the
/// server (20261111120000_entry_history.sql) and pulled; never pushed.
class EntryHistory extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();

  /// The server table, e.g. site_expenses.
  TextColumn get sourceTable => text().withLength(min: 1, max: 60)();
  TextColumn get rowId => text().withLength(min: 1, max: 36)();

  /// update | delete
  TextColumn get op => text().withLength(min: 1, max: 10)();
  TextColumn get oldJson => text()();
  TextColumn get newJson => text().nullable()();
  TextColumn get changedBy => text().withLength(max: 64).nullable()();
  DateTimeColumn get changedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// --- v40: site execution (FOS-205 to FOS-209) -------------------------------
// See supabase/migrations/20261112100000_site_execution.sql. Synced through
// the generic mappers in sync/site_execution_sync.dart (one snake_case
// column on the server per field here).

/// Something a task needs before it can start: material, a drawing, an
/// answer to an RFI, a hold point release, labour, a permit (FOS-205).
class TaskConstraints extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get taskId => text().withLength(min: 1, max: 36)();

  /// material | drawing | rfi | hold_point | labour | equipment | permit | predecessor | other
  TextColumn get kind => text().withLength(min: 1, max: 20)();
  TextColumn get description => text().withLength(min: 1, max: 300)();
  TextColumn get ownerId => text().withLength(max: 64).nullable()();

  /// yyyy-mm-dd: when it must be cleared for the task to start on time.
  TextColumn get needBy => text().withLength(max: 10).nullable()();

  /// The RFI, drawing or hold point it waits on, if any: it clears itself
  /// when that record does.
  TextColumn get linkId => text().withLength(max: 36).nullable()();
  DateTimeColumn get clearedAt => dateTime().nullable()();
  TextColumn get clearedBy => text().withLength(max: 64).nullable()();
  TextColumn get clearNote => text().withLength(max: 300).nullable()();
  TextColumn get raisedBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A drawing in the site's register (FOS-206). Its revisions hold the files.
class Drawings extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get number => text().withLength(min: 1, max: 40)();
  TextColumn get title => text().withLength(min: 1, max: 200)();

  /// architectural | structural | mep | landscape | other
  TextColumn get discipline => text().withLength(min: 1, max: 20).withDefault(const Constant('architectural'))();
  TextColumn get createdBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One revision of a drawing, with its file. Only the latest approved
/// revision is shown on site; older ones stay in the register.
class DrawingRevisions extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get drawingId => text().withLength(min: 1, max: 36)();
  TextColumn get rev => text().withLength(min: 1, max: 10)();
  TextColumn get filePath => text().withLength(min: 1, max: 500)();
  TextColumn get mimeType => text().withLength(max: 100)();
  TextColumn get note => text().withLength(max: 300).nullable()();

  /// pending | approved | rejected
  TextColumn get status => text().withLength(min: 1, max: 20).withDefault(const Constant('pending'))();
  TextColumn get decidedBy => text().withLength(max: 64).nullable()();
  DateTimeColumn get decidedAt => dateTime().nullable()();
  TextColumn get decisionNote => text().withLength(max: 300).nullable()();
  TextColumn get uploadedBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A request for information to the designer or client (FOS-206).
class Rfis extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get question => text().withLength(min: 1, max: 1000)();
  TextColumn get drawingId => text().withLength(max: 36).nullable()();
  TextColumn get taskId => text().withLength(max: 36).nullable()();

  /// Who must answer: a person in the company, or a name outside it.
  TextColumn get assigneeId => text().withLength(max: 64).nullable()();
  TextColumn get askedOf => text().withLength(max: 120).nullable()();

  /// yyyy-mm-dd
  TextColumn get dueOn => text().withLength(max: 10).nullable()();
  TextColumn get answer => text().withLength(max: 1000).nullable()();
  TextColumn get answeredBy => text().withLength(max: 64).nullable()();
  DateTimeColumn get answeredAt => dateTime().nullable()();

  /// open | answered | closed
  TextColumn get status => text().withLength(min: 1, max: 20).withDefault(const Constant('open'))();
  TextColumn get raisedBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A quality hold point: work at this place does not go on until it is
/// inspected and released (FOS-207).
class HoldPoints extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get taskId => text().withLength(max: 36).nullable()();
  TextColumn get unitId => text().withLength(max: 36).nullable()();

  /// Block, floor, zone or grid as people on site say it.
  TextColumn get location => text().withLength(max: 120).nullable()();

  /// pending | released | rejected
  TextColumn get status => text().withLength(min: 1, max: 20).withDefault(const Constant('pending'))();
  TextColumn get decidedBy => text().withLength(max: 64).nullable()();
  DateTimeColumn get decidedAt => dateTime().nullable()();
  TextColumn get note => text().withLength(max: 300).nullable()();
  TextColumn get raisedBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A defect or snag, from raised to fixed to closed (FOS-207).
class Defects extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get unitId => text().withLength(max: 36).nullable()();
  TextColumn get location => text().withLength(max: 120).nullable()();
  TextColumn get description => text().withLength(min: 1, max: 500)();

  /// minor | major | critical
  TextColumn get severity => text().withLength(min: 1, max: 10).withDefault(const Constant('minor'))();
  TextColumn get assigneeId => text().withLength(max: 64).nullable()();
  TextColumn get subcontractorId => text().withLength(max: 36).nullable()();

  /// yyyy-mm-dd
  TextColumn get dueOn => text().withLength(max: 10).nullable()();

  /// open | fixed | closed. A fix that does not pass goes back to open.
  TextColumn get status => text().withLength(min: 1, max: 10).withDefault(const Constant('open'))();
  TextColumn get fixedBy => text().withLength(max: 64).nullable()();
  DateTimeColumn get fixedAt => dateTime().nullable()();
  TextColumn get fixNote => text().withLength(max: 300).nullable()();
  TextColumn get closedBy => text().withLength(max: 64).nullable()();
  DateTimeColumn get closedAt => dateTime().nullable()();
  IntColumn get reopenCount => integer().withDefault(const Constant(0))();
  TextColumn get raisedBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Photos for defects (before and after), hold points and RFIs.
class ExecutionPhotos extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();

  /// defect | defect_fix | hold_point | rfi
  TextColumn get parentKind => text().withLength(min: 1, max: 20)();
  TextColumn get parentId => text().withLength(min: 1, max: 36)();
  TextColumn get filePath => text().withLength(min: 1, max: 500)();
  TextColumn get mimeType => text().withLength(max: 100)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A flat, villa, shop or zone that is handed over on its own (FOS-208).
class HandoverUnits extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get block => text().withLength(max: 60).nullable()();
  TextColumn get floor => text().withLength(max: 30).nullable()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get handedTo => text().withLength(max: 120).nullable()();
  DateTimeColumn get handedOverAt => dateTime().nullable()();
  TextColumn get handedOverBy => text().withLength(max: 64).nullable()();
  TextColumn get handoverNote => text().withLength(max: 300).nullable()();
  TextColumn get createdBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One line of a unit's handover checklist.
class HandoverChecks extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().withLength(min: 1, max: 36)();
  TextColumn get unitId => text().withLength(min: 1, max: 36)();
  TextColumn get item => text().withLength(min: 1, max: 200)();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  TextColumn get doneBy => text().withLength(max: 64).nullable()();
  DateTimeColumn get doneAt => dateTime().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The company's own standard lists, used on every site (FOS-209): hold
/// points every slab gets, the handover checklist every flat gets.
class CompanyStandards extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withLength(min: 1, max: 36)();

  /// hold_point | handover_check
  TextColumn get kind => text().withLength(min: 1, max: 20)();
  TextColumn get item => text().withLength(min: 1, max: 200)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get createdBy => text().withLength(min: 1, max: 64)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
