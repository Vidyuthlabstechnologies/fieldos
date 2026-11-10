/// The daily close on Home: the supervisor sees each site's report still
/// to send; the owner or a PM sees how many came in and how many didn't.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/features/daily/day_close.dart';
import 'package:fieldos_mobile/features/daily/day_close_data.dart';
import 'package:fieldos_mobile/features/daily/daily_reports_screen.dart';
import 'package:fieldos_mobile/features/daily/today_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

class TodayHomeCard extends ConsumerWidget {
  const TodayHomeCard({super.key, required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(dayBoardProvider(companyId)).value;
    final session = ref.watch(sessionProvider);
    final role = session.role;
    if (rows == null || rows.isEmpty || role == null || !Roles.canWrite(role)) return const SizedBox.shrink();
    final now = DateTime.now();
    final theme = Theme.of(context);
    if (Roles.canApprove(role)) {
      final st = [for (final r in rows) r.today.status(now)];
      final done = st.where((s) => s == DayStatus.submitted || s == DayStatus.siteClosed).length;
      final notIn = st.where((s) => s == DayStatus.notReceived || s == DayStatus.missed).length;
      final yMissed = rows.where((r) => r.yesterday.status(now) == DayStatus.missed).length;
      return Card(
        child: ListTile(
          leading: const Icon(Icons.fact_check_outlined),
          title: Text(tr('Daily reports')),
          subtitle: Text([
            trf('{done} of {n} in today', {'done': done, 'n': rows.length}),
            if (notIn > 0) trf('{n} not received', {'n': notIn}),
            if (yMissed > 0) trf('{n} missing from yesterday', {'n': yMissed}),
          ].join(' · ')),
          trailing: notIn + yMissed > 0
              ? Icon(Icons.error_outline, color: toneColor(context, PillTone.danger))
              : const Icon(Icons.chevron_right),
          onTap: () =>
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DailyReportsScreen(companyId: companyId))),
        ),
      );
    }
    final me = session.user!.id;
    final mine = [
      for (final r in rows)
        if (r.records.setup.remindsUser(me, r.today.day, canRecord: true)) r
    ];
    if (mine.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Column(children: [
        for (final r in mine)
          ListTile(
            leading: Icon(
              r.today.isSubmitted ? Icons.check_circle : Icons.today_outlined,
              color: r.today.isSubmitted ? toneColor(context, PillTone.ok) : null,
            ),
            title: Text(trf("Today's report · {site}", {'site': r.project.name})),
            subtitle: Text(
              r.today.isSubmitted
                  ? tr('Sent')
                  : () {
                      final left = missingItems(r.today.snapshot, const NothingMarks());
                      return left.isEmpty
                          ? tr('Everything is recorded. Send it.')
                          : trf('Still to do: {items}', {'items': left.map(checkLabel).join(', ')});
                    }(),
              style: theme.textTheme.bodySmall,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openToday(context, r.project),
          ),
        for (final r in mine)
          if (r.yesterday.status(now) == DayStatus.missed)
            ListTile(
              leading: Icon(Icons.history, color: toneColor(context, PillTone.danger)),
              title: Text(trf("Yesterday's report is missing · {site}", {'site': r.project.name})),
              subtitle: Text(tr('Add what happened and send it now. Late is fine.'), style: theme.textTheme.bodySmall),
              onTap: () => openToday(context, r.project, day: r.yesterday.day),
            ),
      ]),
    );
  }
}
