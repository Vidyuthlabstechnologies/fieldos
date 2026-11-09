/// Material rate history and the site unit converter.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/procurement/purchase_tools.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

Future<void> openMaterialRates(BuildContext context, String projectId, String companyId) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => MaterialRatesScreen(projectId: projectId, companyId: companyId)));

Future<void> openUnitConverter(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UnitConverterScreen()));

/// What each material has cost per unit, delivery by delivery, so a jump
/// in the cement or steel rate is seen before the next order.
class MaterialRatesScreen extends ConsumerWidget {
  const MaterialRatesScreen({super.key, required this.projectId, required this.companyId});
  final String projectId;
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipts = ref.watch(receiptsProvider(projectId));
    final suppliers = ref.watch(suppliersProvider(companyId)).value ?? const <Supplier>[];
    String? supplierName(String? id) => suppliers.where((s) => s.id == id).firstOrNull?.name;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Material rates'))),
      body: receipts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
        data: (rows) {
          final rates = materialRates(rows);
          if (rates.isEmpty) {
            return EmptyState(
              icon: Icons.trending_up,
              title: tr('No rates yet'),
              message: tr('Rates show up once deliveries are saved with a quantity and an amount.'),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              for (final r in rates)
                ExpansionTile(
                  title: Text(r.name),
                  subtitle: Text(trf('{rate} per {unit} · {n} deliveries', {
                    'rate': rupees(r.latest, paise: true),
                    'unit': r.unit ?? tr('unit'),
                    'n': r.points.length,
                  })),
                  trailing: _Change(r.changePct),
                  children: [
                    if (r.points.length > 1)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                        child: Text(
                          trf('Lowest {low}, highest {high}',
                              {'low': rupees(r.lowest, paise: true), 'high': rupees(r.highest, paise: true)}),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    for (final p in r.points.reversed)
                      ListTile(
                        dense: true,
                        title: Text(fmtDate(p.on, short: true)),
                        subtitle: supplierName(p.supplierId) == null ? null : Text(supplierName(p.supplierId)!),
                        trailing: Text(rupees(p.rate, paise: true)),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Change extends StatelessWidget {
  const _Change(this.pct);
  final double? pct;

  @override
  Widget build(BuildContext context) {
    final p = pct;
    if (p == null || p.abs() < 0.5) return const SizedBox.shrink();
    final up = p > 0;
    return StatusPill('${up ? '▲' : '▼'} ${p.abs().toStringAsFixed(0)}%', tone: up ? PillTone.danger : PillTone.ok);
  }
}

/// Bags, brass, running feet and guntha to the units on a bill or a
/// drawing, and steel weight by bar size.
class UnitConverterScreen extends StatefulWidget {
  const UnitConverterScreen({super.key});

  @override
  State<UnitConverterScreen> createState() => _UnitConverterScreenState();
}

class _UnitConverterScreenState extends State<UnitConverterScreen> {
  var _group = unitGroups.first;
  late var _from = _group.units[1];
  late var _to = _group.units[0];
  final _value = TextEditingController(text: '1');
  final _bar = TextEditingController(text: '12');
  final _barLength = TextEditingController(text: '12');

  @override
  void dispose() {
    _value.dispose();
    _bar.dispose();
    _barLength.dispose();
    super.dispose();
  }

  void _pickGroup(UnitGroup g) => setState(() {
        _group = g;
        _from = g.units[1];
        _to = g.units[0];
      });

  static String _fmt(double v) {
    if (v == 0) return '0';
    final a = v.abs();
    final digits = a >= 1000 ? 0 : a >= 1 ? 3 : 5;
    var s = v.toStringAsFixed(digits);
    if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = double.tryParse(_value.text.trim());
    final result = v == null ? null : convertUnits(v, _from, _to);
    final d = double.tryParse(_bar.text.trim());
    final len = double.tryParse(_barLength.text.trim());
    final kgPerM = d == null || d <= 0 ? null : steelKgPerMetre(d);
    DropdownButtonFormField<SiteUnit> unitPicker(String label, SiteUnit value, ValueChanged<SiteUnit> onPick) =>
        DropdownButtonFormField<SiteUnit>(
          key: ValueKey('${_group.label}-$label'),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: tr(label)),
          items: [for (final u in _group.units) DropdownMenuItem(value: u, child: Text(tr(u.label)))],
          onChanged: (u) => u == null ? null : setState(() => onPick(u)),
        );
    return Scaffold(
      appBar: AppBar(title: Text(tr('Unit converter'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final g in unitGroups)
              ChoiceChip(label: Text(tr(g.label)), selected: identical(g, _group), onSelected: (_) => _pickGroup(g)),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _value,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr('Value')),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: unitPicker('From', _from, (u) => _from = u)),
            IconButton(
              tooltip: tr('Swap'),
              icon: const Icon(Icons.swap_horiz),
              onPressed: () => setState(() {
                final t = _from;
                _from = _to;
                _to = t;
              }),
            ),
            Expanded(child: unitPicker('To', _to, (u) => _to = u)),
          ]),
          const SizedBox(height: 16),
          Text(
            result == null ? '–' : '${_fmt(v!)} ${tr(_from.label)} = ${_fmt(result)} ${tr(_to.label)}',
            style: theme.textTheme.titleLarge,
          ),
          const SectionHeader('Steel weight'),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _bar,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: tr('Bar size (mm)')),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _barLength,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: tr('Length (m)')),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          if (kgPerM != null) ...[
            Text(trf('{kg} kg per metre', {'kg': _fmt(kgPerM)}), style: theme.textTheme.titleMedium),
            if (len != null && len > 0)
              Text(trf('{kg} kg for {m} m', {'kg': _fmt(kgPerM * len), 'm': _fmt(len)}), style: theme.textTheme.bodyLarge),
            const SizedBox(height: 4),
            Text(tr('By the site rule: weight per metre = d × d ÷ 162.'), style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
