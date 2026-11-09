/// Every machine taken on hire for the site: from whom, how many days,
/// what it has cost so far, and which ones are late to go back.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/equipment/equipment_screen.dart' show hireLine;
import 'package:fieldos_mobile/features/equipment/hire_register.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

final _siteLogsProvider = FutureProvider.autoDispose.family<List<EquipmentLog>, String>(
    (ref, projectId) => ref.watch(appDatabaseProvider).equipmentDao.logsForProject(projectId));

class HireRegisterScreen extends ConsumerWidget {
  const HireRegisterScreen({super.key, required this.projectId, this.now});
  final String projectId;

  /// For tests.
  final DateTime? now;

  String _shareText(List<EquipmentData> rows, List<EquipmentLog> logs, DateTime now) {
    final b = StringBuffer('Hire register\n\n');
    for (final e in rows) {
      final c = hireCharge(e, logs, now);
      b.write('${e.name}: ${hireLine(e, now)}');
      b.write(c.byHour
          ? ' · ${c.hours.toStringAsFixed(1)} h = ${rupees(c.amount, paise: true)}\n'
          : (c.amount > 0 ? ' · ${rupees(c.amount, paise: true)}\n' : '\n'));
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final at = now ?? DateTime.now();
    final equipment = ref.watch(equipmentProvider(projectId));
    final logs = ref.watch(_siteLogsProvider(projectId));
    final ready = equipment.hasValue && logs.hasValue;
    final rows = ready ? hireRegister(equipment.value!, at) : const <EquipmentData>[];
    final total = ready ? rows.fold<double>(0, (s, e) => s + hireCharge(e, logs.value!, at).amount) : 0.0;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Hire register')), actions: [
        if (rows.isNotEmpty)
          IconButton(
            tooltip: tr('Share on WhatsApp'),
            icon: const Icon(Icons.share),
            onPressed: () => SharePlus.instance.share(ShareParams(text: _shareText(rows, logs.value!, at))),
          ),
      ]),
      body: !ready
          ? const Center(child: CircularProgressIndicator())
          : rows.isEmpty
              ? EmptyState(
                  icon: Icons.handshake_outlined,
                  title: tr('Nothing on hire'),
                  message: tr('When you add a machine, switch on "Hired from someone" to keep it here.'),
                )
              : ListView(padding: const EdgeInsets.all(12), children: [
                  Text(
                    key: const Key('hire-total'),
                    trf('Hire so far: {amount}', {'amount': rupees(total, paise: true)}),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final e in rows) _HireTile(equipment: e, charge: hireCharge(e, logs.value!, at), now: at, projectId: projectId),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      tr('Machines with a rate per hour are charged for the hours logged as worked; others by the day, from the day they came.'),
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ]),
    );
  }
}

class _HireTile extends ConsumerWidget {
  const _HireTile({required this.equipment, required this.charge, required this.now, required this.projectId});
  final EquipmentData equipment;
  final HireCharge charge;
  final DateTime now;
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = equipment;
    final state = hireState(e, now);
    final (label, tone) = switch (state) {
      HireState.overdue => (tr('Late'), PillTone.danger),
      HireState.dueSoon => (tr('Due soon'), PillTone.warn),
      HireState.onHire => (tr('On hire'), PillTone.ok),
      HireState.returned => (tr('Returned'), PillTone.neutral),
    };
    return Card(
      key: Key('hire-${e.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(e.name, style: Theme.of(context).textTheme.titleSmall)),
            StatusPill(label, tone: tone),
          ]),
          const SizedBox(height: 4),
          Text(hireLine(e, now), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: Text(
                charge.byHour
                    ? trf('{hours} h × {rate} = {amount}', {
                        'hours': charge.hours.toStringAsFixed(1),
                        'rate': rupees(e.hourlyRate!, paise: true),
                        'amount': rupees(charge.amount, paise: true),
                      })
                    : e.dailyRate == null
                        ? tr('No rate set')
                        : trf('{days} days × {rate} = {amount}', {
                            'days': charge.days,
                            'rate': rupees(e.dailyRate!, paise: true),
                            'amount': rupees(charge.amount, paise: true),
                          }),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (e.returnedOn == null)
              TextButton(
                key: Key('return-${e.id}'),
                onPressed: () async {
                  await ref.read(appDatabaseProvider).equipmentDao.markReturned(e.id, now);
                  ref.invalidate(equipmentProvider(projectId));
                  if (context.mounted) showSnack(context, 'Marked as returned.');
                },
                child: Text(tr('Returned')),
              ),
          ]),
        ]),
      ),
    );
  }
}
