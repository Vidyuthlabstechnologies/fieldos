/// A filled-in sample site for a new company, so the first minutes show
/// what FieldOS does (late tasks, today's labour, a daily report, money in
/// and out, stock) before anyone types their own. It stays on this phone:
/// its records are local-only (see [SyncOutboxDao.markLocalOnly]), so a
/// team never sees it, and one tap removes it.
library;

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

const sampleProjectName = 'Sample site (demo)';

String sampleProjectKey(String companyId) => 'sample_project:$companyId';

/// The company's sample project id, if it has one.
Future<String?> sampleProjectId(AppDatabase db, String companyId) async {
  final id = await db.settingsDao.get(sampleProjectKey(companyId));
  return (id == null || id.isEmpty) ? null : id;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Creates the sample project, or returns the one already there.
Future<Project> createSampleProject(
  AppDatabase db, {
  required String companyId,
  required String userId,
  DateTime? now,
}) async {
  final existing = await sampleProjectId(db, companyId);
  if (existing != null) {
    final p = await db.projectDao.byId(existing);
    if (p != null) return p;
  }
  final today = _day(now ?? DateTime.now());
  DateTime d(int days) => today.add(Duration(days: days));
  const uuid = Uuid();
  final projectId = uuid.v4();

  return db.transaction(() async {
    await db.syncOutboxDao.markLocalOnly(projectId);
    await db.settingsDao.set(sampleProjectKey(companyId), projectId);
    final project = await db.projectDao.create(
      ProjectsCompanion.insert(
        id: projectId,
        companyId: companyId,
        name: sampleProjectName,
        clientName: const Value('Mr. Reddy (G+1 house)'),
        status: const Value('active'),
        startDate: Value(d(-30)),
        endDate: Value(d(120)),
      ),
    );

    for (final (title, status, progress, priority, start, due) in [
      ('Excavation and PCC', 'done', 100, 'normal', -30, -24),
      ('Footings', 'done', 100, 'normal', -23, -14),
      ('Plinth beam', 'in_progress', 80, 'high', -12, -3),
      ('Ground floor columns', 'in_progress', 30, 'high', -5, 6),
      ('First slab shuttering', 'todo', 0, 'normal', 5, 15),
      ('Ground floor brick work', 'todo', 0, 'low', 14, 40),
    ]) {
      await db.taskDao.create(
        TasksCompanion.insert(
          id: uuid.v4(),
          projectId: projectId,
          title: title,
          status: Value(status),
          progress: Value(progress),
          priority: Value(priority),
          startDate: Value(d(start)),
          dueDate: Value(d(due)),
        ),
      );
    }

    final workers = <Worker>[];
    for (final (name, role, wage) in [
      ('Ramesh', 'Mason', 900.0),
      ('Venkat', 'Bar bender', 850.0),
      ('Anil', 'Carpenter', 850.0),
      ('Suresh', 'Helper', 600.0),
      ('Lakshmi', 'Helper', 600.0),
    ]) {
      workers.add(
        await db.workerDao.create(
          WorkersCompanion.insert(
            id: uuid.v4(),
            projectId: projectId,
            name: name,
            role: Value(role),
            dailyWage: Value(wage),
          ),
        ),
      );
    }
    // Yesterday: everyone, a full day. Today: four in since 9.
    for (final w in workers) {
      await db.attendanceDao.punchIn(
        LabourAttendanceCompanion.insert(
          id: uuid.v4(),
          projectId: projectId,
          workerName: w.name,
          workerId: Value(w.id),
          recordedBy: userId,
          punchIn: d(-1).add(const Duration(hours: 9)),
          punchOut: Value(d(-1).add(const Duration(hours: 17, minutes: 30))),
        ),
      );
    }
    for (final w in workers.take(4)) {
      await db.attendanceDao.punchIn(
        LabourAttendanceCompanion.insert(
          id: uuid.v4(),
          projectId: projectId,
          workerName: w.name,
          workerId: Value(w.id),
          recordedBy: userId,
          punchIn: today.add(const Duration(hours: 9)),
        ),
      );
    }

    final dpr = await db.dprDao.create(
      DprEntriesCompanion.insert(
        id: uuid.v4(),
        projectId: projectId,
        createdBy: userId,
        entryDate: d(-1),
        workSummary:
            'Plinth beam shuttering finished on the east side, reinforcement tied for 6 of 8 beams. '
            'Column starters checked. Cement ran short in the evening, 20 bags needed tomorrow.',
        manpowerCount: const Value(5),
        weather: const Value('Sunny'),
      ),
    );
    await db.issueDao.create(
      IssuesCompanion.insert(
        id: uuid.v4(),
        projectId: projectId,
        dprEntryId: Value(dpr.id),
        description: 'Cement short for column casting: 20 bags needed',
        severity: const Value('high'),
      ),
    );

    await db.materialDao.createReceipt(
      MaterialReceiptsCompanion.insert(
        id: uuid.v4(),
        projectId: projectId,
        materialName: 'Cement (OPC 53)',
        quantity: 50,
        unit: const Value('bags'),
        amount: 19500,
        receivedBy: userId,
        receivedOn: d(-6),
      ),
    );
    await db.materialDao.createReceipt(
      MaterialReceiptsCompanion.insert(
        id: uuid.v4(),
        projectId: projectId,
        materialName: 'TMT steel 12mm',
        quantity: 1.2,
        unit: const Value('t'),
        amount: 78000,
        receivedBy: userId,
        receivedOn: d(-10),
      ),
    );

    await db.paymentDao.create(
      PaymentsReceivedCompanion.insert(
        id: uuid.v4(),
        projectId: projectId,
        amount: 300000,
        receivedOn: d(-28),
        fromParty: 'Mr. Reddy',
        mode: 'bank',
        recordedBy: userId,
        note: const Value('Advance'),
      ),
    );
    for (final (category, amount, day, note) in [
      ('Transport', 1800.0, -6, 'Cement from the dealer'),
      ('Food & tea', 250.0, -1, null),
      ('Labour', 4400.0, -1, 'Yesterday\'s wages'),
    ]) {
      await db.expenseDao.create(
        SiteExpensesCompanion.insert(
          id: uuid.v4(),
          projectId: projectId,
          category: category,
          amount: amount,
          incurredOn: _iso(d(day)),
          recordedBy: userId,
          note: Value(note),
        ),
      );
    }
    return project;
  });
}

/// Deletes the sample project and everything under it from this phone.
Future<void> removeSampleProject(AppDatabase db, String companyId) async {
  final projectId = await sampleProjectId(db, companyId);
  if (projectId == null) return;
  await db.transaction(() async {
    final ids = {...await db.syncOutboxDao.localOnlyIds()};
    // Every table: rows that are local-only, or point at the project.
    for (final table in db.allTables) {
      final cols = table.$columns.map((c) => c.name).toSet();
      final name = table.actualTableName;
      if (name == 'sync_outbox' || name == 'app_settings') continue;
      if (cols.contains('project_id')) {
        await db.customStatement('DELETE FROM "$name" WHERE project_id = ?', [projectId]);
      }
      if (cols.contains('id') && ids.isNotEmpty) {
        await db.customStatement(
          'DELETE FROM "$name" WHERE id IN (${List.filled(ids.length, '?').join(', ')})',
          ids.toList(),
        );
      }
    }
    await db.syncOutboxDao.forgetLocalOnly(ids);
    await db.settingsDao.set(sampleProjectKey(companyId), '');
  });
  db.markTablesUpdated(db.allTables);
}

final sampleProjectIdProvider = FutureProvider.autoDispose.family<String?, String>(
  (ref, companyId) => sampleProjectId(ref.watch(appDatabaseProvider), companyId),
);

/// Shown on top of the sample project: what it is, and a way to remove it.
class SampleProjectBanner extends ConsumerWidget {
  const SampleProjectBanner({super.key, required this.project});
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(sampleProjectIdProvider(project.companyId)).value;
    if (id != project.id) return const SizedBox.shrink();
    final theme = Theme.of(context);
    // A thin, quiet strip: it explains the demo without taking over the
    // top of every tab.
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
        child: Row(
          children: [
            Icon(Icons.science_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr('A sample site to try things on. It stays on this phone and your team never sees it.'),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            TextButton(onPressed: () => _remove(context, ref), child: Text(tr('Remove'))),
          ],
        ),
      ),
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Remove the sample site?')),
        content: Text(
          tr('Its tasks, labour, reports and money are deleted from this phone. Your own projects are not touched.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Remove'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await removeSampleProject(ref.read(appDatabaseProvider), project.companyId);
    ref.invalidate(sampleProjectIdProvider(project.companyId));
    ref.invalidate(projectsProvider(project.companyId));
    if (!context.mounted) return;
    Navigator.of(context).pop();
    showSnack(context, 'Sample site removed');
  }
}
