/// Pre-construction: the approvals and clearances a site waits for (GHMC,
/// Fire NOC and so on) with where each one is stuck, the drawing log with
/// its revisions up to Good for Construction, and the time and cost spent
/// on liaison. The firm's own liaison cost is shown to the owner and
/// project managers only.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/date_pick.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/execution/execution_data.dart';
import 'package:fieldos_mobile/features/execution/execution_rules.dart';
import 'package:fieldos_mobile/features/execution/pre_construction_rules.dart';
import 'package:fieldos_mobile/features/project/project_status.dart';
import 'package:fieldos_mobile/core/market.dart' show isIndia;
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

final approvalsProvider = FutureProvider.autoDispose.family<List<SiteApproval>, String>(
    (ref, projectId) => ref.watch(appDatabaseProvider).preConstructionDao.approvalsFor(projectId));

final liaisonProvider = FutureProvider.autoDispose.family<List<LiaisonLog>, String>(
    (ref, projectId) => ref.watch(appDatabaseProvider).preConstructionDao.liaisonFor(projectId));

String _day(String? ymdText) {
  final d = parseDay(ymdText);
  return d == null ? '' : fmtDate(d, short: true);
}

PillTone _tone(SiteApproval a, DateTime now) {
  if (a.status == 'approved') return approvalExpiring(a, now) ? PillTone.warn : PillTone.ok;
  if (a.status == 'rejected') return PillTone.danger;
  if (approvalLate(a, now)) return PillTone.danger;
  if (approvalStuck(a, now) || a.status == 'query_raised') return PillTone.warn;
  return PillTone.neutral;
}

class PreConstructionScreen extends ConsumerWidget {
  const PreConstructionScreen({super.key, required this.project});
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionProvider).role;
    final manager = Roles.canApprove(role);
    final phase = lifecyclePhaseOf(project.status);
    final tabs = [tr('Approvals'), tr('Drawing log'), if (manager) tr('Liaison time and cost')];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(trf('{site}: approvals and drawings', {'site': project.name})),
          bottom: TabBar(isScrollable: true, tabs: [for (final t in tabs) Tab(text: t)]),
        ),
        body: Column(children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              const Icon(Icons.timeline, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(lifecyclePhaseLabel(phase), key: const Key('lifecycle-phase'))),
              StatusPill(projectStatusLabel(project.status), tone: projectStatusTone(project.status)),
            ]),
          ),
          Expanded(
            child: TabBarView(children: [
              ApprovalsTab(project: project),
              DrawingLogTab(project: project),
              if (manager) LiaisonTab(project: project),
            ]),
          ),
        ]),
      ),
    );
  }
}

// --- Approvals -----------------------------------------------------------------

class ApprovalsTab extends ConsumerWidget {
  const ApprovalsTab({super.key, required this.project});
  final Project project;

  Future<void> _act(BuildContext context, WidgetRef ref, Future<void> Function() run, {String? done}) async {
    try {
      await run();
      ref.invalidate(approvalsProvider(project.id));
      ref.invalidate(liaisonProvider(project.id));
      if (done != null && context.mounted) showSnack(context, done);
    } on ExecutionRefused catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (context.mounted) showSnack(context, trf('Could not save: {error}', {'error': '$e'}), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final canWrite = session.role != null && Roles.canWrite(session.role!);
    final async = ref.watch(approvalsProvider(project.id));
    final now = DateTime.now();
    final theme = Theme.of(context);
    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
        data: (all) {
          if (all.isEmpty) {
            return EmptyState(
              icon: Icons.account_balance_outlined,
              title: tr('No approvals tracked yet'),
              message: tr(
                  'List every approval this project needs, such as GHMC building permission and Fire NOC, and see exactly where each one is stuck.'),
              actionLabel: canWrite ? tr('Add approval') : null,
              onAction: canWrite ? () => _add(context, ref) : null,
            );
          }
          final s = summariseApprovals(all, now);
          final list = [...all]
            ..sort((a, b) {
              int rank(SiteApproval x) => !approvalIsOpen(x) ? 3 : approvalLate(x, now) ? 0 : approvalStuck(x, now) ? 1 : 2;
              final c = rank(a).compareTo(rank(b));
              return c != 0 ? c : approvalIdleDays(b, now).compareTo(approvalIdleDays(a, now));
            });
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            children: [
              Card(
                key: const Key('approvals-summary'),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(trf('{done} of {total} approved', {'done': s.approved, 'total': s.total}), style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      [
                        trf('{n} open', {'n': s.open}),
                        if (s.late > 0) trf('{n} late', {'n': s.late}),
                        if (s.stuck > 0) trf('{n} stuck', {'n': s.stuck}),
                        if (s.expiring > 0) trf('{n} expiring', {'n': s.expiring}),
                      ].join(' · '),
                    ),
                    if (s.byWaitingOn.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(spacing: 6, runSpacing: 4, children: [
                          for (final e in s.byWaitingOn.entries)
                            Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(trf('Waiting on {who}: {n}', {'who': waitingOnLabel(e.key), 'n': e.value})),
                            ),
                        ]),
                      ),
                    if (s.bottleneck != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          trf('Longest wait: {title}, {n} days with {who}', {
                            'title': s.bottleneck!.title,
                            'n': approvalIdleDays(s.bottleneck!, now),
                            'who': waitingOnLabel(s.bottleneck!.waitingOn),
                          }),
                          key: const Key('approvals-bottleneck'),
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                  ]),
                ),
              ),
              for (final a in list) _card(context, ref, a, now, canWrite),
            ],
          );
        },
      ),
      floatingActionButton: canWrite && (async.value?.isNotEmpty ?? false)
          ? FloatingActionButton.extended(
              heroTag: 'approval',
              icon: const Icon(Icons.add),
              label: Text(tr('Add approval')),
              onPressed: () => _add(context, ref),
            )
          : null,
    );
  }

  Widget _card(BuildContext context, WidgetRef ref, SiteApproval a, DateTime now, bool canWrite) {
    final theme = Theme.of(context);
    final inProcess = approvalDaysInProcess(a, now);
    final left = approvalDaysToExpiry(a, now);
    return Card(
      key: Key('approval-${a.id}'),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 8, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(authorityLabel(a.authority), style: theme.textTheme.labelLarge)),
            Flexible(flex: 2, child: StatusPill(approvalStatusLabel(a.status), tone: _tone(a, now))),
          ]),
          const SizedBox(height: 2),
          Text(a.title, style: theme.textTheme.bodyLarge),
          Text(
            [
              if ((a.referenceNo ?? '').isNotEmpty) trf('File {no}', {'no': a.referenceNo!}),
              if (approvalIsOpen(a)) trf('Waiting on {who}', {'who': waitingOnLabel(a.waitingOn)}),
              if (approvalIsOpen(a)) trf('{n} days since the last move', {'n': approvalIdleDays(a, now)}),
              if (a.appliedOn != null) trf('applied {day}', {'day': _day(a.appliedOn)}),
              if (inProcess != null) trf('{n} days in process', {'n': inProcess}),
              if (approvalIsOpen(a) && a.expectedBy != null) trf('expected by {day}', {'day': _day(a.expectedBy)}),
              if (a.approvedOn != null) trf('approved {day}', {'day': _day(a.approvedOn)}),
              if ((a.liaisonBy ?? '').isNotEmpty) trf('chased by {who}', {'who': a.liaisonBy!}),
            ].join(' · '),
            style: theme.textTheme.bodySmall,
          ),
          if (left != null)
            Text(
              left < 0 ? trf('Lapsed {n} days ago', {'n': -left}) : trf('Valid until {day} ({n} days left)', {'day': _day(a.validUntil), 'n': left}),
              style: theme.textTheme.labelMedium?.copyWith(color: left <= approvalExpiryWarnDays ? theme.colorScheme.error : null),
            ),
          if ((a.note ?? '').isNotEmpty) Text(a.note!, style: theme.textTheme.bodyMedium),
          for (final line in a.history.split('\n'))
            if (parseApprovalHistory(line) case final h?)
              Text(
                '${_day(h.day)}: ${approvalStatusLabel(h.status)}${h.note.isEmpty ? '' : ' · ${h.note}'}',
                style: theme.textTheme.bodySmall,
              ),
          if (canWrite && approvalIsOpen(a))
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                key: Key('approval-move-${a.id}'),
                onPressed: () => _move(context, ref, a),
                child: Text(tr('Update status')),
              ),
            ),
        ]),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final refNo = TextEditingController();
    final liaison = TextEditingController();
    var authority = 'ghmc';
    String? expectedBy;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Add approval')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: authority,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Authority')),
                items: [for (final a in approvalAuthorities) if (a != 'rera' || isIndia) DropdownMenuItem(value: a, child: Text(authorityLabel(a)))],
                onChanged: (v) => set(() => authority = v ?? authority),
              ),
              TextField(
                key: const Key('approval-title'),
                controller: title,
                decoration: InputDecoration(labelText: tr('What is needed'), hintText: tr('e.g. Building permission')),
              ),
              TextField(controller: refNo, decoration: InputDecoration(labelText: tr('File or application number (optional)'))),
              TextField(controller: liaison, decoration: InputDecoration(labelText: tr('Who is chasing it (optional)'))),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text(expectedBy == null ? tr('Expected by (optional)') : trf('expected by {day}', {'day': _day(expectedBy)})),
                onTap: () async {
                  final now = DateTime.now();
                  final d = await pickDate(ctx, initial: parseDay(expectedBy) ?? now, first: now.subtract(const Duration(days: 30)), last: now.add(const Duration(days: 1095)));
                  if (d != null) set(() => expectedBy = ymd(d));
                },
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(key: const Key('approval-save'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await _act(
      context,
      ref,
      () => ref.read(appDatabaseProvider).preConstructionDao.addApproval(
            projectId: project.id,
            authority: authority,
            title: title.text,
            referenceNo: refNo.text,
            liaisonBy: liaison.text,
            expectedBy: expectedBy,
            by: ref.read(sessionProvider).user!.id,
          ),
    );
  }

  Future<void> _move(BuildContext context, WidgetRef ref, SiteApproval a) async {
    final note = TextEditingController();
    final refNo = TextEditingController(text: a.referenceNo ?? '');
    var status = a.status;
    var waiting = a.waitingOn;
    String? expectedBy = a.expectedBy;
    String? validUntil;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Update status')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              DropdownButtonFormField<String>(
                key: const Key('approval-status'),
                initialValue: status,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Status')),
                items: [for (final s in approvalStatuses) DropdownMenuItem(value: s, child: Text(approvalStatusLabel(s)))],
                onChanged: (v) => set(() => status = v ?? status),
              ),
              if (status != 'approved' && status != 'rejected')
                DropdownButtonFormField<String>(
                  initialValue: waiting,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('Waiting on')),
                  items: [for (final w in approvalWaitingOn) DropdownMenuItem(value: w, child: Text(waitingOnLabel(w)))],
                  onChanged: (v) => set(() => waiting = v ?? waiting),
                ),
              TextField(controller: refNo, decoration: InputDecoration(labelText: tr('File or application number (optional)'))),
              TextField(
                key: const Key('approval-note'),
                controller: note,
                maxLines: 2,
                decoration: InputDecoration(labelText: tr('What happened'), hintText: tr('e.g. Query on setbacks, reply due')),
              ),
              if (status != 'approved' && status != 'rejected')
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(expectedBy == null ? tr('Expected by (optional)') : trf('expected by {day}', {'day': _day(expectedBy)})),
                  onTap: () async {
                    final now = DateTime.now();
                    final d = await pickDate(ctx, initial: parseDay(expectedBy) ?? now, first: now.subtract(const Duration(days: 30)), last: now.add(const Duration(days: 1095)));
                    if (d != null) set(() => expectedBy = ymd(d));
                  },
                ),
              if (status == 'approved')
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_available_outlined),
                  title: Text(validUntil == null ? tr('Valid until (optional)') : trf('valid until {day}', {'day': _day(validUntil)})),
                  onTap: () async {
                    final now = DateTime.now();
                    final d = await pickDate(ctx, initial: now.add(const Duration(days: 365)), first: now, last: now.add(const Duration(days: 3650)));
                    if (d != null) set(() => validUntil = ymd(d));
                  },
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(key: const Key('approval-move-save'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await _act(
      context,
      ref,
      () => ref.read(appDatabaseProvider).preConstructionDao.moveApproval(
            a.id,
            status: status,
            waitingOn: waiting,
            note: note.text,
            referenceNo: refNo.text,
            expectedBy: expectedBy,
            validUntil: validUntil,
          ),
    );
  }
}

// --- Drawing log ------------------------------------------------------------------

/// Every drawing with its revisions in order, up to Good for Construction.
/// Drawings and their files are added under Plan, quality and handover.
class DrawingLogTab extends ConsumerWidget {
  const DrawingLogTab({super.key, required this.project});
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(executionDataProvider(project.id));
    final theme = Theme.of(context);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => ErrorState(error: e, stack: st),
      data: (d) {
        if (d.drawings.isEmpty) {
          return EmptyState(
            icon: Icons.architecture_outlined,
            title: tr('No drawings yet'),
            message: tr('Add drawings under Plan, quality and handover, then upload each revision: Rev 1, Rev 2, then GFC.'),
          );
        }
        final list = [...d.drawings]..sort((a, b) => a.number.toLowerCase().compareTo(b.number.toLowerCase()));
        final gfc = list.where((x) => d.hasGfc(x.id)).length;
        return ListView(padding: const EdgeInsets.all(12), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(trf('{done} of {total} drawings are Good for Construction', {'done': gfc, 'total': list.length}),
                  key: const Key('gfc-summary'), style: theme.textTheme.titleMedium),
            ),
          ),
          for (final dr in list)
            Card(
              margin: const EdgeInsets.only(top: 8),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('${dr.number}  ${dr.title}', style: theme.textTheme.bodyLarge)),
                    if (d.hasGfc(dr.id)) StatusPill(tr('GFC'), tone: PillTone.ok) else StatusPill(tr('Not GFC yet'), tone: PillTone.warn),
                  ]),
                  const SizedBox(height: 4),
                  for (final r in d.revisionsOf(dr.id).reversed)
                    Text(
                      [
                        r.rev,
                        _statusWord(r.status),
                        fmtDate(r.createdAt, short: true),
                        if ((r.note ?? '').isNotEmpty) r.note!,
                      ].join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                  if (d.revisionsOf(dr.id).isEmpty) Text(tr('No revision uploaded.'), style: theme.textTheme.bodySmall),
                ]),
              ),
            ),
        ]);
      },
    );
  }

  String _statusWord(String s) => switch (s) {
        'approved' => tr('Approved'),
        'rejected' => tr('Rejected'),
        _ => tr('Waiting for approval'),
      };
}

// --- Liaison time and cost --------------------------------------------------------

class LiaisonTab extends ConsumerWidget {
  const LiaisonTab({super.key, required this.project});
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(liaisonProvider(project.id));
    final approvals = ref.watch(approvalsProvider(project.id)).value ?? const <SiteApproval>[];
    final theme = Theme.of(context);
    return Scaffold(
      body: logs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.hourglass_bottom_outlined,
              title: tr('No liaison time logged yet'),
              message: tr('Log each visit to an office: who went, how long it took and what it cost, to see what approvals really cost.'),
              actionLabel: tr('Log time'),
              onAction: () => _log(context, ref, approvals),
            );
          }
          final total = liaisonTotal(list);
          final byPerson = liaisonByPerson(list);
          final byApproval = liaisonByApproval(list);
          final titles = {for (final a in approvals) a.id: a.title};
          return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(trf('{time} spent, {cost}', {'time': durationLabel(total.minutes), 'cost': money(total.cost)}),
                      key: const Key('liaison-total'), style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  for (final e in byPerson)
                    Text(
                      '${e.key.isEmpty ? tr('Not named') : e.key}: ${durationLabel(e.value.minutes)} · ${money(e.value.cost)}',
                      style: theme.textTheme.bodySmall,
                    ),
                ]),
              ),
            ),
            SectionHeader(tr('By approval'), padding: const EdgeInsets.fromLTRB(4, 12, 4, 6)),
            for (final e in byApproval.entries)
              ListTile(
                dense: true,
                title: Text(e.key.isEmpty ? tr('Not linked to an approval') : titles[e.key] ?? tr('Approval')),
                trailing: Text('${durationLabel(e.value.minutes)} · ${money(e.value.cost)}'),
              ),
            SectionHeader(tr('Visits'), padding: const EdgeInsets.fromLTRB(4, 12, 4, 6)),
            for (final l in list)
              ListTile(
                dense: true,
                title: Text([_day(l.onDay), if ((l.person ?? '').isNotEmpty) l.person!, durationLabel(l.minutes)].join(' · ')),
                subtitle: Text([
                  if (l.approvalId != null) titles[l.approvalId] ?? '',
                  if ((l.note ?? '').isNotEmpty) l.note!,
                ].where((x) => x.isNotEmpty).join(' · ')),
                trailing: Text(money(l.cost)),
              ),
          ]);
        },
      ),
      floatingActionButton: (logs.value?.isNotEmpty ?? false)
          ? FloatingActionButton.extended(
              heroTag: 'liaison',
              icon: const Icon(Icons.add),
              label: Text(tr('Log time')),
              onPressed: () => _log(context, ref, approvals),
            )
          : null,
    );
  }

  Future<void> _log(BuildContext context, WidgetRef ref, List<SiteApproval> approvals) async {
    final person = TextEditingController();
    final hours = TextEditingController();
    final minutes = TextEditingController();
    final cost = TextEditingController();
    final note = TextEditingController();
    String? approvalId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Log time')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (approvals.isNotEmpty)
                DropdownButtonFormField<String?>(
                  initialValue: approvalId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('Approval (optional)')),
                  items: [
                    DropdownMenuItem(value: null, child: Text(tr('None'))),
                    for (final a in approvals) DropdownMenuItem(value: a.id, child: Text(a.title, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => set(() => approvalId = v),
                ),
              TextField(controller: person, decoration: InputDecoration(labelText: tr('Whose time'))),
              Row(children: [
                Expanded(
                  child: TextField(
                    key: const Key('liaison-hours'),
                    controller: hours,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: tr('Hours')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const Key('liaison-minutes'),
                    controller: minutes,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: tr('Minutes')),
                  ),
                ),
              ]),
              TextField(
                key: const Key('liaison-cost'),
                controller: cost,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: tr('Cost (time, travel and fees)')),
              ),
              TextField(controller: note, decoration: InputDecoration(labelText: tr('Note (optional)'))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(key: const Key('liaison-save'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(appDatabaseProvider).preConstructionDao.logLiaison(
            projectId: project.id,
            approvalId: approvalId,
            person: person.text,
            minutes: (int.tryParse(hours.text.trim()) ?? 0) * 60 + (int.tryParse(minutes.text.trim()) ?? 0),
            cost: double.tryParse(cost.text.trim().replaceAll(',', '')) ?? 0,
            note: note.text,
            by: ref.read(sessionProvider).user!.id,
          );
      ref.invalidate(liaisonProvider(project.id));
    } on ExecutionRefused catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (context.mounted) showSnack(context, trf('Could not save: {error}', {'error': '$e'}), error: true);
    }
  }
}
