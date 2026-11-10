/// Each person's own dashboard: they pick which figures show at the top of
/// the dashboard and in what order. Every figure comes from a report in the
/// library over the sites they can see, and a tap opens that report.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/auth/auth_service.dart' show Roles;
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/money/money_view.dart' show canSeeMoneyIn;
import 'package:fieldos_mobile/features/onboarding/sample_project.dart' show sampleProjectId;
import 'package:fieldos_mobile/features/reports/report_library.dart';
import 'package:fieldos_mobile/features/reports/reports_library_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

enum KpiKind { money, count, number }

class KpiDef {
  const KpiDef(this.id, this.title, this.reportId, this.icon, this.kind, this.value);
  final String id;
  final String title;

  /// The library report it comes from (and opens).
  final String reportId;
  final IconData icon;
  final KpiKind kind;

  /// The figure, from that report's table for this month (or today).
  final double Function(ReportTable t) value;

  ReportDef get report => reportById(reportId)!;

  /// A figure that is bad news when above zero.
  bool get warnsWhenAny => const {'late-tasks', 'open-issues', 'late-pos', 'tools-overdue', 'approvals', 'follow-ups',
        'shortages', 'outside-geofence'}.contains(reportId);
}

double _total(ReportTable t, int col) => ((t.totals?[col] as num?) ?? 0).toDouble();
double _rows(ReportTable t) => t.rows.length.toDouble();

final List<KpiDef> kpiLibrary = [
  KpiDef('spent', 'Spent this month', 'expenses', Icons.payments_outlined, KpiKind.money, (t) => _total(t, 6)),
  KpiDef('received', 'Received this month', 'received', Icons.savings_outlined, KpiKind.money, (t) => _total(t, 4)),
  KpiDef('billed', 'Billed this month', 'client-bills', Icons.receipt_long_outlined, KpiKind.money, (t) => _total(t, 6)),
  KpiDef('material', 'Material received this month', 'grn', Icons.local_shipping_outlined, KpiKind.money, (t) => _total(t, 6)),
  KpiDef('people', 'People-days this month', 'manpower', Icons.groups_outlined, KpiKind.number, (t) => _total(t, 2)),
  KpiDef('wages', 'Wages earned this month', 'wages-due', Icons.engineering_outlined, KpiKind.money, (t) => _total(t, 4)),
  KpiDef('late-tasks', 'Late tasks', 'late-tasks', Icons.running_with_errors_outlined, KpiKind.count, _rows),
  KpiDef('open-issues', 'Open issues', 'open-issues', Icons.report_problem_outlined, KpiKind.count, _rows),
  KpiDef('late-pos', 'Late deliveries', 'late-pos', Icons.schedule_outlined, KpiKind.count, _rows),
  KpiDef('approvals', 'Approvals waiting', 'approvals', Icons.approval_outlined, KpiKind.count, _rows),
  KpiDef('tools-overdue', 'Tools overdue', 'tools-overdue', Icons.handyman_outlined, KpiKind.count, _rows),
  KpiDef('away', 'Punches away from site', 'outside-geofence', Icons.wrong_location_outlined, KpiKind.count, _rows),
  KpiDef('short', 'Arrived short', 'shortages', Icons.inventory_2_outlined, KpiKind.count, _rows),
  KpiDef('store-value', 'Stock in stores', 'store-stock', Icons.warehouse_outlined, KpiKind.money, (t) => _total(t, 5)),
  KpiDef('salaries', 'Salaries this month', 'salary-register', Icons.badge_outlined, KpiKind.money, (t) => _total(t, 9)),
  KpiDef('follow-ups', 'Follow-ups due', 'follow-ups', Icons.phone_callback_outlined, KpiKind.count, _rows),
  KpiDef('pipeline', 'Open enquiries', 'pipeline', Icons.handshake_outlined, KpiKind.money, (t) => _total(t, 2)),
];

KpiDef? kpiById(String id) => kpiLibrary.where((k) => k.id == id).firstOrNull;

/// What a new person sees until they choose: the money and the problems.
const defaultKpis = ['spent', 'received', 'late-tasks', 'open-issues', 'late-pos', 'approvals'];

String kpiPrefKey(String companyId, String userId) => 'dashboard_cards:$companyId:$userId';

bool canSeeKpi(KpiDef k, {required bool moneyIn, required bool manager}) =>
    canOpenReport(k.report, moneyIn: moneyIn, manager: manager);

/// The person's figures in their order, leaving out any they may not see.
Future<List<KpiDef>> loadKpiChoice(AppDatabase db, String companyId, String userId,
    {required bool moneyIn, required bool manager}) async {
  final raw = await db.settingsDao.get(kpiPrefKey(companyId, userId));
  final ids = raw == null ? defaultKpis : [for (final s in raw.split(',')) if (s.isNotEmpty) s];
  return [
    for (final id in ids)
      if (kpiById(id) case final k? when canSeeKpi(k, moneyIn: moneyIn, manager: manager)) k,
  ];
}

Future<void> saveKpiChoice(AppDatabase db, String companyId, String userId, List<String> ids) =>
    db.settingsDao.set(kpiPrefKey(companyId, userId), ids.join(','));

typedef KpiValue = ({KpiDef kpi, double value});

/// The chosen figures worked out over this month for the sites the person
/// can see.
final myKpisProvider = FutureProvider.autoDispose.family<List<KpiValue>, String>((ref, companyId) async {
  final db = ref.watch(appDatabaseProvider);
  final session = ref.watch(sessionProvider);
  final userId = session.user?.id ?? '';
  final moneyIn = canSeeMoneyIn(session.role);
  final manager = Roles.canApprove(session.role);
  final chosen = await loadKpiChoice(db, companyId, userId, moneyIn: moneyIn, manager: manager);
  if (chosen.isEmpty) return const [];
  final visible = await ref.watch(projectsProvider(companyId).future);
  final sample = await sampleProjectId(db, companyId);
  final real = [for (final p in visible) if (p.id != sample) p];
  final now = DateTime.now();
  final (from, to) = reportRange(ReportPeriodChoice.thisMonth, now);
  final input = await loadReportInput(db,
      companyId: companyId, sites: real.isEmpty ? visible : real, from: from, to: to, manager: manager, moneyIn: moneyIn, now: now);
  return [for (final k in chosen) (kpi: k, value: k.value(k.report.build(input)))];
});

String kpiText(KpiDef k, double v) => switch (k.kind) {
      KpiKind.money => rupees(v),
      KpiKind.count => v.toInt().toString(),
      KpiKind.number => fmtQty(v),
    };

/// The grid of chosen figures, with an edit button.
class MyKpiGrid extends ConsumerWidget {
  const MyKpiGrid({super.key, required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myKpisProvider(companyId));
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(tr('My figures'), style: theme.textTheme.titleMedium)),
        TextButton.icon(
          key: const Key('edit-kpis'),
          icon: const Icon(Icons.tune, size: 18),
          label: Text(tr('Choose')),
          onPressed: () async {
            final changed = await showKpiPicker(context, ref, companyId);
            if (changed) ref.invalidate(myKpisProvider(companyId));
          },
        ),
      ]),
      async.when(
        loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        error: (e, _) => Text(tr('Could not work out your figures.')),
        data: (xs) => xs.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(tr('Tap Choose to pick the figures you want to see here.')),
              )
            : LayoutBuilder(builder: (context, c) {
                final perRow = c.maxWidth >= 600 ? 3 : 2;
                final w = (c.maxWidth - 8 * (perRow - 1)) / perRow;
                return Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final x in xs) SizedBox(width: w, child: _KpiTile(x: x, companyId: companyId)),
                ]);
              }),
      ),
      const SizedBox(height: 12),
    ]);
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.x, required this.companyId});
  final KpiValue x;
  final String companyId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warn = x.kpi.warnsWhenAny && x.value > 0;
    final color = warn ? theme.colorScheme.error : theme.colorScheme.onSurface;
    return Card(
      key: Key('kpi-${x.kpi.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => ReportScreen(report: x.kpi.report, companyId: companyId))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(x.kpi.icon, size: 18, color: warn ? color : theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(tr(x.kpi.title), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
              ),
            ]),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(kpiText(x.kpi, x.value),
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: color)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Pick and order the figures. True when the choice changed.
Future<bool> showKpiPicker(BuildContext context, WidgetRef ref, String companyId) async {
  final db = ref.read(appDatabaseProvider);
  final session = ref.read(sessionProvider);
  final userId = session.user?.id ?? '';
  final moneyIn = canSeeMoneyIn(session.role);
  final manager = Roles.canApprove(session.role);
  final current = [for (final k in await loadKpiChoice(db, companyId, userId, moneyIn: moneyIn, manager: manager)) k.id];
  final all = [for (final k in kpiLibrary) if (canSeeKpi(k, moneyIn: moneyIn, manager: manager)) k];
  // Chosen first in their order, then the rest.
  final order = [...current, for (final k in all) if (!current.contains(k.id)) k.id];
  final on = {...current};
  if (!context.mounted) return false;
  final saved = await showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(tr('My figures'), style: Theme.of(ctx).textTheme.titleMedium),
            subtitle: Text(tr('Tick the ones you want. Drag to change the order.')),
          ),
          Flexible(
            child: ReorderableListView(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              onReorderItem: (a, b) => set(() => order.insert(b, order.removeAt(a))),
              children: [
                for (final (i, id) in order.indexed)
                  CheckboxListTile(
                    key: Key('pick-$id'),
                    value: on.contains(id),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(tr(kpiById(id)!.title)),
                    secondary: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                    onChanged: (v) => set(() => v == true ? on.add(id) : on.remove(id)),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: OverflowBar(alignment: MainAxisAlignment.spaceBetween, overflowAlignment: OverflowBarAlignment.end, children: [
              TextButton(
                onPressed: () => set(() {
                  on
                    ..clear()
                    ..addAll(defaultKpis.where((id) => all.any((k) => k.id == id)));
                  order
                    ..removeWhere((_) => true)
                    ..addAll([...on, for (final k in all) if (!on.contains(k.id)) k.id]);
                }),
                child: Text(tr('Reset')),
              ),
              FilledButton(
                key: const Key('kpis-save'),
                onPressed: () => Navigator.pop(ctx, [for (final id in order) if (on.contains(id)) id]),
                child: Text(tr('Save')),
              ),
            ]),
          ),
        ]),
      ),
    ),
  );
  if (saved == null) return false;
  await saveKpiChoice(db, companyId, userId, saved);
  return true;
}
