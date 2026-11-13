/// Sync for the site execution tables (FOS-205 to FOS-209). Every column
/// on the phone has the same column on the server, in snake_case
/// (supabase/migrations/20261112100000_site_execution.sql), so one mapper
/// covers them all instead of a pair per table.
library;

import 'package:drift/drift.dart';

import 'package:fieldos_mobile/data/app_database.dart';

/// Server table -> phone table.
const siteExecutionTables = {
  'site_task_constraints': 'task_constraints',
  'site_drawings': 'drawings',
  'site_drawing_revisions': 'drawing_revisions',
  'site_rfis': 'rfis',
  'site_hold_points': 'hold_points',
  'site_defects': 'defects',
  'site_execution_photos': 'execution_photos',
  'site_handover_units': 'handover_units',
  'site_handover_checks': 'handover_checks',
  'company_standards': 'company_standards',
};

/// Tables whose rows are a file on the phone, uploaded to Storage under
/// {projectId}/{folder}/{id}.ext.
const siteExecutionFileFolders = {
  'site_drawing_revisions': 'drawings',
  'site_execution_photos': 'execution',
};

/// Server tables scoped to a site (the rest is company-wide).
const siteExecutionProjectScoped = {
  'site_task_constraints', 'site_drawings', 'site_drawing_revisions', 'site_rfis', 'site_hold_points',
  'site_defects', 'site_execution_photos', 'site_handover_units', 'site_handover_checks',
};

/// Person columns on these tables, swapped between the phone's and the
/// cloud's id for the signed-in user.
/// (owner_id, raised_by, created_by, decided_by, uploaded_by and
/// assignee_id are already in SyncEngine.userIdColumns.)
const siteExecutionUserColumns = {
  'cleared_by', 'answered_by', 'fixed_by', 'closed_by', 'handed_over_by', 'done_by',
};

/// Timestamps go to the server in UTC and come back as local time.
class _Iso extends ValueSerializer {
  const _Iso();

  @override
  dynamic toJson<T>(T value) => value is DateTime ? value.toUtc().toIso8601String() : value;

  @override
  T fromJson<T>(dynamic json) {
    if (json == null) return null as T;
    final probe = <T>[];
    if (probe is List<DateTime?>) return DateTime.parse(json.toString()).toLocal() as T;
    if (probe is List<double?> && json is num) return json.toDouble() as T;
    if (probe is List<int?> && json is num) return json.toInt() as T;
    return json as T;
  }
}

const _iso = _Iso();

String _snake(String camel) => camel.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
String _camel(String snake) => snake.replaceAllMapped(RegExp('_([a-z])'), (m) => m[1]!.toUpperCase());

String _ext(String localPath) {
  final dot = localPath.lastIndexOf('.');
  final slash = localPath.lastIndexOf('/');
  if (dot <= slash || localPath.length - dot > 6) return '';
  return localPath.substring(dot).toLowerCase();
}

/// Where a row's file lives in Storage.
String executionStoragePath(String serverTable, String projectId, String id, String localPath) =>
    '$projectId/${siteExecutionFileFolders[serverTable]}/$id${_ext(localPath)}';

/// The outbox payload for [row] of [serverTable].
Map<String, dynamic> executionToRemote(String serverTable, DataClass row) {
  final json = row.toJson(serializer: _iso);
  final out = <String, dynamic>{for (final e in json.entries) _snake(e.key): e.value};
  if (siteExecutionFileFolders.containsKey(serverTable)) {
    final local = out['file_path'] as String;
    out['file_path'] = executionStoragePath(serverTable, out['project_id'] as String, out['id'] as String, local);
    out['_local_file_path'] = local;
  }
  return out;
}

/// A server row as the phone's row; [localPath] for rows with a file.
Insertable<DataClass> executionFromRemote(String serverTable, Map<String, dynamic> row, {String? localPath}) {
  final camel = <String, dynamic>{
    for (final e in row.entries)
      if (e.key != 'synced_at' && !e.key.startsWith('_')) _camel(e.key): e.value,
  };
  if (localPath != null) camel['filePath'] = localPath;
  final DataClass d = switch (serverTable) {
    'site_task_constraints' => TaskConstraint.fromJson(camel, serializer: _iso),
    'site_drawings' => Drawing.fromJson(camel, serializer: _iso),
    'site_drawing_revisions' => DrawingRevision.fromJson(camel, serializer: _iso),
    'site_rfis' => Rfi.fromJson(camel, serializer: _iso),
    'site_hold_points' => HoldPoint.fromJson(camel, serializer: _iso),
    'site_defects' => Defect.fromJson(camel, serializer: _iso),
    'site_execution_photos' => ExecutionPhoto.fromJson(camel, serializer: _iso),
    'site_handover_units' => HandoverUnit.fromJson(camel, serializer: _iso),
    'site_handover_checks' => HandoverCheck.fromJson(camel, serializer: _iso),
    'company_standards' => CompanyStandard.fromJson(camel, serializer: _iso),
    _ => throw ArgumentError('Not a site execution table: $serverTable'),
  };
  return d as Insertable<DataClass>;
}

/// The phone's table for [serverTable].
TableInfo<Table, DataClass> executionTable(AppDatabase db, String serverTable) => switch (serverTable) {
      'site_task_constraints' => db.taskConstraints,
      'site_drawings' => db.drawings,
      'site_drawing_revisions' => db.drawingRevisions,
      'site_rfis' => db.rfis,
      'site_hold_points' => db.holdPoints,
      'site_defects' => db.defects,
      'site_execution_photos' => db.executionPhotos,
      'site_handover_units' => db.handoverUnits,
      'site_handover_checks' => db.handoverChecks,
      'company_standards' => db.companyStandards,
      _ => throw ArgumentError('Not a site execution table: $serverTable'),
    } as TableInfo<Table, DataClass>;
