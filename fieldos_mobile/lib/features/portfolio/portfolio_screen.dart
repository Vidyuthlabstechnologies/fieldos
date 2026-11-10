/// Every running site on one screen: missing reports, waiting and overdue
/// approvals, the week's close, and money outstanding. Rules in
/// portfolio.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/auth/site_roles.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/features/close/week_close_screen.dart';
import 'package:fieldos_mobile/features/money/money_view.dart' show canSeeMoneyIn;
import 'package:fieldos_mobile/features/portfolio/portfolio.dart';
import 'package:fieldos_mobile/features/project/project_detail_screen.dart';
import 'package:fieldos_mobile/features/tasks/team_roster.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

final portfolioProvider = FutureProvider.autoDispose.family<List<SiteStatus>, String>((ref, companyId) async {
  final db = ref.watch(appDatabaseProvider);
  final s = ref.watch(sessionProvider);
  final roster = await ref.watch(teamRosterProvider(companyId).future);
  final visible =
      await visibleSiteIds(db, companyId, userId: s.user?.id, companyRole: s.role, cloudUserId: roster.myUserId);
  return buildPortfolio(db, companyId, visible: visible);
});

class PortfolioScreen extends ConsumerWidget {
  const PortfolioScreen({super.key, required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sites = ref.watch(portfolioProvider(companyId));
    final money = canSeeMoneyIn(ref.watch(sessionProvider).role);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('All sites'))),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(portfolioProvider(companyId).future),
        child: sites.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => ErrorState(error: e, stack: st, onRetry: () => ref.invalidate(portfolioProvider(companyId))),
          data: (list) {
            if (list.isEmpty) {
              return EmptyState(
                icon: Icons.domain_outlined,
                title: tr('No running sites'),
                message: tr('Sites marked as running show here, the ones that need someone first.'),
              );
            }
            final t = PortfolioTotals(list);
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        t.needingAttention == 0
                            ? trf('All {n} sites are up to date.', {'n': list.length})
                            : trf('{m} of {n} sites need someone.', {'m': t.needingAttention, 'n': list.length}),
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        if (t.missingReports > 0)
                          StatusPill(trf('{n} days without a report', {'n': t.missingReports}), tone: PillTone.danger),
                        if (t.overdueApprovals > 0)
                          StatusPill(trf('{n} approvals waiting over 2 days', {'n': t.overdueApprovals}),
                              tone: PillTone.warn),
                        if (t.weeksOpen > 0)
                          StatusPill(trf('{n} sites with last week not closed', {'n': t.weeksOpen}), tone: PillTone.warn),
                      ]),
                      const SizedBox(height: 12),
                      _MoneyRow(tr('Wages due this week'), t.wagesDue),
                      _MoneyRow(tr('Owed to suppliers'), t.supplierDue),
                      if (money) ...[
                        _MoneyRow(tr('To come from clients'), t.clientReceivable),
                        if (t.retentionHeld > 0.005) _MoneyRow(tr('Retention held by clients'), t.retentionHeld),
                      ],
                    ]),
                  ),
                ),
                for (final s in list) _SiteCard(status: s, showMoneyIn: money),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow(this.label, this.amount);
  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text(rupees(amount), style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );
}

class _SiteCard extends StatelessWidget {
  const _SiteCard({required this.status, required this.showMoneyIn});
  final SiteStatus status;
  final bool showMoneyIn;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final theme = Theme.of(context);
    final pills = <Widget>[
      if (s.missingReportDays.isNotEmpty)
        StatusPill(
            s.missingReportDays.length == 1
                ? trf('No report on {day}', {'day': fmtDate(s.missingReportDays.first, short: true)})
                : trf('{n} days without a report', {'n': s.missingReportDays.length}),
            tone: PillTone.danger),
      if (s.closeSentBack > 0) StatusPill(trf('{n} sent back', {'n': s.closeSentBack}), tone: PillTone.danger),
      if (s.closeWaiting > 0) StatusPill(trf('{n} to approve', {'n': s.closeWaiting}), tone: PillTone.warn),
      if (s.overdueApprovals > 0)
        StatusPill(trf('{n} approvals waiting over 2 days', {'n': s.overdueApprovals}), tone: PillTone.warn),
      if (s.lastWeekOpen) StatusPill(tr('Last week not closed'), tone: PillTone.warn),
      if (s.weekClosed) StatusPill(tr('Week closed'), tone: PillTone.ok),
      if (s.allWell && !s.weekClosed) StatusPill(tr('Up to date'), tone: PillTone.ok),
    ];
    final money = [
      if (s.wagesDue > 0.005) trf('wages due {amount}', {'amount': rupees(s.wagesDue)}),
      if (s.supplierDue > 0.005) trf('suppliers {amount}', {'amount': rupees(s.supplierDue)}),
      if (showMoneyIn && s.clientReceivable > 0.005) trf('client owes {amount}', {'amount': rupees(s.clientReceivable)}),
    ];
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: s.project))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(s.project.name, style: theme.textTheme.titleMedium)),
              IconButton(
                tooltip: tr('Weekly close'),
                icon: const Icon(Icons.fact_check_outlined),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => WeekCloseScreen(project: s.project, weekOf: DateTime.now()))),
              ),
            ]),
            Wrap(spacing: 6, runSpacing: 6, children: pills),
            if (money.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(money.join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ]),
        ),
      ),
    );
  }
}
