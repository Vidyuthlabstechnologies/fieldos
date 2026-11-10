/// The pilot scorecard on the phone: pick when the pilot started, see each
/// measure for week 1, days 8 to 30 and days 31 to 60, and share the PDF.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/company/branding.dart';
import 'package:fieldos_mobile/features/reports/pilot_scorecard.dart';
import 'package:fieldos_mobile/features/reports/report_output.dart' show shareReportFile;
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

final _pilotStartProvider = FutureProvider.autoDispose.family<DateTime?, String>(
    (ref, projectId) => loadPilotStart(ref.watch(appDatabaseProvider), projectId));

final _scorecardProvider = FutureProvider.autoDispose.family<PilotScorecard?, Project>((ref, site) async {
  final start = await ref.watch(_pilotStartProvider(site.id).future);
  if (start == null) return null;
  return buildPilotScorecard(ref.watch(appDatabaseProvider), site, start);
});

String _measure(String m) => switch (m) {
      'Days with a daily report' => tr('Days with a daily report'),
      'Daily reports sent the same day' => tr('Daily reports sent the same day'),
      'Cash short at counts' => tr('Cash short at counts'),
      'Cash spent with no bill' => tr('Cash spent with no bill'),
      'Expenses with a bill attached' => tr('Expenses with a bill attached'),
      'Deliveries with a challan photo' => tr('Deliveries with a challan photo'),
      'Labour marked inside the site fence' => tr('Labour marked inside the site fence'),
      'Budget overruns flagged' => tr('Budget overruns flagged'),
      'Days from bill to payment' => tr('Days from bill to payment'),
      'Office time saved (estimate)' => tr('Office time saved (estimate)'),
      _ => m,
    };

String _period(String p) => switch (p) {
      'Week 1 (baseline)' => tr('Week 1 (baseline)'),
      'Days 8 to 30' => tr('Days 8 to 30'),
      'Days 31 to 60' => tr('Days 31 to 60'),
      _ => p,
    };

class PilotScorecardScreen extends ConsumerWidget {
  const PilotScorecardScreen({super.key, required this.project});
  final Project project;

  Future<void> _pickStart(BuildContext context, WidgetRef ref, DateTime? current) async {
    final d = await showDatePicker(
      context: context,
      helpText: tr('When did the pilot start?'),
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (d == null) return;
    await savePilotStart(ref.read(appDatabaseProvider), project.id, d);
    ref.invalidate(_pilotStartProvider(project.id));
  }

  Future<void> _share(BuildContext context, WidgetRef ref, PilotScorecard card) async {
    try {
      final db = ref.read(appDatabaseProvider);
      final company = ref.read(sessionProvider).activeCompany;
      final bytes = await buildPilotScorecardPdf(card,
          companyName: company?.name ?? project.name, branding: await loadBranding(db, company?.id));
      await shareReportFile(bytes, 'FieldOS Pilot scorecard ${project.name.replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '')}.pdf',
          'application/pdf', 'Pilot scorecard: ${project.name}');
    } catch (e, st) {
      if (context.mounted) showSnack(context, friendlyError(e, st), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final start = ref.watch(_pilotStartProvider(project.id));
    final card = ref.watch(_scorecardProvider(project));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Pilot scorecard')),
        actions: [
          if (card.value != null)
            IconButton(
              tooltip: tr('Share PDF'),
              icon: const Icon(Icons.ios_share),
              onPressed: () => _share(context, ref, card.value!),
            ),
        ],
      ),
      body: card.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
        data: (c) {
          if (c == null) {
            return EmptyState(
              icon: Icons.insights_outlined,
              title: tr('Measure a 60-day pilot on this site'),
              message: tr(
                  'Week 1 is the baseline. At day 30 and day 60 the scorecard shows what changed, from what this site recorded: reports, cash, bills, challans, attendance and payments.'),
              actionLabel: tr('Set the start date'),
              onAction: () => _pickStart(context, ref, null),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(trf('Pilot started {date}', {'date': fmtDate(c.start)})),
                trailing: TextButton(onPressed: () => _pickStart(context, ref, start.value), child: Text(tr('Change'))),
              ),
              for (final r in c.rows)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(_measure(r.measure), style: theme.textTheme.titleSmall)),
                        if (r.change == 'better') StatusPill(tr('Better'), tone: PillTone.ok),
                        if (r.change == 'worse') StatusPill(tr('Worse'), tone: PillTone.danger),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        for (var i = 0; i < c.periods.length; i++)
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(_period(c.periods[i].label), style: theme.textTheme.bodySmall),
                              Text(r.cell(i), style: theme.textTheme.titleMedium),
                            ]),
                          ),
                      ]),
                    ]),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                    tr('Every figure comes from what this site recorded. Office time uses fixed minutes per record and is an estimate.'),
                    style: theme.textTheme.bodySmall),
              ),
            ],
          );
        },
      ),
    );
  }
}
