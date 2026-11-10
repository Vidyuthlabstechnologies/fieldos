/// The material check on the phone: should have used against used, per
/// material, for the work approved on a site, and the company's norms.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/procurement/material_check.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

enum _Span { all, thisMonth, lastMonth }

String unitLabel(String u) => switch (u) {
      'bag' => tr('bags'),
      'cum' => tr('cu m'),
      'sqm' => tr('sq m'),
      'nos' => tr('nos'),
      'kg' => tr('kg'),
      _ => u,
    };

String materialLabel(String m) => switch (m) {
      'Cement' => tr('Cement'),
      'Sand' => tr('Sand'),
      'Aggregate' => tr('Aggregate'),
      'Bricks' => tr('Bricks'),
      'Steel' => tr('Steel'),
      _ => m,
    };

String normLabel(String key, String label) => switch (key) {
      'pcc' => tr('PCC 1:4:8'),
      'rcc' => tr('RCC M20 (1:1.5:3)'),
      'brickwork' => tr('Brickwork in 1:6 mortar'),
      'plaster' => tr('Plastering 12 mm, 1:6'),
      'steel' => tr('Reinforcement steel'),
      _ => label,
    };

class MaterialCheckScreen extends ConsumerStatefulWidget {
  const MaterialCheckScreen({super.key, required this.project});
  final Project project;

  @override
  ConsumerState<MaterialCheckScreen> createState() => _MaterialCheckScreenState();
}

class _MaterialCheckScreenState extends ConsumerState<MaterialCheckScreen> {
  _Span _span = _Span.all;
  Future<MaterialCheck>? _check;

  ({DateTime? from, DateTime? to}) get _range {
    final now = DateTime.now();
    return switch (_span) {
      _Span.all => (from: null, to: null),
      _Span.thisMonth => (from: DateTime(now.year, now.month, 1), to: now),
      _Span.lastMonth => (from: DateTime(now.year, now.month - 1, 1), to: DateTime(now.year, now.month, 0)),
    };
  }

  void _load() {
    final r = _range;
    _check = loadMaterialCheck(ref.read(appDatabaseProvider), widget.project, from: r.from, to: r.to);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _openNorms() async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MaterialNormsScreen(companyId: widget.project.companyId)));
    if (mounted) setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canEdit = Roles.canApprove(ref.watch(sessionProvider).role);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Material check')),
        actions: [
          if (canEdit)
            IconButton(tooltip: tr('Material norms'), icon: const Icon(Icons.tune), onPressed: _openNorms),
        ],
      ),
      body: FutureBuilder<MaterialCheck>(
        future: _check,
        builder: (context, snap) {
          if (snap.hasError) return ErrorState(error: snap.error!, stack: snap.stackTrace, onRetry: () => setState(_load));
          final c = snap.data;
          if (c == null) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              Wrap(spacing: 8, children: [
                for (final (s, l) in [
                  (_Span.all, tr('All work')),
                  (_Span.thisMonth, tr('This month')),
                  (_Span.lastMonth, tr('Last month')),
                ])
                  ChoiceChip(
                    label: Text(l),
                    selected: _span == s,
                    onSelected: (_) => setState(() {
                      _span = s;
                      _load();
                    }),
                  ),
              ]),
              const SizedBox(height: 8),
              if (c.checkedWork == 0 && c.lines.every((l) => l.used == 0))
                EmptyState(
                  compact: true,
                  icon: Icons.fact_check_outlined,
                  title: tr('Nothing to check yet'),
                  message: tr(
                      'Approve work measurements (concrete, brickwork, plaster, steel) and record material used on site. The check then shows what should have been used against what was.'),
                )
              else ...[
                Card(
                  child: ListTile(
                    leading: Icon(c.flagged.isEmpty ? Icons.check_circle_outline : Icons.warning_amber_outlined,
                        color: c.flagged.isEmpty ? toneColor(context, PillTone.ok) : toneColor(context, PillTone.danger)),
                    title: Text(c.flagged.isEmpty
                        ? tr('Usage matches the work done')
                        : trf('{n} materials off by more than {pct}%', {'n': c.flagged.length, 'pct': fmtQty(c.tolerancePct)})),
                    subtitle: Text(trf('{n} approved measurements checked', {'n': c.checkedWork})),
                  ),
                ),
                for (final l in c.lines) _LineCard(line: l, tolerancePct: c.tolerancePct),
                if (c.notChecked.isNotEmpty)
                  ExpansionTile(
                    title: Text(trf('{n} measurements not checked', {'n': c.notChecked.length})),
                    subtitle: Text(tr('No norm matches their description or unit'), style: theme.textTheme.bodySmall),
                    children: [
                      for (final m in c.notChecked.take(30))
                        ListTile(dense: true, title: Text(m.description), trailing: Text('${fmtQty(m.qty)} ${m.unit}')),
                    ],
                  ),
              ],
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                    tr('Should have used = approved work × the norms. The norms are starting figures for nominal mixes; set your own in Material norms.'),
                    style: theme.textTheme.bodySmall),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({required this.line, required this.tolerancePct});
  final MaterialCheckLine line;
  final double tolerancePct;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final u = unitLabel(line.unit);
    final p = line.gapPct;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(materialLabel(line.name), style: theme.textTheme.titleSmall)),
            switch (line.status(tolerancePct)) {
              CheckStatus.over => StatusPill(
                  p == null ? tr('Used, no work for it') : trf('{pct}% over', {'pct': fmtQty(p.round())}),
                  tone: PillTone.danger),
              CheckStatus.under => StatusPill(trf('{pct}% under', {'pct': fmtQty(-p!.round())}), tone: PillTone.warn),
              CheckStatus.ok => StatusPill(tr('Within norm'), tone: PillTone.ok),
            },
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _Figure(tr('Should have used'), '${fmtQty(_round(line.shouldHaveUsed))} $u')),
            Expanded(child: _Figure(tr('Used'), '${fmtQty(_round(line.used))} $u')),
            Expanded(child: _Figure(tr('Difference'), '${line.gap >= 0 ? '+' : ''}${fmtQty(_round(line.gap))} $u')),
          ]),
          if (line.status(tolerancePct) == CheckStatus.under)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(tr('Less than the work needs: usage may not be recorded.'), style: theme.textTheme.bodySmall),
            ),
          if (line.otherUnits > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(trf('{qty} more recorded in other units, not counted.', {'qty': fmtQty(_round(line.otherUnits))}),
                  style: theme.textTheme.bodySmall),
            ),
        ]),
      ),
    );
  }
}

double _round(double v) => (v * 100).roundToDouble() / 100;

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: t.bodySmall),
      Text(value, style: t.titleSmall),
    ]);
  }
}

/// The company's norms: what each unit of work takes, and how far over is
/// flagged. Kept on this phone.
class MaterialNormsScreen extends ConsumerStatefulWidget {
  const MaterialNormsScreen({super.key, required this.companyId});
  final String companyId;

  @override
  ConsumerState<MaterialNormsScreen> createState() => _MaterialNormsScreenState();
}

class _MaterialNormsScreenState extends ConsumerState<MaterialNormsScreen> {
  MaterialNormSettings? _s;

  @override
  void initState() {
    super.initState();
    loadMaterialNorms(ref.read(appDatabaseProvider), widget.companyId).then((s) {
      if (mounted) setState(() => _s = s);
    });
  }

  Future<void> _save(MaterialNormSettings s) async {
    await saveMaterialNorms(ref.read(appDatabaseProvider), widget.companyId, s);
    if (mounted) setState(() => _s = s);
  }

  Future<void> _edit(int i) async {
    final s = _s!;
    final n = s.norms[i];
    final cs = [for (final m in n.materials) TextEditingController(text: fmtQty(m.perUnit))];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(normLabel(n.key, n.label)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(trf('For each {unit} of work', {'unit': unitLabel(n.workUnit)})),
          for (var j = 0; j < n.materials.length; j++)
            TextField(
              controller: cs[j],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: materialLabel(n.materials[j].name), suffixText: unitLabel(n.materials[j].unit)),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
        ],
      ),
    );
    if (ok != true) return;
    final vs = [for (final c in cs) double.tryParse(c.text.trim().replaceAll(',', ''))];
    if (vs.any((v) => v == null || v < 0 || v > 100000)) {
      if (mounted) showSnack(context, tr('Enter a number for each material'), error: true);
      return;
    }
    final norms = [...s.norms];
    norms[i] = n.withMaterials([for (var j = 0; j < n.materials.length; j++) n.materials[j].withPerUnit(vs[j]!)]);
    await _save(MaterialNormSettings(norms: norms, tolerancePct: s.tolerancePct));
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Material norms'))),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
              Text(
                  tr('Starting figures for nominal mixes with a 50 kg cement bag. Change them to your own mix and wastage.'),
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              for (var i = 0; i < s.norms.length; i++)
                Card(
                  child: ListTile(
                    title: Text(normLabel(s.norms[i].key, s.norms[i].label)),
                    subtitle: Text([
                      for (final m in s.norms[i].materials)
                        '${materialLabel(m.name)} ${fmtQty(m.perUnit)} ${unitLabel(m.unit)}'
                    ].join(' · ')),
                    trailing: Text('/ ${unitLabel(s.norms[i].workUnit)}'),
                    onTap: () => _edit(i),
                  ),
                ),
              ListTile(
                title: Text(tr('Flag when more than this % over')),
                trailing: DropdownButton<double>(
                  value: s.tolerancePct,
                  items: [
                    for (final v in {2.0, 3.0, 5.0, 7.0, 10.0, 15.0, s.tolerancePct})
                      DropdownMenuItem(value: v, child: Text('${fmtQty(v)}%')),
                  ],
                  onChanged: (v) => v == null ? null : _save(MaterialNormSettings(norms: s.norms, tolerancePct: v)),
                ),
              ),
              TextButton(
                onPressed: () => _save(const MaterialNormSettings()),
                child: Text(tr('Go back to the starting figures')),
              ),
            ]),
    );
  }
}
