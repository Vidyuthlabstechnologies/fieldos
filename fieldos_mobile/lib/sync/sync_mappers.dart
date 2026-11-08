/// Drift row -> Supabase (Postgres, snake_case) JSON mappers.
///
/// Deliberately explicit, one function per table, rather than reflection --
/// this is the one place a Dart camelCase/Postgres snake_case mismatch
/// would silently corrupt synced data, so every field is named out loud and
/// checked against supabase/migrations/20260823000000_initial_schema.sql by
/// hand, not inferred.
///
/// Project, Task, DprEntry, Issue, Worker, Equipment, Inspection,
/// Subcontractor, WorkOrder, Approval, Supplier (-> `vendors`), the
/// estimation tree (Estimation -> CostHead -> Measurement/SteelEntry), and
/// the procurement core (PurchaseRequest -> `purchase_requisitions`,
/// PurchaseOrder -> `purchase_orders`, including status changes) are
/// covered -- chosen because their Drift columns correspond 1:1 with the
/// Postgres schema. The mobile procurement tables were deliberately brought
/// into alignment first (status vocabularies now use the remote CHECK
/// values; see tables.dart) rather than mapped while divergent. Not every
/// mobile table does correspond:
///  - MaterialReceipts has no honest mapping to either synced-shape table:
///    desktop's material_entries is a simple consumption log, and Postgres's
///    own `grns` requires a purchase_order_id (mobile allows ad-hoc receipts
///    with no PO), splits ordered_qty/received_qty where mobile stores one
///    quantity plus an amount, and has no home for cost_head_id -- which is
///    what feeds mobile's cost-engine actuals.
///  - rfqs and quotes have no mobile tables at all. A PO's quote_id is
///    preserved as an opaque uuid column so remote-created linkage isn't
///    dropped on pull, but creating/quoting RFQs from mobile means building
///    those features, not mapping existing ones.
///  - LabourAttendance is a punch-in/punch-out GPS-geofence event log;
///    Postgres's `attendance` is a daily present/absent/half_day summary
///    keyed by (worker_id, date). These aren't the same shape at all --
///    syncing would need a real punches-to-daily-summary aggregation, not
///    a column mapping.
/// Forcing any of the above would silently corrupt or mislead, so they're
/// deliberately NOT wired to those tables. Since schema v7 the phone's own
/// shapes sync instead, to phone-shaped cloud tables (site_attendance,
/// site_material_receipts, plus site_expenses, site_material_usage and
/// site_payments_received): see the section at the end of this file.
/// EquipmentLogs and InspectionItems (child rows of Equipment/Inspection)
/// sync too, checked column by column against the initial schema
/// (equipment_logs.log_type and inspection_items.status use the same
/// vocabularies as the phone). Extending to the rest of the ~30 tables is
/// a follow-up, same pattern, per-table -- verify the shapes actually
/// correspond before wiring, the way this file's docstring itself
/// demonstrates by omission.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:fieldos_mobile/data/app_database.dart';

String? _dateOnly(DateTime? d) => d?.toIso8601String().split('T').first;
String? _timestamp(DateTime? d) => d?.toIso8601String();

Map<String, dynamic> projectToSupabaseJson(Project p) => {
      'id': p.id,
      'company_id': p.companyId,
      'name': p.name,
      'client_name': p.clientName,
      'location_lat': p.locationLat,
      'location_lng': p.locationLng,
      'geofence_radius_m': p.geofenceRadiusM,
      'start_date': _dateOnly(p.startDate),
      'end_date': _dateOnly(p.endDate),
      'status': p.status,
    };

Map<String, dynamic> taskToSupabaseJson(Task t) => {
      'id': t.id,
      'project_id': t.projectId,
      'title': t.title,
      'assignee_id': t.assigneeId,
      'due_date': _dateOnly(t.dueDate),
      'status': t.status,
      'progress': t.progress,
      'priority': t.priority,
      'start_date': _dateOnly(t.startDate),
    };

Map<String, dynamic> dprEntryToSupabaseJson(DprEntry d) => {
      'id': d.id,
      'project_id': d.projectId,
      'created_by': d.createdBy,
      'entry_date': _dateOnly(d.entryDate),
      'work_summary': d.workSummary,
      'manpower_count': d.manpowerCount,
      'weather': d.weather,
      'status': d.status,
      'source': d.source,
    };

Map<String, dynamic> issueToSupabaseJson(Issue i) => {
      'id': i.id,
      'project_id': i.projectId,
      'dpr_entry_id': i.dprEntryId,
      'description': i.description,
      'severity': i.severity,
      'status': i.status,
      'resolved_at': _timestamp(i.resolvedAt),
    };

Map<String, dynamic> workerToSupabaseJson(Worker w) => {
      'id': w.id,
      'project_id': w.projectId,
      'name': w.name,
      'role': w.role,
      'phone': w.phone,
      'daily_wage': w.dailyWage,
      'status': w.status,
    };

Map<String, dynamic> equipmentToSupabaseJson(EquipmentData e) => {
      'id': e.id,
      'project_id': e.projectId,
      'name': e.name,
      'equipment_type': e.equipmentType,
      'model': e.model,
      'registration_number': e.registrationNumber,
      'status': e.status,
      'daily_rate': e.dailyRate,
      'notes': e.notes,
    };

Map<String, dynamic> inspectionToSupabaseJson(Inspection i) => {
      'id': i.id,
      'project_id': i.projectId,
      'title': i.title,
      'inspection_type': i.inspectionType,
      'status': i.status,
      'inspector_id': i.inspectorId,
      'scheduled_date': _dateOnly(i.scheduledDate),
      'completed_date': _dateOnly(i.completedDate),
      'overall_result': i.overallResult,
      'notes': i.notes,
    };

Map<String, dynamic> equipmentLogToSupabaseJson(EquipmentLog l) => {
      'id': l.id,
      'equipment_id': l.equipmentId,
      'log_date': _dateOnly(l.logDate),
      'log_type': l.logType,
      'hours_used': l.hoursUsed,
      'description': l.description,
      'cost': l.cost,
      'created_by': l.createdBy,
    };

Map<String, dynamic> inspectionItemToSupabaseJson(InspectionItem i) => {
      'id': i.id,
      'inspection_id': i.inspectionId,
      'item_description': i.itemDescription,
      'status': i.status,
      'notes': i.notes,
      'sort_order': i.sortOrder,
    };

Map<String, dynamic> subcontractorToSupabaseJson(Subcontractor s) => {
      'id': s.id,
      'company_id': s.companyId,
      'name': s.name,
      'contact_phone': s.contactPhone,
      'trade': s.trade,
    };

Map<String, dynamic> workOrderToSupabaseJson(WorkOrder w) => {
      'id': w.id,
      'project_id': w.projectId,
      'subcontractor_id': w.subcontractorId,
      'description': w.description,
      'agreed_amount': w.agreedAmount,
      'billed_amount': w.billedAmount,
      'status': w.status,
    };

Map<String, dynamic> approvalToSupabaseJson(Approval a) => {
      'id': a.id,
      'project_id': a.projectId,
      'entity_type': a.entityType,
      'entity_id': a.entityId,
      'requested_by': a.requestedBy,
      'status': a.status,
      'approver_id': a.approverId,
      'decision_note': a.decisionNote,
      'decided_at': _timestamp(a.decidedAt),
    };

Map<String, dynamic> supplierToSupabaseJson(Supplier s) => {
      'id': s.id,
      'company_id': s.companyId,
      'name': s.name,
      'contact_person': s.contactPerson,
      'phone': s.contactPhone,
      'email': s.email,
      'address': s.address,
      'gst_number': s.gstNumber,
      'category': s.category,
      'notes': s.notes,
    };

Map<String, dynamic> estimationToSupabaseJson(Estimation e) => {
      'id': e.id,
      'project_id': e.projectId,
      'name': e.name,
      'status': e.status,
      'contractor_profit_percent': e.contractorProfitPercent,
      'created_by': e.createdBy,
    };

Map<String, dynamic> costHeadToSupabaseJson(CostHead c) => {
      'id': c.id,
      'estimation_id': c.estimationId,
      'name': c.name,
      'calculation_type': c.calculationType,
      'raw_unit': c.rawUnit,
      'billing_unit': c.billingUnit,
      'conversion_factor': c.conversionFactor,
      'rate_per_unit': c.ratePerUnit,
      'sort_order': c.sortOrder,
    };

Map<String, dynamic> measurementEntryToSupabaseJson(MeasurementEntry m) => {
      'id': m.id,
      'cost_head_id': m.costHeadId,
      'description': m.description,
      'length': m.length,
      'width': m.width,
      'depth': m.depth,
      'nos': m.nos,
      'is_deduction': m.isDeduction,
    };

Map<String, dynamic> steelEntryToSupabaseJson(SteelEntry s) => {
      'id': s.id,
      'cost_head_id': s.costHeadId,
      'description': s.description,
      'bar_dia_mm': s.barDiaMm,
      'nos': s.nos,
      'length_ft': s.lengthFt,
    };

Map<String, dynamic> purchaseRequestToSupabaseJson(PurchaseRequest r) => {
      'id': r.id,
      'project_id': r.projectId,
      'item_name': r.materialName,
      'quantity': r.quantity,
      'unit': r.unit,
      'estimated_cost': r.estimatedAmount,
      'urgency': r.urgency,
      'status': r.status,
      'requested_by': r.raisedBy,
      'approved_by': r.approvedBy,
      'approved_at': _timestamp(r.approvedAt),
      'notes': r.notes,
    };

Map<String, dynamic> purchaseOrderToSupabaseJson(PurchaseOrder o) => {
      'id': o.id,
      'project_id': o.projectId,
      'vendor_id': o.supplierId,
      'quote_id': o.quoteId,
      'requisition_id': o.requestId,
      'po_number': o.poNumber,
      'total_amount': o.totalAmount,
      'delivery_date': _dateOnly(o.deliveryDate),
      'status': o.status,
      'notes': o.notes,
      'created_by': o.raisedBy,
    };

/// Documents sync the file itself through Supabase Storage (bucket
/// 'documents', object path = {projectId}/{documentId}); Postgres stores
/// only metadata with `file_path` holding that storage-relative path. The
/// row's local on-device path travels in the outbox payload under a
/// `_local_file_path` key, which SyncEngine strips before inserting --
/// it must never reach Postgres.
Map<String, dynamic> documentToSupabaseJson(Document d) => {
      'id': d.id,
      'project_id': d.projectId,
      'name': d.name,
      'category': d.category,
      'version': d.version,
      'file_path': '${d.projectId}/${d.id}',
      'file_size': d.fileSize,
      'mime_type': d.mimeType,
      'notes': d.notes,
      'uploaded_by': d.uploadedBy,
    };

/// [localPath] is where SyncEngine just downloaded the storage object on
/// this device; the local row points there instead of at another phone's
/// filesystem.
DocumentsCompanion documentFromSupabaseJson(Map<String, dynamic> row, {required String localPath}) =>
    DocumentsCompanion.insert(
      id: row['id'] as String,
      projectId: row['project_id'] as String,
      name: row['name'] as String,
      category: Value(row['category'] as String? ?? 'other'),
      version: Value(row['version'] as int? ?? 1),
      filePath: localPath,
      fileSize: Value(row['file_size'] as int?),
      mimeType: Value(row['mime_type'] as String?),
      notes: Value(row['notes'] as String?),
      uploadedBy: row['uploaded_by'] as String,
    );

// --- Reverse direction: a row pulled from Supabase (Realtime or a fetch),
// as a Postgres-shaped JSON map, into a Drift companion for upserting
// locally. Used by the pull side of the sync engine.

ProjectsCompanion projectFromSupabaseJson(Map<String, dynamic> row) => ProjectsCompanion.insert(
      id: row['id'] as String,
      companyId: row['company_id'] as String,
      name: row['name'] as String,
      clientName: Value(row['client_name'] as String?),
      locationLat: Value((row['location_lat'] as num?)?.toDouble()),
      locationLng: Value((row['location_lng'] as num?)?.toDouble()),
      geofenceRadiusM: Value(row['geofence_radius_m'] as int?),
      startDate: Value(row['start_date'] == null ? null : DateTime.parse(row['start_date'] as String)),
      endDate: Value(row['end_date'] == null ? null : DateTime.parse(row['end_date'] as String)),
      status: Value(row['status'] as String? ?? 'planning'),
    );

TasksCompanion taskFromSupabaseJson(Map<String, dynamic> row) => TasksCompanion.insert(
      id: row['id'] as String,
      projectId: row['project_id'] as String,
      title: row['title'] as String,
      assigneeId: Value(row['assignee_id'] as String?),
      dueDate: Value(row['due_date'] == null ? null : DateTime.parse(row['due_date'] as String)),
      status: Value(row['status'] as String? ?? 'todo'),
      progress: Value((row['progress'] as num?)?.toInt() ?? 0),
      priority: Value(row['priority'] as String? ?? 'normal'),
      startDate: Value(row['start_date'] == null ? null : DateTime.parse(row['start_date'] as String)),
    );

DprEntriesCompanion dprEntryFromSupabaseJson(Map<String, dynamic> row) => DprEntriesCompanion.insert(
      id: row['id'] as String,
      projectId: row['project_id'] as String,
      createdBy: row['created_by'] as String,
      entryDate: DateTime.parse(row['entry_date'] as String),
      workSummary: row['work_summary'] as String,
      manpowerCount: Value(row['manpower_count'] as int? ?? 0),
      weather: Value(row['weather'] as String?),
      status: Value(row['status'] as String? ?? 'confirmed'),
      source: Value(row['source'] as String? ?? 'manual'),
    );

IssuesCompanion issueFromSupabaseJson(Map<String, dynamic> row) => IssuesCompanion.insert(
      id: row['id'] as String,
      projectId: row['project_id'] as String,
      dprEntryId: Value(row['dpr_entry_id'] as String?),
      description: row['description'] as String,
      severity: Value(row['severity'] as String? ?? 'medium'),
      status: Value(row['status'] as String? ?? 'open'),
      resolvedAt: Value(row['resolved_at'] == null ? null : DateTime.parse(row['resolved_at'] as String)),
    );

WorkersCompanion workerFromSupabaseJson(Map<String, dynamic> row) => WorkersCompanion.insert(
      id: row['id'] as String,
      projectId: row['project_id'] as String,
      name: row['name'] as String,
      role: Value(row['role'] as String?),
      phone: Value(row['phone'] as String?),
      dailyWage: Value((row['daily_wage'] as num?)?.toDouble()),
      status: Value(row['status'] as String? ?? 'active'),
    );

EquipmentCompanion equipmentFromSupabaseJson(Map<String, dynamic> row) => EquipmentCompanion.insert(
      id: row['id'] as String,
      projectId: row['project_id'] as String,
      name: row['name'] as String,
      equipmentType: Value(row['equipment_type'] as String?),
      model: Value(row['model'] as String?),
      registrationNumber: Value(row['registration_number'] as String?),
      status: Value(row['status'] as String? ?? 'available'),
      dailyRate: Value((row['daily_rate'] as num?)?.toDouble()),
      notes: Value(row['notes'] as String?),
    );

InspectionsCompanion inspectionFromSupabaseJson(Map<String, dynamic> row) => InspectionsCompanion.insert(
      id: row['id'] as String,
      projectId: row['project_id'] as String,
      title: row['title'] as String,
      inspectionType: row['inspection_type'] as String,
      status: Value(row['status'] as String? ?? 'open'),
      inspectorId: Value(row['inspector_id'] as String?),
      scheduledDate: Value(row['scheduled_date'] == null ? null : DateTime.parse(row['scheduled_date'] as String)),
      completedDate: Value(row['completed_date'] == null ? null : DateTime.parse(row['completed_date'] as String)),
      overallResult: Value(row['overall_result'] as String?),
      notes: Value(row['notes'] as String?),
    );

EquipmentLogsCompanion equipmentLogFromSupabaseJson(Map<String, dynamic> row) => EquipmentLogsCompanion.insert(
      id: row['id'] as String,
      equipmentId: row['equipment_id'] as String,
      logDate: DateTime.parse(row['log_date'] as String),
      logType: row['log_type'] as String,
      hoursUsed: Value((row['hours_used'] as num?)?.toDouble()),
      description: Value(row['description'] as String?),
      cost: Value((row['cost'] as num?)?.toDouble()),
      createdBy: row['created_by'] as String,
      createdAt: row['created_at'] == null ? const Value.absent() : Value(DateTime.parse(row['created_at'] as String)),
    );

InspectionItemsCompanion inspectionItemFromSupabaseJson(Map<String, dynamic> row) => InspectionItemsCompanion.insert(
      id: row['id'] as String,
      inspectionId: row['inspection_id'] as String,
      itemDescription: row['item_description'] as String,
      status: Value(row['status'] as String? ?? 'pending'),
      notes: Value(row['notes'] as String?),
      sortOrder: Value((row['sort_order'] as num?)?.toInt() ?? 0),
    );

SubcontractorsCompanion subcontractorFromSupabaseJson(Map<String, dynamic> row) => SubcontractorsCompanion.insert(
      id: row['id'] as String,
      companyId: row['company_id'] as String,
      name: row['name'] as String,
      contactPhone: Value(row['contact_phone'] as String?),
      trade: Value(row['trade'] as String?),
    );

WorkOrdersCompanion workOrderFromSupabaseJson(Map<String, dynamic> row) => WorkOrdersCompanion.insert(
      id: row['id'] as String,
      projectId: row['project_id'] as String,
      subcontractorId: row['subcontractor_id'] as String,
      description: row['description'] as String,
      agreedAmount: Value((row['agreed_amount'] as num?)?.toDouble()),
      billedAmount: Value((row['billed_amount'] as num?)?.toDouble() ?? 0),
      status: Value(row['status'] as String? ?? 'active'),
    );

ApprovalsCompanion approvalFromSupabaseJson(Map<String, dynamic> row) => ApprovalsCompanion.insert(
      id: row['id'] as String,
      projectId: Value(row['project_id'] as String?),
      entityType: row['entity_type'] as String,
      entityId: row['entity_id'] as String,
      requestedBy: row['requested_by'] as String,
      status: Value(row['status'] as String? ?? 'pending'),
      approverId: Value(row['approver_id'] as String?),
      decisionNote: Value(row['decision_note'] as String?),
      decidedAt: Value(row['decided_at'] == null ? null : DateTime.parse(row['decided_at'] as String)),
    );

SuppliersCompanion supplierFromSupabaseJson(Map<String, dynamic> row) => SuppliersCompanion.insert(
      id: row['id'] as String,
      companyId: row['company_id'] as String,
      name: row['name'] as String,
      contactPerson: Value(row['contact_person'] as String?),
      contactPhone: Value(row['phone'] as String?),
      email: Value(row['email'] as String?),
      address: Value(row['address'] as String?),
      gstNumber: Value(row['gst_number'] as String?),
      category: Value(row['category'] as String?),
      notes: Value(row['notes'] as String?),
    );

EstimationsCompanion estimationFromSupabaseJson(Map<String, dynamic> row) => EstimationsCompanion.insert(
      id: row['id'] as String,
      projectId: row['project_id'] as String,
      name: row['name'] as String,
      status: Value(row['status'] as String? ?? 'draft'),
      contractorProfitPercent: Value((row['contractor_profit_percent'] as num?)?.toDouble()),
      createdBy: row['created_by'] as String,
    );

CostHeadsCompanion costHeadFromSupabaseJson(Map<String, dynamic> row) => CostHeadsCompanion.insert(
      id: row['id'] as String,
      estimationId: row['estimation_id'] as String,
      name: row['name'] as String,
      calculationType: row['calculation_type'] as String,
      rawUnit: row['raw_unit'] as String,
      billingUnit: row['billing_unit'] as String,
      conversionFactor: Value((row['conversion_factor'] as num?)?.toDouble() ?? 1),
      ratePerUnit: Value((row['rate_per_unit'] as num?)?.toDouble()),
      sortOrder: Value(row['sort_order'] as int? ?? 0),
    );

MeasurementEntriesCompanion measurementEntryFromSupabaseJson(Map<String, dynamic> row) =>
    MeasurementEntriesCompanion.insert(
      id: row['id'] as String,
      costHeadId: row['cost_head_id'] as String,
      description: row['description'] as String,
      length: Value((row['length'] as num?)?.toDouble()),
      width: Value((row['width'] as num?)?.toDouble()),
      depth: Value((row['depth'] as num?)?.toDouble()),
      nos: Value((row['nos'] as num?)?.toDouble() ?? 1),
      isDeduction: Value(row['is_deduction'] as bool? ?? false),
    );

SteelEntriesCompanion steelEntryFromSupabaseJson(Map<String, dynamic> row) => SteelEntriesCompanion.insert(
      id: row['id'] as String,
      costHeadId: row['cost_head_id'] as String,
      description: row['description'] as String,
      barDiaMm: (row['bar_dia_mm'] as num).toDouble(),
      nos: (row['nos'] as num).toDouble(),
      lengthFt: (row['length_ft'] as num).toDouble(),
    );

PurchaseRequestsCompanion purchaseRequestFromSupabaseJson(Map<String, dynamic> row) =>
    PurchaseRequestsCompanion.insert(
      id: row['id'] as String,
      projectId: row['project_id'] as String,
      raisedBy: row['requested_by'] as String,
      materialName: row['item_name'] as String,
      quantity: Value((row['quantity'] as num?)?.toDouble() ?? 1),
      unit: Value(row['unit'] as String? ?? ''),
      estimatedAmount: Value((row['estimated_cost'] as num?)?.toDouble()),
      urgency: Value(row['urgency'] as String? ?? 'normal'),
      status: Value(row['status'] as String? ?? 'pending'),
      approvedBy: Value(row['approved_by'] as String?),
      approvedAt: Value(row['approved_at'] == null ? null : DateTime.parse(row['approved_at'] as String)),
      notes: Value(row['notes'] as String?),
    );

PurchaseOrdersCompanion purchaseOrderFromSupabaseJson(Map<String, dynamic> row) =>
    PurchaseOrdersCompanion.insert(
      id: row['id'] as String,
      projectId: row['project_id'] as String,
      supplierId: row['vendor_id'] as String,
      requestId: Value(row['requisition_id'] as String?),
      quoteId: Value(row['quote_id'] as String?),
      raisedBy: row['created_by'] as String,
      poNumber: Value(row['po_number'] as String?),
      totalAmount: Value((row['total_amount'] as num?)?.toDouble()),
      deliveryDate: Value(row['delivery_date'] == null ? null : DateTime.parse(row['delivery_date'] as String)),
      status: Value(row['status'] as String? ?? 'issued'),
      notes: Value(row['notes'] as String?),
    );

Map<String, dynamic> projectMessageToSupabaseJson(ProjectMessage m) => {
      'id': m.id,
      'project_id': m.projectId,
      'sender_id': m.senderId,
      'sender_name': m.senderName,
      'body': m.body,
      'created_at': _timestamp(m.createdAt.toUtc()),
    };

ProjectMessagesCompanion projectMessageFromSupabaseJson(Map<String, dynamic> row) => ProjectMessagesCompanion(
      id: Value(row['id'] as String),
      projectId: Value(row['project_id'] as String),
      senderId: Value(row['sender_id'] as String),
      senderName: Value(row['sender_name'] as String),
      body: Value(row['body'] as String),
      createdAt: Value(DateTime.parse(row['created_at'] as String)),
    );

// ---------------------------------------------------------------------------
// Site money, labour and stock (supabase/migrations/20261105050000_site_records.sql).
// These have their own phone-shaped cloud tables (site_*), so the owner sees
// the site's punches, expenses and material from anywhere without forcing
// them into the desktop app's differently-shaped attendance / grns tables
// (see the notes at the top of this file).
// ---------------------------------------------------------------------------

DateTime _parseTs(Object? v) => DateTime.parse(v as String);
DateTime? _parseTsOrNull(Object? v) => v == null ? null : DateTime.parse(v as String);
double _num(Object? v) => (v as num).toDouble();

Map<String, dynamic> attendanceToSupabaseJson(LabourAttendanceData a) => {
      'id': a.id,
      'project_id': a.projectId,
      'worker_name': a.workerName,
      'worker_id': a.workerId,
      'recorded_by': a.recordedBy,
      'punch_in': _timestamp(a.punchIn.toUtc()),
      'punch_out': _timestamp(a.punchOut?.toUtc()),
      'lat': a.lat,
      'lng': a.lng,
      'within_geofence': a.withinGeofence,
    };

LabourAttendanceCompanion attendanceFromSupabaseJson(Map<String, dynamic> row) => LabourAttendanceCompanion(
      id: Value(row['id'] as String),
      projectId: Value(row['project_id'] as String),
      workerName: Value(row['worker_name'] as String),
      workerId: Value(row['worker_id'] as String?),
      recordedBy: Value(row['recorded_by'] as String),
      punchIn: Value(_parseTs(row['punch_in'])),
      punchOut: Value(_parseTsOrNull(row['punch_out'])),
      lat: Value((row['lat'] as num?)?.toDouble()),
      lng: Value((row['lng'] as num?)?.toDouble()),
      withinGeofence: Value(row['within_geofence'] as bool?),
    );

Map<String, dynamic> siteExpenseToSupabaseJson(SiteExpense e) => {
      'id': e.id,
      'project_id': e.projectId,
      'cost_head_id': e.costHeadId,
      'category': e.category,
      'amount': e.amount,
      'incurred_on': e.incurredOn,
      'recorded_by': e.recordedBy,
      'note': e.note,
      'worker_id': e.workerId,
      // v10 money-book columns go only when set. Entries made on v10 always
      // carry a voucher number, so 20261109000000_money_book.sql must be in
      // the cloud before a v10 build ships; older rows sync either way.
      if (_usesMoneyBook(e)) ...{
        'paid_to': e.paidTo,
        'mode': e.mode,
        'gst_pct': e.gstPct,
        'gst_inter_state': e.gstInterState,
        'voucher_no': e.voucherNo,
        'voided': e.voided,
        'void_reason': e.voidReason,
        'edited_at': e.editedAt == null ? null : _timestamp(e.editedAt!.toUtc()),
        'edited_by': e.editedBy,
      },
    };

bool _usesMoneyBook(SiteExpense e) =>
    e.paidTo != null ||
    e.mode != null ||
    e.gstPct != null ||
    e.gstInterState ||
    e.voided ||
    e.editedAt != null ||
    (e.voucherNo != null && e.voucherNo! > 0);

/// A column the cloud didn't send (an older cloud schema) leaves the local
/// value alone instead of wiping it.
Value<T> _ifSent<T>(Map<String, dynamic> row, String key, T Function(Object? v) read) =>
    row.containsKey(key) ? Value(read(row[key])) : const Value.absent();

SiteExpensesCompanion siteExpenseFromSupabaseJson(Map<String, dynamic> row) => SiteExpensesCompanion(
      id: Value(row['id'] as String),
      projectId: Value(row['project_id'] as String),
      costHeadId: Value(row['cost_head_id'] as String?),
      category: Value(row['category'] as String),
      amount: Value(_num(row['amount'])),
      incurredOn: Value(row['incurred_on'] as String),
      recordedBy: Value(row['recorded_by'] as String),
      note: Value(row['note'] as String?),
      workerId: Value(row['worker_id'] as String?),
      paidTo: _ifSent(row, 'paid_to', (v) => v as String?),
      mode: _ifSent(row, 'mode', (v) => v as String?),
      gstPct: _ifSent(row, 'gst_pct', (v) => v == null ? null : _num(v)),
      gstInterState: _ifSent(row, 'gst_inter_state', (v) => v as bool? ?? false),
      // A voucher number is never taken away: a row the cloud hasn't
      // numbered yet keeps the one this phone gave it.
      voucherNo: row['voucher_no'] == null ? const Value.absent() : Value((row['voucher_no'] as num).toInt()),
      voided: _ifSent(row, 'voided', (v) => v as bool? ?? false),
      voidReason: _ifSent(row, 'void_reason', (v) => v as String?),
      editedAt: _ifSent(row, 'edited_at', (v) => v == null ? null : _parseTs(v)),
      editedBy: _ifSent(row, 'edited_by', (v) => v as String?),
    );

Map<String, dynamic> materialReceiptToSupabaseJson(MaterialReceipt r) => {
      'id': r.id,
      'project_id': r.projectId,
      'po_id': r.poId,
      'supplier_id': r.supplierId,
      'cost_head_id': r.costHeadId,
      'material_name': r.materialName,
      'quantity': r.quantity,
      'unit': r.unit,
      'amount': r.amount,
      'received_by': r.receivedBy,
      'received_on': _timestamp(r.receivedOn.toUtc()),
      'notes': r.notes,
    };

MaterialReceiptsCompanion materialReceiptFromSupabaseJson(Map<String, dynamic> row) => MaterialReceiptsCompanion(
      id: Value(row['id'] as String),
      projectId: Value(row['project_id'] as String),
      poId: Value(row['po_id'] as String?),
      supplierId: Value(row['supplier_id'] as String?),
      costHeadId: Value(row['cost_head_id'] as String?),
      materialName: Value(row['material_name'] as String),
      quantity: Value(_num(row['quantity'])),
      unit: Value(row['unit'] as String?),
      amount: Value(_num(row['amount'])),
      receivedBy: Value(row['received_by'] as String),
      receivedOn: Value(_parseTs(row['received_on'])),
      notes: Value(row['notes'] as String?),
    );

Map<String, dynamic> materialUsageToSupabaseJson(MaterialUsageData u) => {
      'id': u.id,
      'project_id': u.projectId,
      'material_name': u.materialName,
      'quantity': u.quantity,
      'unit': u.unit,
      'recorded_by': u.recordedBy,
      'used_on': _timestamp(u.usedOn.toUtc()),
      'note': u.note,
    };

MaterialUsageCompanion materialUsageFromSupabaseJson(Map<String, dynamic> row) => MaterialUsageCompanion(
      id: Value(row['id'] as String),
      projectId: Value(row['project_id'] as String),
      materialName: Value(row['material_name'] as String),
      quantity: Value(_num(row['quantity'])),
      unit: Value(row['unit'] as String?),
      recordedBy: Value(row['recorded_by'] as String),
      usedOn: Value(_parseTs(row['used_on'])),
      note: Value(row['note'] as String?),
    );

Map<String, dynamic> paymentReceivedToSupabaseJson(PaymentsReceivedData p) => {
      'id': p.id,
      'project_id': p.projectId,
      'amount': p.amount,
      'received_on': _timestamp(p.receivedOn.toUtc()),
      'from_party': p.fromParty,
      'mode': p.mode,
      'recorded_by': p.recordedBy,
      'note': p.note,
      if (p.voided || p.editedAt != null) ...{
        'voided': p.voided,
        'void_reason': p.voidReason,
        'edited_at': p.editedAt == null ? null : _timestamp(p.editedAt!.toUtc()),
        'edited_by': p.editedBy,
      },
    };

PaymentsReceivedCompanion paymentReceivedFromSupabaseJson(Map<String, dynamic> row) => PaymentsReceivedCompanion(
      id: Value(row['id'] as String),
      projectId: Value(row['project_id'] as String),
      amount: Value(_num(row['amount'])),
      receivedOn: Value(_parseTs(row['received_on'])),
      fromParty: Value(row['from_party'] as String),
      mode: Value(row['mode'] as String),
      recordedBy: Value(row['recorded_by'] as String),
      note: Value(row['note'] as String?),
      voided: _ifSent(row, 'voided', (v) => v as bool? ?? false),
      voidReason: _ifSent(row, 'void_reason', (v) => v as String?),
      editedAt: _ifSent(row, 'edited_at', (v) => v == null ? null : _parseTs(v)),
      editedBy: _ifSent(row, 'edited_by', (v) => v as String?),
    );

// ---------------------------------------------------------------------------
// Client bills (site_client_bills)
// ---------------------------------------------------------------------------

Map<String, dynamic> clientBillToSupabaseJson(ClientBill b) => {
      'id': b.id,
      'project_id': b.projectId,
      'kind': b.kind,
      'bill_number': b.billNumber,
      'bill_date': _dateOnly(b.billDate),
      'client_name': b.clientName,
      'client_gstin': b.clientGstin,
      'sac': b.sac,
      'lines': b.linesJson,
      'gst_rate': b.gstRate,
      'inter_state': b.interState,
      'retention_pct': b.retentionPct,
      'tds_pct': b.tdsPct,
      'gross': b.gross,
      'net_payable': b.netPayable,
      'status': b.status,
      'notes': b.notes,
      'recorded_by': b.recordedBy,
    };

ClientBillsCompanion clientBillFromSupabaseJson(Map<String, dynamic> row) => ClientBillsCompanion.insert(
      id: row['id'] as String,
      projectId: row['project_id'] as String,
      kind: row['kind'] as String,
      billNumber: row['bill_number'] as String,
      billDate: DateTime.parse(row['bill_date'] as String),
      clientName: row['client_name'] as String,
      clientGstin: Value(row['client_gstin'] as String?),
      sac: Value(row['sac'] as String? ?? '995411'),
      linesJson: row['lines'] is String ? row['lines'] as String : jsonEncode(row['lines'] ?? const []),
      gstRate: Value((row['gst_rate'] as num? ?? 18).toDouble()),
      interState: Value(row['inter_state'] as bool? ?? false),
      retentionPct: Value((row['retention_pct'] as num? ?? 0).toDouble()),
      tdsPct: Value((row['tds_pct'] as num? ?? 0).toDouble()),
      gross: (row['gross'] as num).toDouble(),
      netPayable: (row['net_payable'] as num).toDouble(),
      status: Value(row['status'] as String? ?? 'issued'),
      notes: Value(row['notes'] as String?),
      recordedBy: row['recorded_by'] as String,
    );
