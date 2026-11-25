/// Site operations: the quality officer's tests (cube, plaster, paint,
/// bitumen, with required against actual and the 7, 14 and 28-day
/// reminders), the safety breach log by department, and the security
/// gate (punch in and out, frisking, breathalyser). It opens on the tab
/// that suits the person's role on the site.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/auth/site_roles.dart';
import 'package:fieldos_mobile/core/date_pick.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/execution/execution_rules.dart' show parseDay, ymd;
import 'package:fieldos_mobile/features/execution/site_ops_rules.dart';
import 'package:fieldos_mobile/features/team/site_team_screen.dart' show mySiteAccessProvider;
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

final qualityProvider = FutureProvider.autoDispose.family<List<QualityTest>, String>(
    (ref, id) => ref.watch(appDatabaseProvider).siteOpsDao.qualityFor(id));
final breachesProvider = FutureProvider.autoDispose.family<List<SafetyBreach>, String>(
    (ref, id) => ref.watch(appDatabaseProvider).siteOpsDao.breachesFor(id));
final gateProvider = FutureProvider.autoDispose.family<List<GateCheck>, String>(
    (ref, id) => ref.watch(appDatabaseProvider).siteOpsDao.gateFor(id));

/// Which tab a role opens on: 0 quality, 1 safety, 2 security gate.
int opsTabForRole(String siteRole) => switch (siteRole) {
      SiteRole.security => 2,
      SiteRole.qualityOfficer => 0,
      _ => 0,
    };

String _day(String? v) {
  final d = parseDay(v);
  return d == null ? '' : fmtDate(d, short: true);
}

Future<void> _run(BuildContext context, Future<void> Function() go, void Function() refresh, {String? done}) async {
  try {
    await go();
    refresh();
    if (done != null && context.mounted) showSnack(context, done);
  } on ExecutionRefused catch (e) {
    if (context.mounted) showSnack(context, e.message, error: true);
  } catch (e) {
    if (context.mounted) showSnack(context, trf('Could not save: {error}', {'error': '$e'}), error: true);
  }
}

class SiteOpsScreen extends ConsumerWidget {
  const SiteOpsScreen({super.key, required this.project, this.initialTab});
  final Project project;
  final int? initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(mySiteAccessProvider(project.id)).value;
    final start = initialTab ?? (access == null ? 0 : opsTabForRole(access.siteRole));
    final canWrite = access?.canWrite ?? true;
    return DefaultTabController(
      length: 3,
      initialIndex: start,
      child: Scaffold(
        appBar: AppBar(
          title: Text(trf('{site}: quality, safety and security', {'site': project.name})),
          bottom: TabBar(isScrollable: true, tabs: [
            Tab(text: tr('Quality tests')),
            Tab(text: tr('Safety breaches')),
            Tab(text: tr('Security gate')),
          ]),
        ),
        body: TabBarView(children: [
          QualityTestsTab(project: project, canWrite: canWrite),
          SafetyTab(project: project, canWrite: canWrite, canClose: access?.managesSite ?? false),
          GateTab(project: project, canWrite: canWrite),
        ]),
      ),
    );
  }
}

// --- Quality ---------------------------------------------------------------------

class QualityTestsTab extends ConsumerWidget {
  const QualityTestsTab({super.key, required this.project, required this.canWrite});
  final Project project;
  final bool canWrite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(qualityProvider(project.id));
    final theme = Theme.of(context);
    final now = DateTime.now();
    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
        data: (all) {
          if (all.isEmpty) {
            return EmptyState(
              icon: Icons.science_outlined,
              title: tr('No tests logged yet'),
              message: tr('Log concrete cubes (with the 7, 14 and 28-day reminders), plastering, painting and bitumen tests, with the value each must show.'),
              actionLabel: canWrite ? tr('New test') : null,
              onAction: canWrite ? () => _add(context, ref) : null,
            );
          }
          final s = summariseQuality(all, now);
          int rank(QualityTest t) => switch (qualityDueState(t, now)) { 'overdue' => 0, 'soon' => 1, 'later' => 2, _ => 3 };
          final list = [...all]..sort((a, b) {
              final c = rank(a).compareTo(rank(b));
              return c != 0 ? c : a.dueOn.compareTo(b.dueOn);
            });
          return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  [
                    trf('{n} passed', {'n': s.passed}),
                    trf('{n} failed', {'n': s.failed}),
                    if (s.overdue > 0) trf('{n} overdue', {'n': s.overdue}),
                    if (s.soon > 0) trf('{n} due soon', {'n': s.soon}),
                  ].join(' · '),
                  key: const Key('quality-summary'),
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
            for (final t in list)
              Card(
                key: Key('test-${t.id}'),
                margin: const EdgeInsets.only(top: 8),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 8, 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          [qualityKindLabel(t.kind), if (t.ageDays != null) trf('{n}-day', {'n': t.ageDays!})].join(' · '),
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                      Flexible(flex: 2, child: _pill(t, now)),
                    ]),
                    Text(t.parameter, style: theme.textTheme.bodyLarge),
                    Text(
                      [
                        if ((t.batchNo ?? '').isNotEmpty) trf('batch {no}', {'no': t.batchNo!}),
                        if ((t.element ?? '').isNotEmpty) t.element!,
                        trf('sampled {day}', {'day': _day(t.sampledOn)}),
                        if (t.result == 'pending') trf('due {day}', {'day': _day(t.dueOn)}),
                        if ((t.officer ?? '').isNotEmpty) trf('officer {who}', {'who': t.officer!}),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      '${tr('Required')} ${t.rule == 'max' ? '≤' : '≥'} ${fmtQty(t.requiredValue)} ${t.unit ?? ''}'
                      '${t.actualValue == null ? '' : '  ·  ${tr('Actual')} ${fmtQty(t.actualValue!)} ${t.unit ?? ''}'}',
                      key: Key('test-values-${t.id}'),
                      style: theme.textTheme.bodyMedium,
                    ),
                    if ((t.note ?? '').isNotEmpty) Text(t.note!, style: theme.textTheme.bodySmall),
                    if (canWrite && t.result == 'pending')
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(key: Key('test-record-${t.id}'), onPressed: () => _record(context, ref, t), child: Text(tr('Record the result'))),
                      ),
                  ]),
                ),
              ),
          ]);
        },
      ),
      floatingActionButton: canWrite && (async.value?.isNotEmpty ?? false)
          ? FloatingActionButton.extended(heroTag: 'test', icon: const Icon(Icons.add), label: Text(tr('New test')), onPressed: () => _add(context, ref))
          : null,
    );
  }

  Widget _pill(QualityTest t, DateTime now) {
    if (t.result == 'pass') return StatusPill(qualityResultLabel('pass'), tone: PillTone.ok);
    if (t.result == 'fail') return StatusPill(qualityResultLabel('fail'), tone: PillTone.danger);
    return switch (qualityDueState(t, now)) {
      'overdue' => StatusPill(tr('Overdue'), tone: PillTone.danger),
      'soon' => StatusPill(tr('Due soon'), tone: PillTone.warn),
      _ => StatusPill(qualityResultLabel('pending')),
    };
  }

  Future<void> _record(BuildContext context, WidgetRef ref, QualityTest t) async {
    final actual = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Record the result')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            key: const Key('test-actual'),
            controller: actual,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: '${tr('Actual')} (${t.unit ?? ''})', helperText: '${tr('Required')} ${t.rule == 'max' ? '≤' : '≥'} ${fmtQty(t.requiredValue)}'),
          ),
          TextField(controller: note, decoration: InputDecoration(labelText: tr('Note (optional)'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(key: const Key('test-record-save'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final v = double.tryParse(actual.text.trim().replaceAll(',', ''));
    if (v == null) {
      showSnack(context, tr('Enter the value the test showed.'), error: true);
      return;
    }
    await _run(context, () async {
      await ref.read(appDatabaseProvider).siteOpsDao.recordTest(t.id, actual: v, note: note.text, by: ref.read(sessionProvider).user!.id);
    }, () => ref.invalidate(qualityProvider(project.id)));
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    var kind = 'cube';
    var grade = 'M25';
    final parameter = TextEditingController();
    final unit = TextEditingController();
    final required = TextEditingController();
    final batch = TextEditingController();
    final element = TextEditingController();
    final officer = TextEditingController();
    var rule = 'min';
    var day = ymd(DateTime.now());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          if (kind != 'cube' && parameter.text.isEmpty) {
            final p = qualityPreset(kind);
            parameter.text = p.parameter;
            unit.text = p.unit;
          }
          return AlertDialog(
            title: Text(tr('New test')),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  key: const Key('test-kind'),
                  initialValue: kind,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('Test')),
                  items: [for (final k in qualityKinds) DropdownMenuItem(value: k, child: Text(qualityKindLabel(k)))],
                  onChanged: (v) => set(() {
                    kind = v ?? kind;
                    final p = qualityPreset(kind);
                    parameter.text = p.parameter;
                    unit.text = p.unit;
                    rule = p.rule;
                  }),
                ),
                if (kind == 'cube')
                  DropdownButtonFormField<String>(
                    initialValue: grade,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('Concrete grade')),
                    items: [for (final g in concreteGrades) DropdownMenuItem(value: g, child: Text(g))],
                    onChanged: (v) => set(() => grade = v ?? grade),
                  )
                else ...[
                  TextField(controller: parameter, decoration: InputDecoration(labelText: tr('What is measured'))),
                  Row(children: [
                    Expanded(child: TextField(controller: unit, decoration: InputDecoration(labelText: tr('Unit')))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        key: const Key('test-required'),
                        controller: required,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: tr('Required value')),
                      ),
                    ),
                  ]),
                  SegmentedButton<String>(
                    segments: [ButtonSegment(value: 'min', label: Text(tr('At least'))), ButtonSegment(value: 'max', label: Text(tr('At most')))],
                    selected: {rule},
                    onSelectionChanged: (v) => set(() => rule = v.first),
                  ),
                ],
                TextField(controller: batch, decoration: InputDecoration(labelText: tr('Batch or lot number (optional)'))),
                TextField(controller: element, decoration: InputDecoration(labelText: tr('Where taken from (optional)'), hintText: tr('e.g. Column C4, 2nd floor slab'))),
                TextField(controller: officer, decoration: InputDecoration(labelText: tr('Quality officer (optional)'))),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(trf('sampled {day}', {'day': _day(day)})),
                  onTap: () async {
                    final now = DateTime.now();
                    final d = await pickDate(ctx, initial: parseDay(day) ?? now, first: now.subtract(const Duration(days: 60)), last: now);
                    if (d != null) set(() => day = ymd(d));
                  },
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
              FilledButton(key: const Key('test-save'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
            ],
          );
        },
      ),
    );
    if (ok != true || !context.mounted) return;
    final dao = ref.read(appDatabaseProvider).siteOpsDao;
    final by = ref.read(sessionProvider).user!.id;
    await _run(context, () async {
      if (kind == 'cube') {
        await dao.addCubeSet(projectId: project.id, grade: grade, castOn: day, batchNo: batch.text, element: element.text, officer: officer.text, by: by);
      } else {
        await dao.addQualityTest(
          projectId: project.id,
          kind: kind,
          parameter: parameter.text,
          unit: unit.text,
          rule: rule,
          requiredValue: double.tryParse(required.text.trim()) ?? 0,
          sampledOn: day,
          batchNo: batch.text,
          element: element.text,
          officer: officer.text,
          by: by,
        );
      }
    }, () => ref.invalidate(qualityProvider(project.id)));
  }
}

// --- Safety ----------------------------------------------------------------------

class SafetyTab extends ConsumerWidget {
  const SafetyTab({super.key, required this.project, required this.canWrite, required this.canClose});
  final Project project;
  final bool canWrite;
  final bool canClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(breachesProvider(project.id));
    final theme = Theme.of(context);
    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
        data: (all) {
          if (all.isEmpty) {
            return EmptyState(
              icon: Icons.health_and_safety_outlined,
              title: tr('No safety breaches logged'),
              message: tr('Log a breach against the department that committed it, and close it when action is taken.'),
              actionLabel: canWrite ? tr('Log a breach') : null,
              onAction: canWrite ? () => _add(context, ref) : null,
            );
          }
          final open = all.where((b) => b.closedAt == null).toList();
          final by = breachesByDepartment(all);
          return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(trf('{n} open of {total}', {'n': open.length, 'total': all.length}), key: const Key('breach-summary'), style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final e in by) Chip(visualDensity: VisualDensity.compact, label: Text('${departmentLabel(e.key)}: ${e.value}')),
                  ]),
                ]),
              ),
            ),
            for (final b in all)
              Card(
                key: Key('breach-${b.id}'),
                margin: const EdgeInsets.only(top: 8),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 8, 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('${departmentLabel(b.department)} · ${_day(b.onDay)}', style: theme.textTheme.labelLarge)),
                      Flexible(
                        flex: 2,
                        child: b.closedAt != null
                            ? StatusPill(tr('Closed'), tone: PillTone.ok)
                            : StatusPill(severityLabel(b.severity), tone: b.severity == 'minor' ? PillTone.neutral : (b.severity == 'major' ? PillTone.warn : PillTone.danger)),
                      ),
                    ]),
                    Text(b.description, style: theme.textTheme.bodyLarge),
                    if ((b.who ?? '').isNotEmpty) Text(b.who!, style: theme.textTheme.bodySmall),
                    if ((b.actionTaken ?? '').isNotEmpty) Text('${tr('Action')}: ${b.actionTaken}', style: theme.textTheme.bodySmall),
                    if (canClose && b.closedAt == null)
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(key: Key('breach-close-${b.id}'), onPressed: () => _close(context, ref, b), child: Text(tr('Close it'))),
                      ),
                  ]),
                ),
              ),
          ]);
        },
      ),
      floatingActionButton: canWrite && (async.value?.isNotEmpty ?? false)
          ? FloatingActionButton.extended(heroTag: 'breach', icon: const Icon(Icons.add), label: Text(tr('Log a breach')), onPressed: () => _add(context, ref))
          : null,
    );
  }

  Future<void> _close(BuildContext context, WidgetRef ref, SafetyBreach b) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Close it')),
        content: TextField(key: const Key('breach-action'), controller: c, autofocus: true, maxLines: 3, decoration: InputDecoration(labelText: tr('What was done about it'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(key: const Key('breach-close-save'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(context, () async {
      await ref.read(appDatabaseProvider).siteOpsDao.closeBreach(b.id, action: c.text, by: ref.read(sessionProvider).user!.id);
    }, () => ref.invalidate(breachesProvider(project.id)));
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    var dept = 'civil';
    var severity = 'minor';
    final what = TextEditingController();
    final who = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Log a breach')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: dept,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Department')),
                items: [for (final d in safetyDepartments) DropdownMenuItem(value: d, child: Text(departmentLabel(d)))],
                onChanged: (v) => set(() => dept = v ?? dept),
              ),
              TextField(key: const Key('breach-what'), controller: what, maxLines: 2, decoration: InputDecoration(labelText: tr('What happened'), hintText: tr('e.g. Working at height without a harness'))),
              TextField(controller: who, decoration: InputDecoration(labelText: tr('Who or which gang (optional)'))),
              Wrap(spacing: 8, children: [
                for (final s in breachSeverities) ChoiceChip(label: Text(severityLabel(s)), selected: severity == s, onSelected: (_) => set(() => severity = s)),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(key: const Key('breach-save'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(context, () async {
      await ref.read(appDatabaseProvider).siteOpsDao.addBreach(
          projectId: project.id, department: dept, description: what.text, who: who.text, severity: severity, by: ref.read(sessionProvider).user!.id);
    }, () => ref.invalidate(breachesProvider(project.id)));
  }
}

// --- Security gate ---------------------------------------------------------------

class GateTab extends ConsumerWidget {
  const GateTab({super.key, required this.project, required this.canWrite});
  final Project project;
  final bool canWrite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(gateProvider(project.id));
    final theme = Theme.of(context);
    final now = DateTime.now();
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => ErrorState(error: e, stack: st),
      data: (all) {
        final inside = insideTheGate(all, now);
        final today = DateTime(now.year, now.month, now.day);
        final flaggedToday = all.where((g) => g.result == 'flagged' && !g.createdAt.isBefore(today)).length;
        return ListView(padding: const EdgeInsets.all(12), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(trf('{n} people inside now', {'n': inside.length}), key: const Key('gate-inside'), style: theme.textTheme.titleMedium),
                if (flaggedToday > 0) Text(trf('{n} flagged today', {'n': flaggedToday}), style: TextStyle(color: theme.colorScheme.error)),
              ]),
            ),
          ),
          if (canWrite)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final k in gateKinds)
                  FilledButton.tonal(key: Key('gate-$k'), onPressed: () => _check(context, ref, k), child: Text(gateKindLabel(k))),
              ]),
            ),
          if (all.isEmpty)
            Padding(padding: const EdgeInsets.all(24), child: Text(tr('Nothing logged at the gate yet.'), textAlign: TextAlign.center)),
          for (final g in all.take(100))
            ListTile(
              key: Key('gate-row-${g.id}'),
              dense: true,
              leading: Icon(g.result == 'flagged' ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                  color: g.result == 'flagged' ? theme.colorScheme.error : null),
              title: Text('${g.personName} · ${gateKindLabel(g.kind)}'),
              subtitle: Text([
                fmtDate(g.createdAt, short: true),
                '${g.createdAt.hour.toString().padLeft(2, '0')}:${g.createdAt.minute.toString().padLeft(2, '0')}',
                if ((g.item ?? '').isNotEmpty) g.item!,
                if (g.reading != null) '${fmtQty(g.reading!)} mg/100 ml',
                if ((g.note ?? '').isNotEmpty) g.note!,
              ].join(' · ')),
            ),
        ]);
      },
    );
  }

  Future<void> _check(BuildContext context, WidgetRef ref, String kind) async {
    final name = TextEditingController();
    final reading = TextEditingController();
    final note = TextEditingController();
    var item = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(gateKindLabel(kind)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(key: const Key('gate-name'), controller: name, autofocus: true, decoration: InputDecoration(labelText: tr('Name'))),
              if (kind == 'frisk') ...[
                const SizedBox(height: 8),
                Text(tr('Found anything?'), style: Theme.of(ctx).textTheme.labelLarge),
                Wrap(spacing: 8, children: [
                  for (final p in prohibitedItems)
                    ChoiceChip(
                      key: Key('gate-item-$p'),
                      label: Text(tr(p)),
                      selected: item == p,
                      onSelected: (v) => set(() => item = v ? p : ''),
                    ),
                ]),
              ],
              if (kind == 'breath')
                TextField(
                  key: const Key('gate-reading'),
                  controller: reading,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: tr('Reading (mg/100 ml)'), helperText: tr('Anything above 0 is flagged.')),
                ),
              TextField(controller: note, decoration: InputDecoration(labelText: tr('Note (optional)'))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(key: const Key('gate-save'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(context, () async {
      await ref.read(appDatabaseProvider).siteOpsDao.addGateCheck(
            projectId: project.id,
            kind: kind,
            personName: name.text,
            item: item == 'Other' ? tr('Other') : item,
            reading: double.tryParse(reading.text.trim()),
            note: note.text,
            by: ref.read(sessionProvider).user!.id,
          );
    }, () => ref.invalidate(gateProvider(project.id)));
  }
}
