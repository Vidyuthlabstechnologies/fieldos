/// Drift row -> Supabase (Postgres, snake_case) JSON mappers.
///
/// Deliberately explicit, one function per table, rather than reflection --
/// this is the one place a Dart camelCase/Postgres snake_case mismatch
/// would silently corrupt synced data, so every field is named out loud and
/// checked against supabase/migrations/20260823000000_initial_schema.sql by
/// hand, not inferred.
///
/// Only Project and Task are covered so far -- this is the initial,
/// verified slice of the sync engine (see docs/SUPABASE_SYNC_RESEARCH.md).
/// Extending to the other ~28 tables is a follow-up: same pattern, once
/// this slice is proven correct end to end.
library;

import 'package:drift/drift.dart' show Value;
import 'package:fieldos_mobile/data/app_database.dart';

String? _dateOnly(DateTime? d) => d?.toIso8601String().split('T').first;

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
