/// Estimation / BOQ entry: Estimations -> Cost Heads -> Entries (Measurements or Steel).
/// Uses the existing Decimal-precise calculation engine from estimation_calc.dart.
library;

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/estimation/estimation_calc.dart';

class EstimationView extends ConsumerStatefulWidget {
  const EstimationView({
    super.key,
    required this.projectId,
    required this.userId,
  });
  final String projectId;
  final String userId;

  @override
  ConsumerState<EstimationView> createState() => _EstimationViewState();
}

class _EstimationViewState extends ConsumerState<EstimationView> {
  @override
  Widget build(BuildContext context) {
    final estimationsList = ref.watch(estimationsProvider(widget.projectId));
    return Column(
      children: [
        _sectionHeader(context, 'Estimations', () => _addEstimation(context, ref)),
        Expanded(
          child: estimationsList.when(
            data: (rows) => rows.isEmpty
                ? const Center(child: Text('No estimations yet.'))
                : ListView(
                    children: [
                      for (final e in rows)
                        _EstimationTile(
                          estimation: e,
                          projectId: widget.projectId,
                          userId: widget.userId,
                        ),
                    ],
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => ErrorState(error: e, stack: st),
          ),
        ),
      ],
    );
  }

  Future<void> _addEstimation(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final profitPercent = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New estimation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            TextField(
              controller: profitPercent,
              decoration: const InputDecoration(labelText: 'Contractor profit % (optional)'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Create')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !context.mounted) return;
    await ref.read(appDatabaseProvider).estimationDao.create(EstimationsCompanion.insert(
          id: const Uuid().v4(),
          projectId: widget.projectId,
          name: name.text.trim(),
          contractorProfitPercent: Value(double.tryParse(profitPercent.text)),
          createdBy: widget.userId,
          status: const Value('draft'),
        ));
    ref.invalidate(estimationsProvider(widget.projectId));
  }
}

Widget _sectionHeader(BuildContext context, String title, VoidCallback onAdd) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          IconButton(icon: const Icon(Icons.add), tooltip: 'Add', onPressed: onAdd),
        ],
      ),
    );

class _EstimationTile extends ConsumerWidget {
  const _EstimationTile({
    required this.estimation,
    required this.projectId,
    required this.userId,
  });
  final Estimation estimation;
  final String projectId;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        title: Text(estimation.name),
        subtitle: Text('Status: ${estimation.status}${estimation.contractorProfitPercent != null ? '  •  Profit: ${estimation.contractorProfitPercent!.toStringAsFixed(1)}%' : ''}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CostHeadsScreen(
              estimation: estimation,
              projectId: projectId,
              userId: userId,
            ),
          ),
        ),
      ),
    );
  }
}

/// Screen showing cost heads for an estimation.
class CostHeadsScreen extends ConsumerStatefulWidget {
  const CostHeadsScreen({
    super.key,
    required this.estimation,
    required this.projectId,
    required this.userId,
  });
  final Estimation estimation;
  final String projectId;
  final String userId;

  @override
  ConsumerState<CostHeadsScreen> createState() => _CostHeadsScreenState();
}

class _CostHeadsScreenState extends ConsumerState<CostHeadsScreen> {
  @override
  Widget build(BuildContext context) {
    final costHeadsList = ref.watch(costHeadsProvider(widget.estimation.id));
    return Scaffold(
      appBar: AppBar(title: Text(widget.estimation.name)),
      body: Column(
        children: [
          _sectionHeader(context, 'Cost heads', () => _addCostHead(context, ref)),
          Expanded(
            child: costHeadsList.when(
              data: (rows) => rows.isEmpty
                  ? const Center(child: Text('No cost heads yet.'))
                  : ListView(
                      children: [
                        for (final ch in rows)
                          _CostHeadTile(
                            costHead: ch,
                            estimationId: widget.estimation.id,
                            projectId: widget.projectId,
                          ),
                      ],
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => ErrorState(error: e, stack: st),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addCostHead(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final calculationType = TextEditingController(text: calcVolume);
    final rawUnit = TextEditingController();
    final billingUnit = TextEditingController();
    final conversionFactor = TextEditingController(text: '1');
    final ratePerUnit = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add cost head'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            DropdownButtonFormField<String>(
              initialValue: calcVolume,
              decoration: const InputDecoration(labelText: 'Calculation type'),
              items: const [calcVolume, calcArea, calcSteelWeight, calcCount]
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => calculationType.text = v ?? calcVolume,
            ),
            TextField(controller: rawUnit, decoration: const InputDecoration(labelText: 'Raw unit (e.g. cft, m)')),
            TextField(controller: billingUnit, decoration: const InputDecoration(labelText: 'Billing unit (e.g. cft, sqm)')),
            TextField(
              controller: conversionFactor,
              decoration: const InputDecoration(labelText: 'Conversion factor'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: ratePerUnit,
              decoration: const InputDecoration(labelText: 'Rate per billing unit (optional)'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !context.mounted) return;
    await ref.read(appDatabaseProvider).estimationDao.addCostHead(CostHeadsCompanion.insert(
          id: const Uuid().v4(),
          estimationId: widget.estimation.id,
          name: name.text.trim(),
          calculationType: calculationType.text,
          rawUnit: rawUnit.text.trim(),
          billingUnit: billingUnit.text.trim(),
          conversionFactor: Value(double.tryParse(conversionFactor.text) ?? 1),
          ratePerUnit: Value(double.tryParse(ratePerUnit.text)),
        ));
    ref.invalidate(costHeadsProvider(widget.estimation.id));
  }
}

class _CostHeadTile extends ConsumerWidget {
  const _CostHeadTile({
    required this.costHead,
    required this.estimationId,
    required this.projectId,
  });
  final CostHead costHead;
  final String estimationId;
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        title: Text(costHead.name),
        subtitle: Text('${costHead.calculationType} · ${costHead.rawUnit} -> ${costHead.billingUnit} (×${costHead.conversionFactor})${costHead.ratePerUnit != null ? '  •  ${rupees(costHead.ratePerUnit!, paise: true)}/${costHead.billingUnit}' : ''}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EntriesScreen(
              costHead: costHead,
              estimationId: estimationId,
              projectId: projectId,
            ),
          ),
        ),
      ),
    );
  }
}

/// Screen showing entries (measurements or steel) for a cost head.
class EntriesScreen extends ConsumerStatefulWidget {
  const EntriesScreen({
    super.key,
    required this.costHead,
    required this.estimationId,
    required this.projectId,
  });
  final CostHead costHead;
  final String estimationId;
  final String projectId;

  @override
  ConsumerState<EntriesScreen> createState() => _EntriesScreenState();
}

class _EntriesScreenState extends ConsumerState<EntriesScreen> {
  late final bool isSteel;

  @override
  void initState() {
    super.initState();
    isSteel = widget.costHead.calculationType == calcSteelWeight;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.costHead.name)),
      body: Column(
        children: [
          _sectionHeader(context, isSteel ? 'Steel entries' : 'Measurement entries', () => _addEntry(context, ref)),
          Expanded(
            child: isSteel
                ? ref.watch(steelEntriesProvider(widget.costHead.id)).when(
                      data: (rows) => rows.isEmpty
                          ? const Center(child: Text('No entries yet.'))
                          : ListView(
                              children: [
                                for (final e in rows)
                                  _SteelEntryTile(
                                    entry: e,
                                    costHeadId: widget.costHead.id,
                                    costHead: widget.costHead,
                                  ),
                              ],
                            ),
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (e, st) => ErrorState(error: e, stack: st),
                    )
                : ref.watch(measurementEntriesProvider(widget.costHead.id)).when(
                      data: (rows) => rows.isEmpty
                          ? const Center(child: Text('No entries yet.'))
                          : ListView(
                              children: [
                                for (final e in rows)
                                  _MeasurementEntryTile(
                                    entry: e,
                                    costHeadId: widget.costHead.id,
                                    costHead: widget.costHead,
                                  ),
                              ],
                            ),
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (e, st) => ErrorState(error: e, stack: st),
                    ),
          ),
          _TotalSection(
            costHead: widget.costHead,
            estimationId: widget.estimationId,
            projectId: widget.projectId,
          ),
        ],
      ),
    );
  }

  Future<void> _addEntry(BuildContext context, WidgetRef ref) async {
    if (isSteel) {
      await _addSteelEntry(context, ref);
    } else {
      await _addMeasurementEntry(context, ref);
    }
  }

  Future<void> _addMeasurementEntry(BuildContext context, WidgetRef ref) async {
    final description = TextEditingController();
    final length = TextEditingController();
    final width = TextEditingController();
    final depth = TextEditingController();
    final nos = TextEditingController(text: '1');
    final isDeduction = ValueNotifier<bool>(false);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add measurement'),
        content: StatefulBuilder(
          builder: (ctx, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: description, decoration: const InputDecoration(labelText: 'Description')),
              TextField(controller: length, decoration: const InputDecoration(labelText: 'Length'), keyboardType: TextInputType.number),
              TextField(controller: width, decoration: const InputDecoration(labelText: 'Width'), keyboardType: TextInputType.number),
              TextField(controller: depth, decoration: const InputDecoration(labelText: 'Depth'), keyboardType: TextInputType.number),
              TextField(controller: nos, decoration: const InputDecoration(labelText: 'Nos'), keyboardType: TextInputType.number),
              CheckboxListTile(
                value: isDeduction.value,
                title: const Text('Deduction'),
                onChanged: (v) => setDialogState(() => isDeduction.value = v ?? false),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || description.text.trim().isEmpty || !context.mounted) return;
    await ref.read(appDatabaseProvider).estimationDao.addMeasurement(MeasurementEntriesCompanion.insert(
          id: const Uuid().v4(),
          costHeadId: widget.costHead.id,
          description: description.text.trim(),
          length: Value(double.tryParse(length.text)),
          width: Value(double.tryParse(width.text)),
          depth: Value(double.tryParse(depth.text)),
          nos: Value(double.tryParse(nos.text) ?? 1),
          isDeduction: Value(isDeduction.value),
        ));
    ref.invalidate(measurementEntriesProvider(widget.costHead.id));
  }

  Future<void> _addSteelEntry(BuildContext context, WidgetRef ref) async {
    final description = TextEditingController();
    final barDiaMm = TextEditingController();
    final nos = TextEditingController();
    final lengthFt = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add steel entry'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: description, decoration: const InputDecoration(labelText: 'Description')),
            TextField(controller: barDiaMm, decoration: const InputDecoration(labelText: 'Bar dia (mm)'), keyboardType: TextInputType.number),
            TextField(controller: nos, decoration: const InputDecoration(labelText: 'Nos'), keyboardType: TextInputType.number),
            TextField(controller: lengthFt, decoration: const InputDecoration(labelText: 'Length (ft)'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || description.text.trim().isEmpty || !context.mounted) return;
    await ref.read(appDatabaseProvider).estimationDao.addSteel(SteelEntriesCompanion.insert(
          id: const Uuid().v4(),
          costHeadId: widget.costHead.id,
          description: description.text.trim(),
          barDiaMm: double.tryParse(barDiaMm.text) ?? 0,
          nos: double.tryParse(nos.text) ?? 0,
          lengthFt: double.tryParse(lengthFt.text) ?? 0,
        ));
    ref.invalidate(steelEntriesProvider(widget.costHead.id));
  }
}

class _MeasurementEntryTile extends ConsumerWidget {
  const _MeasurementEntryTile({
    required this.entry,
    required this.costHeadId,
    required this.costHead,
  });
  final MeasurementEntry entry;
  final String costHeadId;
  final CostHead costHead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final qty = measurementEntryQuantity(
      costHead.calculationType,
      length: entry.length == null ? null : Decimal.parse(entry.length.toString()),
      width: entry.width == null ? null : Decimal.parse(entry.width.toString()),
      depth: entry.depth == null ? null : Decimal.parse(entry.depth.toString()),
      nos: Decimal.parse(entry.nos.toString()),
      isDeduction: entry.isDeduction,
    );
    return Card(
      child: ListTile(
        title: Text(entry.description),
        subtitle: Text([
          if (entry.length != null) 'L: ${entry.length}',
          if (entry.width != null) 'W: ${entry.width}',
          if (entry.depth != null) 'D: ${entry.depth}',
          'Nos: ${entry.nos}',
          if (entry.isDeduction) 'DEDUCTION',
        ].join('  ·  ')),
        trailing: Text(
          '${qty.toStringAsFixed(3)} ${entry.isDeduction ? '-' : '+'}',
          style: TextStyle(
              color: toneColor(context, entry.isDeduction ? PillTone.danger : PillTone.ok), fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _SteelEntryTile extends ConsumerWidget {
  const _SteelEntryTile({
    required this.entry,
    required this.costHeadId,
    required this.costHead,
  });
  final SteelEntry entry;
  final String costHeadId;
  final CostHead costHead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weight = steelEntryWeightKg(
      Decimal.parse(entry.barDiaMm.toString()),
      Decimal.parse(entry.nos.toString()),
      Decimal.parse(entry.lengthFt.toString()),
    );
    return Card(
      child: ListTile(
        title: Text(entry.description),
        subtitle: Text('Ø${entry.barDiaMm}mm · ${entry.nos} nos · ${entry.lengthFt} ft'),
        trailing: Text('${weight.toStringAsFixed(2)} kg', style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// Shows running total for the cost head using the estimation engine.
class _TotalSection extends ConsumerWidget {
  const _TotalSection({
    required this.costHead,
    required this.estimationId,
    required this.projectId,
  });
  final CostHead costHead;
  final String estimationId;
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final measurements = ref.watch(measurementEntriesProvider(costHead.id));
    final steel = ref.watch(steelEntriesProvider(costHead.id));

    return measurements.when(
      data: (meas) => steel.when(
        data: (stl) {
          final calcHead = CalcCostHead(
            id: costHead.id,
            name: costHead.name,
            calculationType: costHead.calculationType,
            billingUnit: costHead.billingUnit,
            conversionFactor: Decimal.parse(costHead.conversionFactor.toString()),
            ratePerUnit: costHead.ratePerUnit == null ? null : Decimal.parse(costHead.ratePerUnit.toString()),
          );
          final calcMeas = meas
              .map((m) => CalcMeasurement(
                    length: m.length == null ? null : Decimal.parse(m.length.toString()),
                    width: m.width == null ? null : Decimal.parse(m.width.toString()),
                    depth: m.depth == null ? null : Decimal.parse(m.depth.toString()),
                    nos: Decimal.parse(m.nos.toString()),
                    isDeduction: m.isDeduction,
                  ))
              .toList();
          final calcSteel = stl
              .map((s) => CalcSteel(
                    barDiaMm: Decimal.parse(s.barDiaMm.toString()),
                    nos: Decimal.parse(s.nos.toString()),
                    lengthFt: Decimal.parse(s.lengthFt.toString()),
                  ))
              .toList();

          final rawQty = costHeadRawQuantity(calcHead, measurements: calcMeas, steel: calcSteel);
          final billingQty = costHeadBillingQuantity(calcHead, rawQty);
          final amount = costHeadAmount(calcHead, billingQty);

          return Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Raw quantity: ${rawQty.toStringAsFixed(3)} ${costHead.rawUnit}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('Billing quantity: ${billingQty.toStringAsFixed(3)} ${costHead.billingUnit}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (amount != null)
                  Text('Amount: ${rupees(amount.toDouble(), paise: true)}',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: toneColor(context, PillTone.ok)))
                else
                  Text('Amount: not priced yet (add a rate to this item)',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => ErrorState(error: e, stack: st),
    );
  }
}