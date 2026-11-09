/// Worker directory per project (name, role, phone, daily wage, active/inactive).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/features/workers/worker_calendar.dart';
import 'package:fieldos_mobile/features/workers/worker_tools.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/features/mascot/mitra.dart';

class WorkersView extends ConsumerStatefulWidget {
  const WorkersView({
    super.key,
    required this.projectId,
    required this.userId,
  });
  final String projectId;
  final String userId;

  @override
  ConsumerState<WorkersView> createState() => _WorkersViewState();
}

class _WorkersViewState extends ConsumerState<WorkersView> {
  final _search = TextEditingController();
  String? _role;
  bool _activeOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workersList = ref.watch(workersProvider(widget.projectId));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(tr('Workers'), style: Theme.of(context).textTheme.titleSmall),
              Row(mainAxisSize: MainAxisSize.min, children: [
                TextButton.icon(
                  icon: const Icon(Icons.playlist_add),
                  label: Text(tr('Add many')),
                  onPressed: () => _addMany(context),
                ),
                IconButton(icon: const Icon(Icons.add), tooltip: tr('Add worker'), onPressed: () => _addWorker(context, ref)),
              ]),
            ],
          ),
        ),
        Expanded(
          child: workersList.when(
            data: (rows) {
              if (rows.isEmpty) return MitraEmpty(tr('No workers yet.'));
              final roles = rolesOf(rows);
              final shown = filterWorkers(rows, query: _search.text, role: _role, activeOnly: _activeOnly);
              return ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  if (rows.length > 5) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: tr('Search by name, skill or phone'),
                          isDense: true,
                        ),
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: Row(children: [
                        FilterChip(
                          label: Text(tr('Active')),
                          selected: _activeOnly,
                          onSelected: (v) => setState(() => _activeOnly = v),
                        ),
                        for (final r in roles) ...[
                          const SizedBox(width: 6),
                          ChoiceChip(
                            label: Text(r),
                            selected: _role == r,
                            onSelected: (v) => setState(() => _role = v ? r : null),
                          ),
                        ],
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Text(
                        trf('{shown} of {all} workers', {'shown': shown.length, 'all': rows.length}),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                  for (final w in shown) _WorkerTile(worker: w, projectId: widget.projectId),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => ErrorState(error: e, stack: st),
          ),
        ),
      ],
    );
  }

  /// True when it is fine to add: no look-alike, or the person said it is
  /// someone else.
  Future<bool> _confirmNotDuplicate(BuildContext context, String name, String? phone) async {
    final existing = await ref.read(appDatabaseProvider).workerDao.forProject(widget.projectId);
    final same = findDuplicate(existing, name: name, phone: phone);
    if (same == null || !context.mounted) return true;
    final samePhone = normalizePhone(phone).length >= 10 && normalizePhone(phone) == normalizePhone(same.phone);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Already on the list?')),
        content: Text(samePhone
            ? trf('{name} already has this phone number.', {'name': same.name})
            : trf('There is already a worker called {name}.', {'name': same.name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Add anyway'))),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _addMany(BuildContext context) async {
    final text = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Add many workers')),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('One worker per line: name, skill, phone, daily wage. Only the name is needed.'),
                style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 8),
            TextField(
              controller: text,
              minLines: 5,
              maxLines: 12,
              decoration: const InputDecoration(hintText: 'Ramesh, Mason, 9848012345, 900\nSuresh, Helper, 600'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Add'))),
        ],
      ),
    );
    final parsed = parseWorkerLines(text.text);
    if (ok != true || parsed.isEmpty || !context.mounted) return;
    final db = ref.read(appDatabaseProvider);
    final existing = [...await db.workerDao.forProject(widget.projectId)];
    var added = 0;
    final skipped = <String>[];
    for (final n in parsed) {
      if (findDuplicate(existing, name: n.name, phone: n.phone) != null) {
        skipped.add(n.name);
        continue;
      }
      final w = await db.workerDao.create(WorkersCompanion.insert(
        id: const Uuid().v4(),
        projectId: widget.projectId,
        name: n.name,
        role: Value(n.role),
        phone: Value(n.phone),
        dailyWage: Value(n.dailyWage),
        status: const Value('active'),
      ));
      existing.add(w);
      added++;
    }
    ref.invalidate(workersProvider(widget.projectId));
    if (!context.mounted) return;
    showSnack(
      context,
      skipped.isEmpty
          ? trf('{n} workers added.', {'n': added})
          : trf('{n} workers added. Already on the list: {names}.', {'n': added, 'names': skipped.join(', ')}),
    );
  }

  Future<void> _addWorker(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final role = TextEditingController();
    final phone = TextEditingController();
    final dailyWage = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Add worker')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: InputDecoration(labelText: tr('Name'))),
            TextField(controller: role, decoration: InputDecoration(labelText: tr('Role'))),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: tr('Phone'))),
            TextField(
              controller: dailyWage,
              decoration: InputDecoration(labelText: tr('Daily wage')),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(tr('Save'))),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !context.mounted) return;
    if (!await _confirmNotDuplicate(context, name.text, phone.text)) return;
    await ref.read(appDatabaseProvider).workerDao.create(WorkersCompanion.insert(
          id: const Uuid().v4(),
          projectId: widget.projectId,
          name: name.text.trim(),
          role: Value(role.text.trim()),
          phone: Value(phone.text.trim()),
          dailyWage: Value(double.tryParse(dailyWage.text)),
          status: const Value('active'),
        ));
    ref.invalidate(workersProvider(widget.projectId));
  }
}

class _WorkerTile extends ConsumerWidget {
  const _WorkerTile({required this.worker, required this.projectId});
  final Worker worker;
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        onTap: () => openWorkerCalendar(context, worker),
        title: Text(worker.name),
        subtitle: Text([
          worker.role ?? '',
          worker.phone ?? '',
          worker.dailyWage != null ? '${rupees(worker.dailyWage!)} a day' : '',
        ].where((e) => e.isNotEmpty).join(' · ')),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _statusBadge(worker.status),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              initialValue: worker.status,
              onSelected: (s) async {
                await ref.read(appDatabaseProvider).workerDao.setStatus(worker.id, s);
                ref.invalidate(workersProvider(projectId));
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(value: 'active', child: Text(tr('Active'))),
                PopupMenuItem(value: 'inactive', child: Text(tr('Inactive'))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String status) =>
      status == 'active' ? const StatusPill('Active', tone: PillTone.ok) : const StatusPill('Not active');
}