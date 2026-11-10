/// The RERA quarterly progress pack on the phone: the site's RERA number,
/// each block and floor's stage, and the PDF for the quarter.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/company/branding.dart';
import 'package:fieldos_mobile/features/money/money_view.dart' show isoDay;
import 'package:fieldos_mobile/features/reports/rera_pack.dart';
import 'package:fieldos_mobile/features/reports/report_output.dart' show shareReportFile;
import 'package:fieldos_mobile/features/team/site_team_screen.dart' show mySiteAccessProvider;
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

final _reraNumberProvider = FutureProvider.autoDispose.family<String?, String>(
    (ref, projectId) => ref.watch(appDatabaseProvider).settingsDao.get(reraNumberKey(projectId)));

final _floorRowsProvider = FutureProvider.autoDispose.family<List<FloorProgressData>, String>(
    (ref, projectId) => ref.watch(appDatabaseProvider).floorProgressDao.forProject(projectId));

String stageLabel(String s) => switch (s) {
      'not_started' => tr('Not started'),
      'excavation' => tr('Excavation'),
      'foundation' => tr('Foundation'),
      'plinth' => tr('Plinth'),
      'columns' => tr('Columns'),
      'slab' => tr('Slab cast'),
      'masonry' => tr('Brickwork'),
      'plastering' => tr('Plastering'),
      'flooring' => tr('Flooring'),
      'finishing' => tr('Finishing'),
      'complete' => tr('Complete'),
      _ => s,
    };

class ReraScreen extends ConsumerStatefulWidget {
  const ReraScreen({super.key, required this.project});
  final Project project;

  @override
  ConsumerState<ReraScreen> createState() => _ReraScreenState();
}

class _ReraScreenState extends ConsumerState<ReraScreen> {
  late Quarter _quarter = reportingQuarter(DateTime.now());
  bool _making = false;

  String get _pid => widget.project.id;

  void _refresh() {
    ref.invalidate(_floorRowsProvider(_pid));
    ref.invalidate(_reraNumberProvider(_pid));
  }

  Future<void> _editNumber(String? current) async {
    final c = TextEditingController(text: current ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('RERA registration number')),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(hintText: tr('As on the RERA certificate')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(tr('Save'))),
        ],
      ),
    );
    if (v == null) return;
    await ref.read(appDatabaseProvider).settingsDao.set(reraNumberKey(_pid), v);
    _refresh();
  }

  Future<void> _addFloors() async {
    final block = TextEditingController(text: 'Block A');
    final count = TextEditingController(text: '5');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Add a block')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: block, maxLength: 60, decoration: InputDecoration(labelText: tr('Block or tower name'))),
          TextField(
            controller: count,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: tr('Floors above ground'), helperText: tr('Ground floor is added too')),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Add'))),
        ],
      ),
    );
    final n = int.tryParse(count.text.trim());
    if (ok != true || block.text.trim().isEmpty || n == null || n < 0 || n > 80) {
      if (ok == true && mounted) showSnack(context, tr('Give a block name and 0 to 80 floors'), error: true);
      return;
    }
    final db = ref.read(appDatabaseProvider);
    final me = ref.read(sessionProvider).user?.id ?? 'local';
    final today = isoDay(DateTime.now());
    for (final f in ['Ground', for (var i = 1; i <= n; i++) '$i']) {
      await db.floorProgressDao.record(
          projectId: _pid, block: block.text, floor: f, stage: 'not_started', pct: 0, asOf: today, by: me);
    }
    _refresh();
  }

  Future<void> _update(FloorProgressData f) async {
    var stage = f.stage;
    var pct = f.pct.toDouble();
    var day = DateTime.now();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(trf('{block}, floor {floor}', {'block': f.block, 'floor': f.floor}),
                style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in FloorProgressDao.stages)
                ChoiceChip(
                  label: Text(stageLabel(s)),
                  selected: stage == s,
                  onSelected: (_) => set(() {
                    stage = s;
                    pct = (stagePct[s] ?? 0).toDouble();
                  }),
                ),
            ]),
            const SizedBox(height: 12),
            Text(trf('{pct}% complete', {'pct': '${pct.round()}'})),
            Slider(value: pct, min: 0, max: 100, divisions: 20, onChanged: (v) => set(() => pct = v)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(trf('As on {date}', {'date': fmtDate(day)})),
              onTap: () async {
                final d = await showDatePicker(
                    context: ctx, initialDate: day, firstDate: DateTime(2020), lastDate: DateTime.now());
                if (d != null) set(() => day = d);
              },
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
            ),
          ]),
        ),
      ),
    );
    if (saved != true) return;
    try {
      await ref.read(appDatabaseProvider).floorProgressDao.record(
            projectId: _pid,
            block: f.block,
            floor: f.floor,
            stage: stage,
            pct: pct.round(),
            asOf: isoDay(day),
            by: ref.read(sessionProvider).user?.id ?? 'local',
          );
      _refresh();
    } catch (e, st) {
      if (mounted) showSnack(context, friendlyError(e, st), error: true);
    }
  }

  Future<void> _makePdf() async {
    setState(() => _making = true);
    try {
      final db = ref.read(appDatabaseProvider);
      final company = ref.read(sessionProvider).activeCompany;
      final pack = await buildReraPack(db, widget.project, _quarter);
      final bytes = await buildReraPackPdf(pack,
          companyName: company?.name ?? widget.project.name, branding: await loadBranding(db, company?.id));
      final safe = widget.project.name.replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '');
      await shareReportFile(bytes, 'RERA progress $safe ${_quarter.label}.pdf', 'application/pdf',
          'RERA quarterly progress: ${widget.project.name}, ${_quarter.label}');
    } catch (e, st) {
      if (mounted) showSnack(context, friendlyError(e, st), error: true);
    } finally {
      if (mounted) setState(() => _making = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(mySiteAccessProvider(_pid)).value;
    final canWrite = access?.canWrite ?? false;
    final manages = access?.managesSite ?? false;
    final number = ref.watch(_reraNumberProvider(_pid));
    final rows = ref.watch(_floorRowsProvider(_pid));
    final theme = Theme.of(context);
    final now = DateTime.now();
    final latestQuarter = Quarter.of(now);

    return Scaffold(
      appBar: AppBar(title: Text(tr('RERA quarterly report'))),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: _addFloors, icon: const Icon(Icons.apartment_outlined), label: Text(tr('Add a block')))
          : null,
      body: rows.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st, onRetry: _refresh),
        data: (all) {
          final floors = progressAsOf(all, isoDay(now));
          final blocks = <String, List<FloorProgressData>>{};
          for (final f in floors) {
            (blocks[f.block] ??= []).add(f);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            children: [
              ListTile(
                leading: const Icon(Icons.verified_outlined),
                title: Text(tr('RERA registration number')),
                subtitle: Text(number.value?.isNotEmpty == true ? number.value! : tr('Not added yet')),
                trailing: manages ? TextButton(onPressed: () => _editNumber(number.value), child: Text(tr('Change'))) : null,
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      IconButton(
                        tooltip: tr('Earlier quarter'),
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => setState(() => _quarter = _quarter.previous),
                      ),
                      Expanded(
                        child: Text(_quarter.label, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                      ),
                      IconButton(
                        tooltip: tr('Later quarter'),
                        icon: const Icon(Icons.chevron_right),
                        onPressed: _quarter == latestQuarter ? null : () => setState(() => _quarter = _quarter.next),
                      ),
                    ]),
                    Text(trf('Upload to TS-RERA by {date}', {'date': fmtDate(_quarter.dueBy)}),
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _making ? null : _makePdf,
                        icon: _making
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.picture_as_pdf_outlined),
                        label: Text(tr('Make the progress PDF')),
                      ),
                    ),
                  ]),
                ),
              ),
              if (floors.isEmpty)
                EmptyState(
                  compact: true,
                  icon: Icons.apartment_outlined,
                  title: tr('Add the blocks and floors'),
                  message: tr(
                      'Mark each floor\'s stage as work moves. The quarterly PDF shows each floor at the quarter\'s end, the daily reports and site photos.'),
                ),
              for (final e in blocks.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
                  child: Row(children: [
                    Expanded(child: Text(e.key, style: theme.textTheme.titleSmall)),
                    Text(trf('{pct}% complete', {'pct': '${averagePct(e.value).round()}'}),
                        style: theme.textTheme.bodySmall),
                  ]),
                ),
                Card(
                  child: Column(children: [
                    for (final f in e.value)
                      ListTile(
                        dense: true,
                        title: Text(trf('Floor {floor}', {'floor': f.floor})),
                        subtitle: Text('${stageLabel(f.stage)} · ${fmtDate(DateTime.parse(f.asOf))}'),
                        trailing: Text('${f.pct}%', style: theme.textTheme.titleMedium),
                        onTap: canWrite ? () => _update(f) : null,
                      ),
                  ]),
                ),
              ],
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                    tr('Progress is as recorded on site. The architect certifies the stage of completion for RERA.'),
                    style: theme.textTheme.bodySmall),
              ),
            ],
          );
        },
      ),
    );
  }
}
