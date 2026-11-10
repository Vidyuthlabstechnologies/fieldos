/// The project director's commercial exceptions inbox (FOS-204): one queue
/// across sites for work beyond approved scope, quantities above contract,
/// overdue certifications and forecast overruns. Each has an owner, a due
/// date, a decision and the record it came from; most clear themselves
/// when that record is acted on (a claim certified, a variation decided),
/// and the rest are resolved here with a recorded decision.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/features/close/week_close_screen.dart' show closeNamesProvider;
import 'package:fieldos_mobile/features/commercial/commercial_data.dart';
import 'package:fieldos_mobile/features/commercial/commercial_rules.dart';
import 'package:fieldos_mobile/features/commercial/commercial_screens.dart';
import 'package:fieldos_mobile/features/commercial/commercial_widgets.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class CommercialExceptionsScreen extends ConsumerStatefulWidget {
  const CommercialExceptionsScreen({super.key, required this.companyId});
  final String companyId;

  @override
  ConsumerState<CommercialExceptionsScreen> createState() => _State();
}

class _State extends ConsumerState<CommercialExceptionsScreen> {
  bool _decided = false;
  bool _mineOnly = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(companyExceptionsProvider(widget.companyId));
    final names = ref.watch(closeNamesProvider(widget.companyId)).value ?? const {};
    final session = ref.watch(sessionProvider);
    final me = session.user!.id;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Commercial exceptions'))),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
        data: (sites) {
          final now = DateTime.now();
          final all = [
            for (final s in sites)
              for (final e in s.items) (site: s, e: e),
          ].where((x) => x.e.isResolved == _decided && (!_mineOnly || x.e.ownerId == me)).toList()
            ..sort((a, b) => a.e.dueDate.compareTo(b.e.dueDate));
          final open = sites.fold<int>(0, (n, s) => n + s.items.where((e) => !e.isResolved).length);
          final overdue = sites.fold<int>(0, (n, s) => n + s.items.where((e) => e.isOverdue(now)).length);
          return RefreshIndicator(
            onRefresh: () => ref.refresh(companyExceptionsProvider(widget.companyId).future),
            child: ListView(padding: const EdgeInsets.all(12), children: [
              Text(
                trf('{open} open across {sites} sites, {late} overdue',
                    {'open': open, 'sites': sites.where((s) => s.items.isNotEmpty).length, 'late': overdue}),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                ChoiceChip(label: Text(tr('Open')), selected: !_decided, onSelected: (_) => setState(() => _decided = false)),
                ChoiceChip(label: Text(tr('Decided here')), selected: _decided, onSelected: (_) => setState(() => _decided = true)),
                FilterChip(label: Text(tr('Mine')), selected: _mineOnly, onSelected: (v) => setState(() => _mineOnly = v)),
              ]),
              const SizedBox(height: 8),
              if (all.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_decided
                      ? tr('Nothing decided here yet.')
                      : tr('Nothing needs a commercial decision. Claims beyond their order, variations waiting, late '
                          'certifications and budget lines heading over show up here.')),
                ),
              for (final x in all) _ExceptionCard(site: x.site, e: x.e, names: names, now: now, companyId: widget.companyId),
            ]),
          );
        },
      ),
    );
  }
}

class _ExceptionCard extends ConsumerWidget {
  const _ExceptionCard({required this.site, required this.e, required this.names, required this.now, required this.companyId});
  final SiteExceptions site;
  final CommercialException e;
  final Map<String, String> names;
  final DateTime now;
  final String companyId;

  String _owner() {
    if (e.ownerId != null) return names[e.ownerId] ?? tr('Someone on the team');
    return e.defaultOwnerRole == 'engineer' ? tr('Site engineer') : tr('Project manager');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final late = e.isOverdue(now);
    final session = ref.watch(sessionProvider);
    final canResolve = Roles.canApprove(session.role);
    final canAct = session.role != null && Roles.canWrite(session.role!);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(exceptionKindLabel(e.kind), style: theme.textTheme.labelLarge)),
            StatusPill(
              e.isResolved
                  ? tr('Decided')
                  : late
                      ? trf('Overdue since {date}', {'date': fmtDate(e.dueDate, short: true)})
                      : trf('Due {date}', {'date': fmtDate(e.dueDate, short: true)}),
              tone: e.isResolved ? PillTone.ok : (late ? PillTone.danger : PillTone.warn),
            ),
          ]),
          const SizedBox(height: 4),
          Text(e.title, style: theme.textTheme.titleSmall),
          Text('${site.project.name} · ${e.detail}', style: theme.textTheme.bodySmall),
          if (e.amount != null && e.amount! > 0) Text(rupees(e.amount!), style: theme.textTheme.bodySmall),
          Text(trf('Owner: {who}', {'who': _owner()}), style: theme.textTheme.bodySmall),
          if (e.resolution != null)
            Text(
              trf('Decided by {who} on {date}: "{note}"', {
                'who': names[e.resolution!.actedBy] ?? tr('Someone on the team'),
                'date': fmtDate(e.resolution!.createdAt),
                'note': e.resolution!.note ?? '',
              }),
              style: theme.textTheme.bodySmall,
            ),
          Wrap(spacing: 4, children: [
            TextButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: Text(tr('Open the record')),
              onPressed: () => _open(context),
            ),
            if (canAct && !e.isResolved && e.ownerId != session.user!.id)
              TextButton(onPressed: () => _assign(ref, ownerId: session.user!.id), child: Text(tr('Take it'))),
            if (canAct && !e.isResolved)
              TextButton(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: e.dueDate.isBefore(now) ? now : e.dueDate,
                    firstDate: now.subtract(const Duration(days: 1)),
                    lastDate: now.add(const Duration(days: 365)),
                  );
                  if (d != null) await _assign(ref, dueOn: _ymd(d));
                },
                child: Text(tr('Change due date')),
              ),
            if (canResolve && !e.isResolved)
              TextButton(onPressed: () => _resolve(context, ref), child: Text(tr('Record a decision'))),
            if (canResolve && e.isResolved)
              TextButton(
                onPressed: () => _act(ref, 'reopened'),
                child: Text(tr('Reopen')),
              ),
          ]),
        ]),
      ),
    );
  }

  void _open(BuildContext context) {
    final p = site.project;
    final route = switch (e.source) {
      ExceptionSource.claim => MaterialPageRoute<void>(
          builder: (_) => WorkOrderScreen(project: p, orderId: site.data.claimById(e.sourceId)!.workOrderId)),
      ExceptionSource.variation => MaterialPageRoute<void>(builder: (_) => VariationScreen(project: p, variationId: e.sourceId)),
      ExceptionSource.costCode => MaterialPageRoute<void>(builder: (_) => CostLineScreen(project: p, costCodeId: e.sourceId)),
    };
    Navigator.of(context).push(route);
  }

  Future<void> _act(WidgetRef ref, String action, {String? ownerId, String? dueOn, String? note}) async {
    await ref.read(appDatabaseProvider).commercialDao.actOnException(
          projectId: site.project.id,
          exceptionKey: e.key,
          action: action,
          by: ref.read(sessionProvider).user!.id,
          ownerId: ownerId,
          dueOn: dueOn,
          note: note,
          fingerprint: action == 'resolved' ? e.fingerprint : null,
        );
    ref.invalidate(companyExceptionsProvider(companyId));
    ref.invalidate(commercialDataProvider(site.project.id));
  }

  Future<void> _assign(WidgetRef ref, {String? ownerId, String? dueOn}) =>
      _act(ref, 'assigned', ownerId: ownerId ?? e.ownerId, dueOn: dueOn);

  Future<void> _resolve(BuildContext context, WidgetRef ref) async {
    final note = await askText(context,
        title: tr('Record a decision'), label: tr('What was decided (e.g. accepted, covered by contingency)'));
    if (note == null || note.isEmpty) return;
    await _act(ref, 'resolved', note: note);
  }
}
