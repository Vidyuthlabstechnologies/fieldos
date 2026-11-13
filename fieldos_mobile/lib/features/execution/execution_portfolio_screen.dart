/// FOS-209: every site counted the same way (lookahead, RFIs, drawings,
/// hold points, defects, handover), shared as CSV, and the company's
/// standard hold points and handover checklist that every site starts from.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/commercial/commercial_widgets.dart' show askText, KeyValue;
import 'package:fieldos_mobile/features/execution/execution_data.dart';
import 'package:fieldos_mobile/features/execution/execution_rules.dart';
import 'package:fieldos_mobile/features/execution/execution_screens.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

class ExecutionPortfolioScreen extends ConsumerWidget {
  const ExecutionPortfolioScreen({super.key, required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(portfolioExecutionProvider(companyId));
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Site execution across sites')),
        actions: [
          IconButton(
            tooltip: tr('Company standards'),
            icon: const Icon(Icons.rule_outlined),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => CompanyStandardsScreen(companyId: companyId))),
          ),
          IconButton(
            tooltip: tr('Share as CSV'),
            icon: const Icon(Icons.ios_share),
            onPressed: data.value == null ? null : () => _share(context, data.value!, now),
          ),
        ],
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
        data: (rows) {
          if (rows.isEmpty) {
            return EmptyState(icon: Icons.apartment_outlined, title: tr('No sites yet'));
          }
          final sorted = [for (final (p, d) in rows) (p, d.summary(now))]
            ..sort((a, b) => (b.$2.needsAttention ? 1 : 0).compareTo(a.$2.needsAttention ? 1 : 0));
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(portfolioExecutionProvider(companyId)),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
              children: [for (final (p, s) in sorted) _SiteCard(project: p, s: s)],
            ),
          );
        },
      ),
    );
  }

  Future<void> _share(BuildContext context, List<(Project, ExecutionData)> rows, DateTime now) async {
    final csv = portfolioCsv([for (final (p, d) in rows) (p.name, d.summary(now))]);
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/site-execution-${ymd(now)}.csv')..writeAsStringSync(csv);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: tr('Site execution across sites')));
  }
}

class _SiteCard extends StatelessWidget {
  const _SiteCard({required this.project, required this.s});
  final Project project;
  final SiteExecutionSummary s;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    void open(int tab) => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SiteExecutionScreen(project: project, initialTab: tab),
      ),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => open(0),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(project.name, style: theme.textTheme.titleMedium)),
                  s.needsAttention
                      ? StatusPill(tr('Needs attention'), tone: PillTone.warn)
                      : StatusPill(tr('On track'), tone: PillTone.ok),
                ],
              ),
              const SizedBox(height: 6),
              KeyValue(tr('Tasks in the next two weeks'), trf('{n}, {b} blocked', {'n': s.lookaheadTasks, 'b': s.blockedTasks})),
              if (s.lateConstraints > 0)
                KeyValue(tr('Constraints past need-by'), '${s.lateConstraints}', color: toneColor(context, PillTone.danger)),
              KeyValue(
                tr('Open RFIs'),
                s.overdueRfis > 0 ? trf('{n}, {o} overdue', {'n': s.openRfis, 'o': s.overdueRfis}) : '${s.openRfis}',
              ),
              KeyValue(tr('Drawings to approve'), '${s.pendingRevisions}'),
              KeyValue(tr('Hold points not released'), '${s.pendingHoldPoints}'),
              KeyValue(
                tr('Open defects'),
                s.ageingDefects > 0
                    ? trf('{n}, {a} open a week or more', {'n': s.openDefects, 'a': s.ageingDefects})
                    : '${s.openDefects}',
              ),
              if (s.units > 0)
                KeyValue(
                  tr('Handover'),
                  trf('{h} of {n} handed over, {r} ready', {'h': s.unitsHandedOver, 'n': s.units, 'r': s.unitsReady}),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class CompanyStandardsScreen extends ConsumerWidget {
  const CompanyStandardsScreen({super.key, required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit = Roles.canApprove(ref.watch(sessionProvider).role);
    final data = ref.watch(companyStandardsProvider(companyId));
    return Scaffold(
      appBar: AppBar(title: Text(tr('Company standards'))),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
              child: Text(
                tr(
                  'Every site starts from these. A new unit gets the handover checklist, '
                  'and the standard hold points can be added at any place on a site.',
                ),
              ),
            ),
            for (final (kind, title) in [
              ('hold_point', tr('Standard hold points')),
              ('handover_check', tr('Handover checklist')),
            ]) ...[
              SectionHeader(title),
              for (final s in list.where((s) => s.kind == kind))
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(s.item),
                  trailing: canEdit
                      ? IconButton(
                          tooltip: tr('Remove'),
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () =>
                              _run(context, ref, () => ref.read(appDatabaseProvider).siteExecutionDao.removeStandard(s.id)),
                        )
                      : null,
                ),
              if (canEdit)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(tr('Add a line')),
                    onPressed: () async {
                      final item = await askText(context, title: title);
                      if (item == null || item.isEmpty || !context.mounted) return;
                      await _run(
                        context,
                        ref,
                        () => ref
                            .read(appDatabaseProvider)
                            .siteExecutionDao
                            .addStandard(companyId: companyId, kind: kind, item: item, by: ref.read(sessionProvider).user!.id),
                      );
                    },
                  ),
                ),
            ],
            if (!canEdit)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  tr('The owner or a project manager sets the company standards.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() f) async {
    try {
      await f();
      ref.invalidate(companyStandardsProvider(companyId));
    } on ExecutionRefused catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    }
  }
}
