/// The manager's daily reports board: for every running site, whether
/// today's report is submitted, not received yet (with when the
/// supervisor's phone last synced), or the site was closed, and how
/// yesterday went. A missing report is never shown as zero activity.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/close/week_close_screen.dart' show closeNamesProvider;
import 'package:fieldos_mobile/features/daily/day_close.dart';
import 'package:fieldos_mobile/features/daily/day_close_data.dart';
import 'package:fieldos_mobile/features/daily/day_close_widgets.dart';
import 'package:fieldos_mobile/features/daily/today_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

class DailyReportsScreen extends ConsumerWidget {
  const DailyReportsScreen({super.key, required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dayBoardProvider(companyId));
    final names = ref.watch(closeNamesProvider(companyId)).value ?? const {};
    final sync = ref.watch(memberSyncProvider(companyId)).value ?? const {};
    final me = ref.watch(sessionProvider).user!.id;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Daily reports'))),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st, onRetry: () => ref.invalidate(dayBoardProvider(companyId))),
        data: (rows) {
          final now = DateTime.now();
          if (rows.isEmpty) {
            return EmptyState(
              icon: Icons.fact_check_outlined,
              title: tr('No running sites'),
              message: tr('Sites marked active show their daily report here.'),
            );
          }
          final today = [for (final r in rows) r.today.status(now)];
          final done = today.where((s) => s == DayStatus.submitted || s == DayStatus.siteClosed).length;
          final notIn = today.where((s) => s == DayStatus.notReceived || s == DayStatus.missed).length;
          final open = today.where((s) => s == DayStatus.open).length;
          final sorted = [...rows]..sort((a, b) => _rank(a, now).compareTo(_rank(b, now)));
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(memberSyncProvider(companyId));
              return ref.refresh(dayBoardProvider(companyId).future);
            },
            child: ListView(padding: const EdgeInsets.all(12), children: [
              Text(
                trf('Today: {done} submitted, {missing} not received, {open} not due yet',
                    {'done': done, 'missing': notIn, 'open': open}),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                tr('"Not received" means the report hasn\'t reached the server. If the supervisor\'s phone last '
                    'synced before the cutoff, it may be saved there, waiting for signal.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (final r in sorted) _SiteCard(row: r, names: names, sync: sync, me: me, now: now),
            ]),
          );
        },
      ),
    );
  }

  static int _rank(SiteDayRow r, DateTime now) => switch (r.today.status(now)) {
        DayStatus.missed => 0,
        DayStatus.notReceived => 1,
        DayStatus.open => 2,
        DayStatus.submitted => 3,
        DayStatus.siteClosed => 4,
      };
}

class _SiteCard extends StatelessWidget {
  const _SiteCard({required this.row, required this.names, required this.sync, required this.me, required this.now});
  final SiteDayRow row;
  final Map<String, String> names;
  final Map<String, MemberSyncStatusData> sync;
  final String me;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reporter = reporterFor(row.records, row.today.day);
    final yReporter = reporterFor(row.records, row.yesterday.day);
    DateTime? last(String? who) => who == null || who == me ? null : sync[who]?.lastSyncedAt;
    final (yLabel, yTone) = dayStatusText(row.yesterday, now, lastSync: last(yReporter));
    final s = row.today.submission;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openToday(context, row.project),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(row.project.name, style: theme.textTheme.titleMedium)),
              if (row.isRepeat)
                StatusPill(trf('{n} misses in 2 weeks', {'n': row.missed.length}), tone: PillTone.danger),
            ]),
            const SizedBox(height: 6),
            DayStatusLine(
              day: row.today,
              now: now,
              waitingToSync: false,
              names: names,
              sync: sync,
              me: me,
              reporter: reporter,
            ),
            if (s != null && !s.siteClosed) ...[
              const SizedBox(height: 4),
              Text(
                [
                  trf('{n} people', {'n': row.today.snapshot.people.length}),
                  row.today.snapshot.receipts.isEmpty
                      ? tr('No deliveries')
                      : trf('{n} deliveries', {'n': row.today.snapshot.receipts.length}),
                  row.today.snapshot.expenses.isEmpty ? tr('No expenses') : rupees(row.today.snapshot.expenseTotal),
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 6),
            InkWell(
              onTap: () => openToday(context, row.project, day: row.yesterday.day),
              child: Row(children: [
                Text('${tr('Yesterday')}: ', style: theme.textTheme.bodySmall),
                Flexible(child: StatusPill(yLabel, tone: yTone)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
