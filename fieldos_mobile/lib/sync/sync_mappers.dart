/// Drift row -> Supabase (Postgres, snake_case) JSON mappers.
///
/// Deliberately explicit, one function per table, rather than reflection --
/// this is the one place a Dart camelCase/Postgres snake_case mismatch
/// would silently corrupt synced data, so every field is named out loud and
/// checked against supabase/migrations/20260823000000_initial_schema.sql by
/// hand, not inferred.
///
/// Project, Task, DprEntry, Issue, Worker, Equipment, and Inspection are
/// covered -- chosen because their Drift columns correspond 1:1 with the
/// Postgres schema. Not every mobile table does: e.g. MaterialReceipts
/// (procurement-chain shaped -- po_id/supplier_id/cost_head_id) has no
/// honest mapping to material_entries (the desktop's simple consumption-log
/// shape) -- forcing one would silently corrupt data, so it's deliberately
/// NOT wired rather than wired wrong. EquipmentLogs and InspectionItems
/// (child/detail rows of Equipment/Inspection) are also not yet wired --
/// same reasoning as MaterialReceipts's omission, just not yet verified,
/// not ruled out. Extending to the rest of the ~30 tables is a follow-up,
/// same pattern, per-table -- verify the shapes actually correspond before
/// wiring, the way this file's docstring itself demonstrates by omission.
library;

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
