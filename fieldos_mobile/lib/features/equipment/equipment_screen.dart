/// Equipment tracking: list, add, status, and usage/maintenance logs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/equipment/hire_register.dart';
import 'package:fieldos_mobile/features/equipment/hire_register_screen.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/l10n/language.dart';

class EquipmentView extends ConsumerStatefulWidget {
  const EquipmentView({super.key, required this.projectId, required this.userId});
  final String projectId;
  final String userId;

  @override
  ConsumerState<EquipmentView> createState() => _EquipmentViewState();
}

class _EquipmentViewState extends ConsumerState<EquipmentView> {
  @override
  Widget build(BuildContext context) {
    final equipmentList = ref.watch(equipmentProvider(widget.projectId));
    return Column(
      children: [
        _sectionHeader(context, 'Equipment', () => _addEquipment(context, ref)),
        if (equipmentList.valueOrNull?.any(isHired) ?? false)
          _HireSummary(equipment: equipmentList.value!, projectId: widget.projectId),
        Expanded(
          child: equipmentList.when(
            data: (rows) => rows.isEmpty
                ? Center(child: Text(tr('No equipment yet.')))
                : ListView(
                    children: [
                      for (final e in rows)
                        _EquipmentTile(equipment: e, projectId: widget.projectId, userId: widget.userId),
                    ],
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => ErrorState(error: e, stack: st),
          ),
        ),
      ],
    );
  }

  Future<void> _addEquipment(BuildContext context, WidgetRef ref) =>
      editEquipment(context, ref, projectId: widget.projectId);
}

/// Adds a machine, or changes [existing]: its rates, and for a hired one
/// who it came from, since when and when it goes back.
Future<void> editEquipment(BuildContext context, WidgetRef ref,
    {required String projectId, EquipmentData? existing}) async {
  final e = existing;
  final name = TextEditingController(text: e?.name ?? '');
  final equipmentType = TextEditingController(text: e?.equipmentType ?? '');
  final model = TextEditingController(text: e?.model ?? '');
  final registrationNumber = TextEditingController(text: e?.registrationNumber ?? '');
  final dailyRate = TextEditingController(text: _plain(e?.dailyRate));
  final hourlyRate = TextEditingController(text: _plain(e?.hourlyRate));
  final hiredFrom = TextEditingController(text: e?.hiredFrom ?? '');
  var hired = e?.ownership == 'hired';
  final today = DateTime.now();
  var hiredOn = e?.hiredOn ?? DateTime(today.year, today.month, today.day);
  DateTime? returnDue = e?.returnDueOn;
  String? nameError;

  Future<DateTime?> pick(BuildContext ctx, DateTime initial, {DateTime? first}) => showDatePicker(
      context: ctx, initialDate: initial, firstDate: first ?? DateTime(2020), lastDate: DateTime(today.year + 3));

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(e == null ? tr('Add equipment') : tr('Edit equipment')),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('equipment-name'),
              controller: name,
              autofocus: e == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: tr('Name'), hintText: tr('e.g. JCB 3DX'), errorText: nameError),
            ),
            TextField(
              controller: equipmentType,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: tr('Type (optional)'), hintText: tr('e.g. Excavator')),
            ),
            TextField(
              controller: model,
              decoration: InputDecoration(labelText: tr('Model (optional)')),
            ),
            TextField(
              controller: registrationNumber,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: tr('Registration number (optional)')),
            ),
            TextField(
              key: const Key('equipment-hourly-rate'),
              controller: hourlyRate,
              decoration: InputDecoration(labelText: tr('Rate per hour (optional)'), prefixText: '₹ '),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            TextField(
              controller: dailyRate,
              decoration: InputDecoration(labelText: tr('Daily rate (optional)'), prefixText: '₹ '),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            SwitchListTile(
              key: const Key('equipment-hired'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Hired from someone')),
              value: hired,
              onChanged: (v) => set(() => hired = v),
            ),
            if (hired) ...[
              TextField(
                key: const Key('equipment-hired-from'),
                controller: hiredFrom,
                maxLength: 120,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: tr('Hired from'), counterText: ''),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(tr('On site since')),
                subtitle: Text(fmtDate(hiredOn)),
                onTap: () async {
                  final d = await pick(ctx, hiredOn);
                  if (d == null) return;
                  set(() {
                    hiredOn = d;
                    if (returnDue != null && returnDue!.isBefore(d)) returnDue = d;
                  });
                },
              ),
              ListTile(
                key: const Key('equipment-return-due'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_available),
                title: Text(tr('Goes back on (optional)')),
                subtitle: Text(returnDue == null ? tr('Not agreed') : fmtDate(returnDue!)),
                trailing: returnDue == null
                    ? null
                    : IconButton(
                        tooltip: tr('Clear'), icon: const Icon(Icons.close), onPressed: () => set(() => returnDue = null)),
                onTap: () async {
                  final d = await pick(ctx, returnDue ?? hiredOn.add(const Duration(days: 7)), first: hiredOn);
                  if (d != null) set(() => returnDue = d);
                },
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('Cancel'))),
          FilledButton(
            key: const Key('equipment-save'),
            onPressed: () {
              if (name.text.trim().isEmpty) {
                set(() => nameError = tr('Enter a name'));
                return;
              }
              Navigator.of(ctx).pop(true);
            },
            child: Text(tr('Save')),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final fields = EquipmentCompanion(
    name: Value(_cut(name.text.trim(), 200)),
    equipmentType: Value(_orNull(equipmentType.text)),
    model: Value(_orNull(model.text)),
    registrationNumber: Value(_orNull(registrationNumber.text)),
    dailyRate: Value(_amount(dailyRate.text)),
    hourlyRate: Value(_amount(hourlyRate.text)),
    ownership: Value(hired ? 'hired' : 'own'),
    hiredFrom: Value(hired ? _orNull(hiredFrom.text) : null),
    hiredOn: Value(hired ? hiredOn : null),
    returnDueOn: Value(hired ? returnDue : null),
    // The cloud keeps a return on or after the hire date.
    returnedOn: Value(!hired || e?.returnedOn == null
        ? null
        : (e!.returnedOn!.isBefore(hiredOn) ? hiredOn : e.returnedOn)),
  );
  final dao = ref.read(appDatabaseProvider).equipmentDao;
  if (e == null) {
    await dao.create(fields.copyWith(
      id: Value(const Uuid().v4()),
      projectId: Value(projectId),
      status: const Value('available'),
    ));
  } else {
    await dao.edit(e.id, fields);
  }
  ref.invalidate(equipmentProvider(projectId));
}

String _plain(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

String _cut(String s, int max) => s.length <= max ? s : s.substring(0, max);

Widget _sectionHeader(BuildContext context, String title, VoidCallback onAdd) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      IconButton(icon: const Icon(Icons.add), tooltip: tr('Add'), onPressed: onAdd),
    ],
  ),
);

class _EquipmentTile extends ConsumerWidget {
  const _EquipmentTile({required this.equipment, required this.projectId, required this.userId});
  final EquipmentData equipment;
  final String projectId;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        title: Text(equipment.name),
        subtitle: Text(
          [
            [
              equipment.equipmentType ?? '',
              equipment.model ?? '',
              equipment.registrationNumber ?? '',
              if (equipment.hourlyRate != null) trf('{rate}/hour', {'rate': rupees(equipment.hourlyRate!, paise: true)}),
            ].where((e) => e.isNotEmpty).join(' · '),
            if (isHired(equipment)) hireLine(equipment, DateTime.now()),
          ].where((e) => e.isNotEmpty).join('\n'),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _statusBadge(equipment.status),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              initialValue: equipment.status,
              onSelected: (s) async {
                final dao = ref.read(appDatabaseProvider).equipmentDao;
                if (s == '_edit') {
                  await editEquipment(context, ref, projectId: projectId, existing: equipment);
                  return;
                }
                if (s == '_returned') {
                  await dao.markReturned(equipment.id, DateTime.now());
                  if (context.mounted) showSnack(context, 'Marked as returned.');
                } else {
                  await dao.updateStatus(equipment.id, s);
                }
                ref.invalidate(equipmentProvider(projectId));
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(value: 'available', child: Text(tr('Available'))),
                PopupMenuItem(value: 'in_use', child: Text(tr('In use'))),
                PopupMenuItem(value: 'maintenance', child: Text(tr('Maintenance'))),
                PopupMenuItem(value: 'breakdown', child: Text(tr('Breakdown'))),
                const PopupMenuDivider(),
                PopupMenuItem(value: '_edit', child: Text(tr('Edit details'))),
                if (isHired(equipment) && equipment.returnedOn == null)
                  PopupMenuItem(value: '_returned', child: Text(tr('Returned to owner'))),
              ],
            ),
            IconButton(icon: const Icon(Icons.list_alt), tooltip: tr('View logs'), onPressed: () => _showLogs(context)),
          ],
        ),
        onTap: () => _showLogs(context),
      ),
    );
  }

  Widget _statusBadge(String status) => switch (status) {
    'available' => const StatusPill('Available', tone: PillTone.ok),
    'in_use' => const StatusPill('In use'),
    'maintenance' => const StatusPill('In maintenance', tone: PillTone.warn),
    'breakdown' => const StatusPill('Broken down', tone: PillTone.danger),
    _ => StatusPill(status.replaceAll('_', ' ')),
  };

  Future<void> _showLogs(BuildContext context) => showDialog<void>(
    context: context,
    // Watches the logs, so one just added shows at once (the list used
    // to be read once, when the dialog opened).
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final logs = ref.watch(equipmentLogsProvider(equipment.id));
        return AlertDialog(
          title: Text(equipment.name),
          scrollable: true,
          content: SizedBox(
            width: 400,
            child: logs.when(
              data: (rows) => rows.isEmpty
                  ? Text(tr('No logs yet. Add hours worked, fuel, repairs or servicing.'))
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final l in rows)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text('${fmtDate(l.logDate, short: true)} · ${_logTypeLabel(l.logType)}'),
                            subtitle: Text(
                              [
                                if (l.hoursUsed != null) '${fmtQty(l.hoursUsed!)} h',
                                if (l.cost != null) rupees(l.cost!, paise: true),
                                if ((l.description ?? '').isNotEmpty) l.description!,
                              ].join(' · '),
                            ),
                          ),
                      ],
                    ),
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, st) => Text(friendlyError(e, st)),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(tr('Close'))),
            FilledButton(onPressed: () => _addLog(ctx, ref), child: Text(tr('Add log'))),
          ],
        );
      },
    ),
  );

  Future<void> _addLog(BuildContext context, WidgetRef ref) async {
    final logType = TextEditingController(text: 'usage');
    final hoursUsed = TextEditingController();
    final description = TextEditingController();
    final cost = TextEditingController();
    String? hoursError;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(tr('Add equipment log')),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: 'usage',
                decoration: InputDecoration(labelText: tr('What happened')),
                items: [for (final t in _logTypes) DropdownMenuItem(value: t, child: Text(_logTypeLabel(t)))],
                onChanged: (v) => logType.text = v ?? 'usage',
              ),
              TextField(
                key: const Key('log-hours'),
                controller: hoursUsed,
                onChanged: (_) => setDialogState(() {}),
                decoration: InputDecoration(
                  labelText: tr('Hours (optional)'),
                  errorText: hoursError,
                  helperText: () {
                    final c = costAtHourlyRate(equipment, _amount(hoursUsed.text));
                    return c == null || cost.text.trim().isNotEmpty
                        ? null
                        : trf('At {rate}/hour: {amount}', {
                            'rate': rupees(equipment.hourlyRate!, paise: true),
                            'amount': rupees(c, paise: true),
                          });
                  }(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              TextField(
                controller: description,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: tr('Note (optional)')),
              ),
              TextField(
                controller: cost,
                onChanged: (_) => setDialogState(() {}),
                decoration: InputDecoration(labelText: tr('Cost (optional)'), prefixText: '₹ '),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('Cancel'))),
            FilledButton(
              onPressed: () {
                // The cloud keeps hours below 10,000 (a meter reading, at most).
                final h = _amount(hoursUsed.text);
                final bad = hoursUsed.text.trim().isNotEmpty && (h == null || h >= 10000);
                if (bad) {
                  setDialogState(() => hoursError = 'Enter hours as a number below 10,000');
                  return;
                }
                Navigator.of(ctx).pop(true);
              },
              child: Text(tr('Save')),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref
        .read(appDatabaseProvider)
        .equipmentDao
        .addLog(
          EquipmentLogsCompanion.insert(
            id: const Uuid().v4(),
            equipmentId: equipment.id,
            logDate: DateTime.now(),
            logType: logType.text,
            hoursUsed: Value(_amount(hoursUsed.text)),
            description: Value(_orNull(description.text)),
            // Hours worked by a machine with an hourly rate cost that
            // much unless a cost was typed.
            cost: Value(_amount(cost.text) ??
                (logType.text == 'usage' ? costAtHourlyRate(equipment, _amount(hoursUsed.text)) : null)),
            createdBy: userId,
          ),
        );
    ref.invalidate(equipmentLogsProvider(equipment.id));
    ref.invalidate(equipmentProvider(projectId));
  }
}

const _logTypes = ['usage', 'fuel', 'maintenance', 'repair', 'inspection'];

String _logTypeLabel(String t) => switch (t) {
  'usage' => tr('Worked'),
  'fuel' => tr('Fuel'),
  'maintenance' => tr('Servicing'),
  'repair' => tr('Repair'),
  'inspection' => tr('Inspection'),
  _ => t.replaceAll('_', ' '),
};

String? _orNull(String text) => text.trim().isEmpty ? null : text.trim();

/// A typed amount, tolerating "1,500" and a stray "₹"; null when blank,
/// unreadable or negative.
double? _amount(String text) {
  final v = double.tryParse(text.replaceAll(RegExp(r'[₹,\s]'), ''));
  return v == null || v < 0 || v.isNaN || v.isInfinite ? null : v;
}

/// "Hired from Sri Balaji since 3 Nov · 6 days · back by 10 Nov".
String hireLine(EquipmentData e, DateTime now) {
  final parts = <String>[
    if ((e.hiredFrom ?? '').isNotEmpty) trf('Hired from {who}', {'who': e.hiredFrom!}) else tr('Hired'),
    if (e.hiredOn != null) trf('since {date}', {'date': fmtDate(e.hiredOn!, short: true)}),
    trf('{n} days', {'n': daysOnHire(e, now)}),
  ];
  switch (hireState(e, now)) {
    case HireState.returned:
      parts.add(trf('returned {date}', {'date': fmtDate(e.returnedOn!, short: true)}));
    case HireState.overdue:
      parts.add(trf('{n} days late to go back', {'n': daysOverdue(e, now)}));
    case HireState.dueSoon:
    case HireState.onHire:
      if (e.returnDueOn != null) parts.add(trf('back by {date}', {'date': fmtDate(e.returnDueOn!, short: true)}));
  }
  return parts.join(' · ');
}

class _HireSummary extends ConsumerWidget {
  const _HireSummary({required this.equipment, required this.projectId});
  final List<EquipmentData> equipment;
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final onHire = equipment.where((e) => isHired(e) && e.returnedOn == null).toList();
    final late = onHire.where((e) => hireState(e, now) == HireState.overdue).length;
    return Card(
      key: const Key('hire-summary'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.handshake_outlined),
        title: Text(tr('Hire register')),
        subtitle: Text([
          trf('{n} on hire', {'n': onHire.length}),
          if (late > 0) trf('{n} late to go back', {'n': late}),
        ].join(' · ')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => HireRegisterScreen(projectId: projectId),
        )),
      ),
    );
  }
}
