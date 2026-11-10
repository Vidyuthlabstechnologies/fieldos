/// Loading one site's commercial records, and the providers the screens use.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/commercial/commercial_rules.dart';
import 'package:fieldos_mobile/features/daily/day_close_exceptions.dart';
import 'package:fieldos_mobile/providers.dart';

Future<CommercialData> loadCommercialData(AppDatabase db, String projectId) async {
  final c = db.commercialDao;
  final project = await db.projectDao.byId(projectId);
  final subs = project == null ? const <Subcontractor>[] : await db.subcontractorDao.forCompany(project.companyId);
  final receipts = await (db.select(db.materialReceipts)..where((r) => r.projectId.equals(projectId))).get();
  final expenses = await (db.select(db.siteExpenses)..where((e) => e.projectId.equals(projectId))).get();
  return CommercialData(
    projectId: projectId,
    costCodes: await c.costCodesFor(projectId),
    workOrders: await c.workOrdersFor(projectId),
    claims: await c.claimsForProject(projectId),
    certifications: await c.certificationsForProject(projectId),
    variations: await c.variationsFor(projectId),
    decisions: await c.decisionsFor(projectId),
    attachments: await c.attachmentsFor(projectId),
    actions: await c.exceptionActionsFor(projectId),
    purchaseOrders: await db.purchaseDao.ordersFor(projectId),
    receipts: receipts,
    expenses: expenses,
    subcontractorNames: {for (final s in subs) s.id: s.name},
  );
}

final commercialDataProvider = FutureProvider.autoDispose.family<CommercialData, String>(
    (ref, projectId) => loadCommercialData(ref.watch(appDatabaseProvider), projectId));

/// One site's open and decided exceptions, with the site.
class SiteExceptions {
  SiteExceptions(this.project, this.data, this.items);
  final Project project;
  final CommercialData data;
  final List<CommercialException> items;
}

/// The project director's queue: every site of the company.
final companyExceptionsProvider =
    FutureProvider.autoDispose.family<List<SiteExceptions>, String>((ref, companyId) async {
  final db = ref.watch(appDatabaseProvider);
  final out = <SiteExceptions>[];
  for (final p in await db.projectDao.forCompany(companyId)) {
    final d = await loadCommercialData(db, p.id);
    out.add(SiteExceptions(p, d, commercialExceptions(d, now: DateTime.now())));
  }
  return out;
});

/// Open exceptions across the company, for the badge on Home.
final openExceptionCountProvider = FutureProvider.autoDispose.family<int, String>((ref, companyId) async {
  // With the daily close's missing reports (day_close_exceptions.dart).
  final sites = await ref.watch(inboxExceptionsProvider(companyId).future);
  return sites.fold<int>(0, (n, s) => n + s.items.where((e) => !e.isResolved).length);
});
