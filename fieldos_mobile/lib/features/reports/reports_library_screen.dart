/// Home menu > Reports: the report library. Find a report, pick the sites
/// and the period, see it on the phone, and share it as a PDF with the
/// company's own look or as an Excel sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/auth/auth_service.dart' show Roles;
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/company/branding.dart';
import 'package:fieldos_mobile/features/money/bills_view.dart' show billingProfileProvider;
import 'package:fieldos_mobile/features/money/money_view.dart' show canSeeMoneyIn;
import 'package:fieldos_mobile/features/onboarding/sample_project.dart' show sampleProjectId;
import 'package:fieldos_mobile/features/reports/report_library.dart';
import 'package:fieldos_mobile/features/reports/report_output.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

enum ReportPeriodChoice { thisMonth, lastMonth, thisWeek, lastWeek, thisYear, lastYear, allTime }

const reportPeriodLabels = {
  ReportPeriodChoice.thisMonth: 'This month',
  ReportPeriodChoice.lastMonth: 'Last month',
  ReportPeriodChoice.thisWeek: 'This week',
  ReportPeriodChoice.lastWeek: 'Last week',
  ReportPeriodChoice.thisYear: 'This financial year',
  ReportPeriodChoice.lastYear: 'Last financial year',
  ReportPeriodChoice.allTime: 'Since the start',
};

/// The first day and the day after the last. Weeks start on Monday and
/// financial years on 1 April.
(DateTime, DateTime) reportRange(ReportPeriodChoice c, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));
  final monday = today.subtract(Duration(days: today.weekday - DateTime.monday));
  final fy = now.month >= 4 ? now.year : now.year - 1;
  return switch (c) {
    ReportPeriodChoice.thisMonth => (DateTime(now.year, now.month), tomorrow),
    ReportPeriodChoice.lastMonth => (DateTime(now.year, now.month - 1), DateTime(now.year, now.month)),
    ReportPeriodChoice.thisWeek => (monday, tomorrow),
    ReportPeriodChoice.lastWeek => (monday.subtract(const Duration(days: 7)), monday),
    ReportPeriodChoice.thisYear => (DateTime(fy, 4), tomorrow),
    ReportPeriodChoice.lastYear => (DateTime(fy - 1, 4), DateTime(fy, 4)),
    ReportPeriodChoice.allTime => (DateTime(2000), tomorrow),
  };
}

class ReportsLibraryScreen extends ConsumerStatefulWidget {
  const ReportsLibraryScreen({super.key, required this.companyId});
  final String companyId;

  @override
  ConsumerState<ReportsLibraryScreen> createState() => _ReportsLibraryScreenState();
}

class _ReportsLibraryScreenState extends ConsumerState<ReportsLibraryScreen> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(ReportDef r) {
    if (_q.isEmpty) return true;
    final q = _q.toLowerCase();
    return [r.title, r.about, tr(r.title), tr(r.about), tr(reportGroupLabels[r.group]!)].any((s) => s.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(sessionProvider).role;
    final open = [
      for (final r in reportLibrary)
        if (canOpenReport(r, moneyIn: canSeeMoneyIn(role), manager: Roles.canApprove(role)) && _matches(r)) r,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(tr('Reports'))),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            key: const Key('report-search'),
            controller: _search,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('Find a report')),
            onChanged: (v) => setState(() => _q = v.trim()),
          ),
        ),
        if (open.isEmpty)
          Padding(padding: const EdgeInsets.all(24), child: Text(tr('No report matches.'), textAlign: TextAlign.center)),
        for (final g in ReportGroup.values)
          if (open.any((r) => r.group == g)) ...[
            SectionHeader(reportGroupLabels[g]!),
            for (final r in open.where((r) => r.group == g))
              ListTile(
                key: Key('report-${r.id}'),
                title: Text(tr(r.title)),
                subtitle: Text(tr(r.about)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ReportScreen(report: r, companyId: widget.companyId))),
              ),
          ],
      ]),
    );
  }
}

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key, required this.report, required this.companyId, this.now});
  final ReportDef report;
  final String companyId;

  /// For tests.
  final DateTime? now;

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  ReportPeriodChoice _period = ReportPeriodChoice.thisMonth;

  /// Null is every site this person can see.
  Set<String>? _sites;
  Future<(ReportTable, List<Project>)>? _future;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(ReportTable, List<Project>)> _load() async {
    final db = ref.read(appDatabaseProvider);
    final role = ref.read(sessionProvider).role;
    final visible = await ref.read(projectsProvider(widget.companyId).future);
    final sample = await sampleProjectId(db, widget.companyId);
    // The sample site stays out of real totals, unless it is all there is.
    final real = [for (final p in visible) if (p.id != sample) p];
    final all = (real.isEmpty ? [...visible] : real)..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final chosen = _sites == null ? all : [for (final p in all) if (_sites!.contains(p.id)) p];
    final (from, to) = reportRange(_period, _now);
    final input = await loadReportInput(db,
        companyId: widget.companyId, sites: chosen, from: from, to: to,
        manager: Roles.canApprove(role), moneyIn: canSeeMoneyIn(role), now: _now);
    return (widget.report.build(input), all);
  }

  void _reload() {
    final next = _load();
    setState(() {
      _future = next;
    });
  }

  String _sitesText(List<Project> all) {
    if (_sites == null || _sites!.length == all.length) return 'All sites';
    final names = [for (final p in all) if (_sites!.contains(p.id)) p.name];
    return names.length <= 3 ? names.join(', ') : '${names.length} sites';
  }

  Future<void> _pickSites(List<Project> all) async {
    final picked = {...(_sites ?? {for (final p in all) p.id})};
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              title: Text(tr('Sites in the report'), style: Theme.of(ctx).textTheme.titleMedium),
              trailing: TextButton(
                onPressed: () => set(() => picked.length == all.length ? picked.clear() : picked.addAll(all.map((p) => p.id))),
                child: Text(picked.length == all.length ? tr('None') : tr('All')),
              ),
            ),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final p in all)
                  CheckboxListTile(
                    value: picked.contains(p.id),
                    title: Text(p.name),
                    onChanged: (v) => set(() => v == true ? picked.add(p.id) : picked.remove(p.id)),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton(
                key: const Key('sites-done'),
                onPressed: picked.isEmpty ? null : () => Navigator.pop(ctx, true),
                child: Text(tr('Done')),
              ),
            ),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    _sites = picked.length == all.length ? null : picked;
    _reload();
  }

  Future<void> _share({required bool pdf}) async {
    final (table, all) = await _future!;
    final db = ref.read(appDatabaseProvider);
    final company = ref.read(sessionProvider).activeCompany;
    final r = widget.report;
    final (from, to) = reportRange(_period, _now);
    final period = r.usesPeriod ? periodText(from, to) : null;
    try {
      if (pdf) {
        final bytes = await buildReportPdf(
          report: r,
          table: table,
          companyName: company?.name ?? '',
          sitesText: _sitesText(all),
          periodLine: period,
          profile: await ref.read(billingProfileProvider(widget.companyId).future),
          branding: await loadBranding(db, widget.companyId),
          now: _now,
        );
        await shareReportFile(bytes, reportFileName(r, _now, 'pdf'), 'application/pdf', '${r.title}: ${_sitesText(all)}');
      } else {
        await shareReportFile(buildReportXlsx(r, table), reportFileName(r, _now, 'xlsx'),
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', '${r.title}: ${_sitesText(all)}');
      }
    } catch (e) {
      if (mounted) showSnack(context, tr('Could not make the file. Please try again.'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(r.title)),
        actions: [
          IconButton(
              key: const Key('report-pdf'),
              tooltip: tr('Share PDF'),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () => _share(pdf: true)),
          IconButton(
              key: const Key('report-xlsx'),
              tooltip: tr('Share Excel'),
              icon: const Icon(Icons.table_view_outlined),
              onPressed: () => _share(pdf: false)),
        ],
      ),
      body: FutureBuilder<(ReportTable, List<Project>)>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return ErrorState(error: snap.error!, stack: snap.stackTrace);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (table, all) = snap.data!;
          return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
            Text(tr(r.about)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              ActionChip(
                key: const Key('report-sites'),
                avatar: const Icon(Icons.location_city_outlined, size: 18),
                label: Text(_sites == null ? tr('All sites') : _sitesText(all)),
                onPressed: all.isEmpty ? null : () => _pickSites(all),
              ),
              if (r.usesPeriod)
                for (final c in ReportPeriodChoice.values)
                  ChoiceChip(
                    key: Key('period-${c.name}'),
                    label: Text(tr(reportPeriodLabels[c]!)),
                    selected: _period == c,
                    onSelected: (_) {
                      _period = c;
                      _reload();
                    },
                  ),
            ]),
            if (!r.usesPeriod)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(tr('Shows how things stand today.'), style: Theme.of(context).textTheme.bodySmall),
              ),
            const SizedBox(height: 8),
            if (table.rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(tr('Nothing recorded for this report.'), textAlign: TextAlign.center),
              )
            else
              _ReportGrid(table: table),
            if (table.note != null)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(tr(table.note!), style: Theme.of(context).textTheme.bodySmall)),
          ]);
        },
      ),
    );
  }
}

/// The table on the phone: the first 200 rows, the rest in the PDF and Excel.
class _ReportGrid extends StatelessWidget {
  const _ReportGrid({required this.table});
  final ReportTable table;
  static const shown = 200;

  @override
  Widget build(BuildContext context) {
    final money = [for (final h in table.headers) moneyHeaders.contains(h)];
    final numeric = [for (var i = 0; i < table.headers.length; i++) table.rows.any((r) => r[i] is num) || money[i]];
    final totals = table.totals;
    final bold = Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700);
    DataRow row(List<Object?> cells, {bool total = false}) => DataRow(cells: [
          for (var i = 0; i < cells.length; i++)
            DataCell(ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(i == 0 && total ? tr('Total') : cellText(cells[i], money: money[i]),
                  style: total ? bold : null, overflow: TextOverflow.ellipsis, maxLines: 2),
            )),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(trf('{n} rows', {'n': table.rows.length}), style: Theme.of(context).textTheme.bodySmall),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          key: const Key('report-table'),
          headingRowHeight: 40,
          dataRowMinHeight: 36,
          columnSpacing: 16,
          columns: [
            for (var i = 0; i < table.headers.length; i++) DataColumn(label: Text(tr(table.headers[i])), numeric: numeric[i]),
          ],
          rows: [
            for (final r in table.rows.take(shown)) row(r),
            if (totals != null) row(totals, total: true),
          ],
        ),
      ),
      if (table.rows.length > shown)
        Text(trf('Showing the first {n}. Share the PDF or Excel for all of them.', {'n': shown}),
            style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}
