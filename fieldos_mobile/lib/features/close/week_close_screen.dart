/// The weekly close on screen: every site's week on one list, and one
/// site's review queue, where a project manager approves what is payable,
/// sends back what is wrong with a note, closes the week, and sends one pack
/// to accounts. Supervisors see what was sent back to them and mark it
/// fixed.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/close/week_close.dart';
import 'package:fieldos_mobile/features/close/week_close_data.dart';
import 'package:fieldos_mobile/features/close/week_close_pack.dart';
import 'package:fieldos_mobile/features/company/branding.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet.dart' show weekStart;
import 'package:fieldos_mobile/features/money/money_view.dart' show provisionalVouchersProvider;
import 'package:fieldos_mobile/features/shared/photo_viewer.dart';
import 'package:fieldos_mobile/features/tasks/team_roster.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/features/daily/day_close_data.dart' show DayCloseActions;
import 'package:fieldos_mobile/features/daily/week_verification_ui.dart';
import 'package:fieldos_mobile/providers.dart';

/// (projectId, Monday as yyyy-mm-dd)
typedef WeekKey = ({String projectId, String week});

final weekCloseProvider = FutureProvider.autoDispose.family<WeekClose, WeekKey>((ref, k) async {
  final db = ref.watch(appDatabaseProvider);
  final project = await db.projectDao.byId(k.projectId);
  if (project == null) throw StateError('This site is no longer on the phone.');
  final unconfirmed = await ref.watch(provisionalVouchersProvider(k.projectId).future);
  return loadWeekClose(db, project, DateTime.parse(k.week), unconfirmedVouchers: unconfirmed);
});

/// Every running site's week, for the list.
final companyWeekCloseProvider =
    FutureProvider.autoDispose.family<List<WeekClose>, ({String companyId, String week})>((ref, k) async {
  final db = ref.watch(appDatabaseProvider);
  final sites = (await db.projectDao.forCompany(k.companyId)).where((p) => p.status == 'active');
  final out = [for (final p in sites) await loadWeekClose(db, p, DateTime.parse(k.week))];
  // The sites that need someone first.
  out.sort((a, b) {
    int weight(WeekClose w) => w.isClosed && !w.changedSinceClose ? 0 : w.waiting.length + w.sentBack.length * 2;
    final c = weight(b).compareTo(weight(a));
    return c != 0 ? c : a.project.name.toLowerCase().compareTo(b.project.name.toLowerCase());
  });
  return out;
});

/// People's names for the history: this phone's accounts and the team.
final closeNamesProvider = FutureProvider.autoDispose.family<Map<String, String>, String>((ref, companyId) async {
  final db = ref.watch(appDatabaseProvider);
  final roster = await ref.watch(teamRosterProvider(companyId).future);
  return {
    for (final m in roster.members) m.userId: memberLabel(m),
    for (final u in await db.select(db.users).get()) u.id: u.name,
  };
});

String _key(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String weekRangeLabel(DateTime from) => trf('{from} to {to}',
    {'from': fmtDate(from, short: true), 'to': fmtDate(from.add(const Duration(days: 6)), short: true)});

/// The week's state in a few words, with how worried to be.
(String, PillTone) weekStatus(WeekClose w) {
  if (w.changedSinceClose) return (tr('Changed since close'), PillTone.danger);
  if (w.isClosed) return (tr('Closed'), PillTone.ok);
  if (w.items.isEmpty) return (tr('Nothing recorded'), PillTone.neutral);
  if (w.canClose) return (tr('Ready to close'), PillTone.ok);
  if (w.sentBack.isNotEmpty) {
    return (trf('{n} sent back', {'n': w.sentBack.length}), PillTone.warn);
  }
  return (trf('{n} to review', {'n': w.waiting.length}), PillTone.warn);
}

class _WeekPicker extends StatelessWidget {
  const _WeekPicker({required this.from, required this.onChange});
  final DateTime from;
  final ValueChanged<DateTime> onChange;

  @override
  Widget build(BuildContext context) {
    final thisWeek = weekStart(DateTime.now());
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      IconButton(
        tooltip: tr('Previous week'),
        icon: const Icon(Icons.chevron_left),
        onPressed: () => onChange(from.subtract(const Duration(days: 7))),
      ),
      Flexible(
        child: Text(from == thisWeek ? '${tr('This week')} · ${weekRangeLabel(from)}' : weekRangeLabel(from),
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleSmall),
      ),
      IconButton(
        tooltip: tr('Next week'),
        icon: const Icon(Icons.chevron_right),
        onPressed: from.isBefore(thisWeek) ? () => onChange(from.add(const Duration(days: 7))) : null,
      ),
    ]);
  }
}

/// Every running site's week: what is waiting, sent back or closed.
class WeeklyCloseListScreen extends ConsumerStatefulWidget {
  const WeeklyCloseListScreen({super.key, required this.companyId});
  final String companyId;

  @override
  ConsumerState<WeeklyCloseListScreen> createState() => _WeeklyCloseListScreenState();
}

class _WeeklyCloseListScreenState extends ConsumerState<WeeklyCloseListScreen> {
  // Most closes happen on Saturday or the Monday after, so a Monday or
  // Tuesday opens on last week.
  late DateTime _from = () {
    final now = DateTime.now();
    final monday = weekStart(now);
    return now.weekday <= DateTime.tuesday ? monday.subtract(const Duration(days: 7)) : monday;
  }();

  @override
  Widget build(BuildContext context) {
    final k = (companyId: widget.companyId, week: _key(_from));
    final weeks = ref.watch(companyWeekCloseProvider(k));
    return Scaffold(
      appBar: AppBar(title: Text(tr('Weekly close'))),
      body: Column(children: [
        _WeekPicker(from: _from, onChange: (d) => setState(() => _from = d)),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(companyWeekCloseProvider(k).future),
            child: weeks.when(
              data: (list) => list.isEmpty
                  ? ListView(children: [
                      EmptyState(
                        icon: Icons.fact_check_outlined,
                        title: tr('No running sites'),
                        message: tr('Each running site gets a weekly close here: wages, expenses and deliveries to approve.'),
                      ),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final w = list[i];
                        final (label, tone) = weekStatus(w);
                        return Card(
                          child: ListTile(
                            title: Text(w.project.name),
                            subtitle: Text([
                              trf('Wages {amount}', {'amount': rupees(w.wagesEarned)}),
                              trf('Expenses {amount}', {'amount': rupees(w.expensesTotal)}),
                              if (w.flagged.isNotEmpty) trf('{n} exceptions', {'n': w.flagged.length}),
                            ].join(' · ')),
                            trailing: StatusPill(label, tone: tone),
                            onTap: () async {
                              await Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => WeekCloseScreen(project: w.project, weekOf: w.from),
                              ));
                              ref.invalidate(companyWeekCloseProvider(k));
                            },
                          ),
                        );
                      },
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => ErrorState(error: e, stack: st, onRetry: () => ref.invalidate(companyWeekCloseProvider(k))),
            ),
          ),
        ),
      ]),
    );
  }
}

enum _Show { review, sentBack, approved, all }

/// One site's week.
class WeekCloseScreen extends ConsumerStatefulWidget {
  const WeekCloseScreen({super.key, required this.project, required this.weekOf});
  final Project project;
  final DateTime weekOf;

  @override
  ConsumerState<WeekCloseScreen> createState() => _WeekCloseScreenState();
}

class _WeekCloseScreenState extends ConsumerState<WeekCloseScreen> {
  late DateTime _from = weekStart(widget.weekOf);
  _Show _show = _Show.review;
  bool _busy = false;

  WeekKey get _k => (projectId: widget.project.id, week: _key(_from));

  CloseActions _actions() {
    final s = ref.read(sessionProvider);
    return CloseActions(ref.read(appDatabaseProvider), userId: s.user?.id ?? '', role: s.role ?? Roles.viewer);
  }

  Future<void> _run(Future<void> Function() job, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
      ref.invalidate(weekCloseProvider(_k));
      if (mounted && done != null) showSnack(context, done);
    } catch (e, st) {
      if (mounted) showSnack(context, friendlyError(e, st), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askNote({required String title, required String label, bool required = true}) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: c,
            autofocus: true,
            maxLength: 300,
            maxLines: 3,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => set(() {}),
            decoration: InputDecoration(labelText: label, counterText: ''),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(
              onPressed: required && c.text.trim().isEmpty ? null : () => Navigator.pop(ctx, true),
              child: Text(tr('Save')),
            ),
          ],
        ),
      ),
    );
    final text = c.text.trim();
    c.dispose();
    return ok == true ? text : null;
  }

  Future<void> _approve(WeekClose w, CloseItem i) async {
    // Money for days with no submitted daily report is held: the verified
    // part can go ahead, and approving the rest needs a recorded reason.
    final v = ref.read(weekVerificationProvider(_k)).value;
    if (isHeld(v, i)) {
      final choice = await askHeldApproval(context, v!, i);
      if (choice == null) return;
      final s = ref.read(sessionProvider);
      final day = DayCloseActions(ref.read(appDatabaseProvider), userId: s.user?.id ?? '', role: s.role ?? Roles.viewer);
      await _run(() async {
        if (choice.$1 == HeldChoice.releaseVerified) {
          await day.releaseVerified(v, i);
        } else {
          await day.overrideAndApprove(v, i, choice.$2!);
        }
        ref.invalidate(weekVerificationProvider(_k));
      }, done: choice.$1 == HeldChoice.releaseVerified ? tr('Verified part released') : tr('Approved'));
      return;
    }
    double? accepted;
    if (i.kind == CloseKind.receipt) {
      final c = TextEditingController(text: fmtQty(i.quantity ?? 0));
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Approve this delivery')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(i.title),
            if (i.orderedQty != null)
              Text(trf('ordered {qty}', {'qty': [fmtQty(i.orderedQty!), i.unit].where((s) => s.isNotEmpty).join(' ')}),
                  style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 8),
            TextField(
              controller: c,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: tr('Quantity accepted'),
                helperText: tr('Less than received if some was short or damaged.'),
                suffixText: i.unit,
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Approve'))),
          ],
        ),
      );
      accepted = double.tryParse(c.text.trim().replaceAll(',', ''));
      c.dispose();
      if (ok != true) return;
      if (accepted == null || accepted < 0) {
        if (mounted) showSnack(context, tr('Enter the quantity accepted.'), error: true);
        return;
      }
    }
    String? note;
    if (accepted != null && i.quantity != null && accepted < i.quantity! - 0.0001) {
      note = 'Short ${fmtQty(i.quantity! - accepted)} ${i.unit}'.trim();
    }
    await _run(() => _actions().approve(w, i, acceptedQty: accepted, note: note), done: tr('Approved'));
  }

  Future<void> _sendBack(WeekClose w, CloseItem i) async {
    final note = await _askNote(title: tr('Send back to the site'), label: tr('What needs fixing?'));
    if (note == null) return;
    await _run(() => _actions().sendBack(w, i, note), done: tr('Sent back'));
  }

  Future<void> _markFixed(WeekClose w, CloseItem i) async {
    final note = await _askNote(title: tr('Mark as fixed'), label: tr('What was done? (optional)'), required: false);
    if (note == null) return;
    await _run(() => _actions().markFixed(w, i, note: note.isEmpty ? null : note), done: tr('Marked fixed'));
  }

  Future<void> _close(WeekClose w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Close this week?')),
        content: Text(trf('{n} items approved, {amount} in all. Anything changed later comes back here to review.',
            {'n': w.approved.length, 'amount': rupees(w.approvedTotal)})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Close the week'))),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => _actions().closeWeek(w), done: tr('Week closed'));
  }

  Future<void> _reopen(WeekClose w) async {
    final note = await _askNote(title: tr('Reopen this week?'), label: tr('Why?'));
    if (note == null) return;
    await _run(() => _actions().reopen(w, note), done: tr('Week reopened'));
  }

  Future<void> _sendPack(WeekClose w) async {
    final box = context.findRenderObject() as RenderBox?;
    await _run(() async {
      final db = ref.read(appDatabaseProvider);
      final session = ref.read(sessionProvider);
      final companyId = session.activeCompany?.id ?? widget.project.companyId;
      final names = await ref.read(closeNamesProvider(companyId).future);
      final workers = {for (final x in await db.workerDao.forProject(w.project.id)) x.id: x.name};
      final bytes = await buildWeekClosePack(
        week: w,
        companyName: session.activeCompany?.name ?? '',
        names: names,
        workerNames: workers,
        photos: await packPhotos(db, w),
        branding: await loadBranding(db, companyId),
      );
      final dir = await getTemporaryDirectory();
      final safe = w.project.name.replaceAll(RegExp(r'[^\w\-]+'), '_');
      final pdf = File('${dir.path}/Weekly-close-$safe-${w.weekKey}.pdf')..writeAsBytesSync(bytes);
      final csv = File('${dir.path}/Weekly-close-$safe-${w.weekKey}.csv')..writeAsStringSync(weekCloseCsv(w));
      await SharePlus.instance.share(ShareParams(
        files: [XFile(pdf.path, mimeType: 'application/pdf'), XFile(csv.path, mimeType: 'text/csv')],
        subject: 'Weekly close: ${w.project.name}, ${w.weekKey}',
        text: '${w.project.name} weekly close, ${w.weekKey}. ${packStatusLine(w, names: names)}.',
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ));
    });
  }

  void _showHistory(WeekClose w, Map<String, String> names) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (ctx, scroll) => w.history.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(tr('No decisions yet this week.')),
              )
            : ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  Text(tr('History'), style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final r in w.history.reversed)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_decisionIcon(r.decision)),
                      title: Text('${decisionLabel(r.decision)} · ${_historyItem(w, r)}'),
                      subtitle: Text([
                        '${names[r.decidedBy] ?? tr('Someone on the team')} · ${fmtDateTime(r.createdAt)}',
                        if (r.acceptedQty != null && r.itemKind == 'receipt')
                          trf('{qty} accepted', {'qty': fmtQty(r.acceptedQty!)}),
                        if ((r.note ?? '').trim().isNotEmpty) '"${r.note!.trim()}"',
                      ].join('\n')),
                    ),
                ],
              ),
      ),
    );
  }

  String _historyItem(WeekClose w, CloseReview r) {
    if (r.itemKind == 'week') return tr('Week');
    for (final i in w.items) {
      if (i.kind.key == r.itemKind && i.id == r.itemId) return i.title;
    }
    return tr('A removed entry');
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final canDecide = Roles.canApprove(session.role);
    final canFix = Roles.canWrite(session.role ?? Roles.viewer);
    final week = ref.watch(weekCloseProvider(_k));
    final names = ref.watch(closeNamesProvider(session.activeCompany?.id ?? widget.project.companyId)).value ?? const {};
    final verification = ref.watch(weekVerificationProvider(_k)).value;

    return Scaffold(
      appBar: AppBar(
        title: Text('${tr('Weekly close')} · ${widget.project.name}'),
        actions: [
          if (week.value != null)
            IconButton(
              tooltip: tr('History'),
              icon: const Icon(Icons.history),
              onPressed: () => _showHistory(week.value!, names),
            ),
          if (week.value != null)
            IconButton(
              tooltip: tr('Send the pack to accounts'),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: _busy ? null : () => _sendPack(week.value!),
            ),
        ],
      ),
      body: Column(children: [
        _WeekPicker(from: _from, onChange: (d) => setState(() => _from = d)),
        Expanded(
          child: week.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => ErrorState(error: e, stack: st, onRetry: () => ref.invalidate(weekCloseProvider(_k))),
            data: (w) {
              final shown = switch (_show) {
                _Show.review => w.waiting,
                _Show.sentBack => w.sentBack,
                _Show.approved => w.approved,
                _Show.all => w.items,
              };
              return RefreshIndicator(
                onRefresh: () => ref.refresh(weekCloseProvider(_k).future),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  children: [
                    _Summary(week: w, names: names),
                    if (!canDecide)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                        child: FormMessage(
                            tr('The owner or a project manager approves the week. Fix what is sent back to you and mark it fixed.'),
                            error: false),
                      ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final (s, label, n) in [
                          (_Show.review, tr('To review'), w.waiting.length),
                          (_Show.sentBack, tr('Sent back'), w.sentBack.length),
                          (_Show.approved, tr('Approved'), w.approved.length),
                          (_Show.all, tr('All'), w.items.length),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text('$label ($n)'),
                              selected: _show == s,
                              onSelected: (_) => setState(() => _show = s),
                            ),
                          ),
                      ]),
                    ),
                    if (canDecide &&
                        _show == _Show.review &&
                        w.waiting.any((i) => !i.hasFlags && !isHeld(verification, i)))
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.done_all),
                          label: Text(trf('Approve the {n} with no exceptions',
                              {'n': w.waiting.where((i) => !i.hasFlags && !isHeld(verification, i)).length})),
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                    // Held money (no daily report) is not "no exceptions".
                                    final v = ref.read(weekVerificationProvider(_k)).value;
                                    for (final i in w.waiting.where((i) => !i.hasFlags && !isHeld(v, i))) {
                                      await _actions().approve(w, i);
                                    }
                                  }, done: tr('Approved')),
                        ),
                      ),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          switch (_show) {
                            _Show.review => w.items.isEmpty
                                ? tr('Nothing was recorded on this site this week.')
                                : tr('Nothing left to review.'),
                            _Show.sentBack => tr('Nothing sent back.'),
                            _Show.approved => tr('Nothing approved yet.'),
                            _Show.all => tr('Nothing was recorded on this site this week.'),
                          },
                          textAlign: TextAlign.center,
                        ),
                      ),
                    for (final kind in CloseKind.values) ...[
                      if (shown.any((i) => i.kind == kind)) SectionHeader(kindLabel(kind)),
                      for (final i in shown.where((i) => i.kind == kind))
                        _ItemCard(
                          item: i,
                          names: names,
                          busy: _busy,
                          onApprove: canDecide && i.state != ItemState.approved ? () => _approve(w, i) : null,
                          onSendBack: canDecide && i.state != ItemState.sentBack ? () => _sendBack(w, i) : null,
                          onFixed: canFix && i.state == ItemState.sentBack ? () => _markFixed(w, i) : null,
                          onEvidence: i.evidence > 0 ? () => _openEvidence(i) : null,
                          extra: VerificationNote(v: verification, item: i, names: names),
                        ),
                    ],
                    const SizedBox(height: 12),
                    if (canDecide && !w.isClosed)
                      FilledButton.icon(
                        icon: const Icon(Icons.lock_outline),
                        label: Text(tr('Close the week')),
                        onPressed: w.canClose && !_busy && w.items.isNotEmpty ? () => _close(w) : null,
                      ),
                    if (canDecide && !w.isClosed && !w.canClose && w.items.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(tr('Approve everything, and get back what was sent back, to close the week.'),
                            textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                      ),
                    if (canDecide && w.isClosed)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.lock_open),
                        label: Text(tr('Reopen the week')),
                        onPressed: _busy ? null : () => _reopen(w),
                      ),
                    if (canDecide && w.changedSinceClose && w.canClose)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: FilledButton(onPressed: _busy ? null : () => _close(w), child: Text(tr('Close the week again'))),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  Future<void> _openEvidence(CloseItem i) async {
    final db = ref.read(appDatabaseProvider);
    final paths = i.kind == CloseKind.receipt
        ? [for (final a in await db.materialDao.slipsFor(i.id)) a.filePath]
        : [for (final a in await db.expenseDao.attachmentsFor(i.id)) a.filePath];
    final existing = paths.where((p) => File(p).existsSync()).toList();
    if (!mounted) return;
    if (existing.isEmpty) {
      showSnack(context, tr('The photo has not reached this phone yet. Sync and try again.'));
      return;
    }
    await showPhotoViewer(context, existing, shareText: i.title);
  }
}

IconData _decisionIcon(String d) => switch (d) {
      'approved' => Icons.check_circle_outline,
      'sent_back' => Icons.reply,
      'fixed' => Icons.build_circle_outlined,
      'closed' => Icons.lock_outline,
      'reopened' => Icons.lock_open,
      _ => Icons.circle_outlined,
    };

class _Summary extends StatelessWidget {
  const _Summary({required this.week, required this.names});
  final WeekClose week;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final w = week;
    final theme = Theme.of(context);
    final (label, tone) = weekStatus(w);
    final d = w.weekDecision;
    Widget fact(String l, double v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(l, style: theme.textTheme.bodyMedium)),
            Text(rupees(v), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(tr('This week on site'), style: theme.textTheme.titleMedium)),
            StatusPill(label, tone: tone),
          ]),
          if (w.isClosed && d != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  trf('Closed by {who}, {when}', {
                    'who': names[d.decidedBy] ?? tr('Someone on the team'),
                    'when': fmtDateTime(d.createdAt),
                  }),
                  style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 8),
          fact(tr('Wages earned'), w.wagesEarned),
          fact(tr('Wages and advances paid'), w.wagesPaid),
          fact(tr('Wages still due'), w.wagesDue),
          if (w.advancesOut > 0) fact(tr('Advances not worked off'), w.advancesOut),
          fact(tr('Site expenses'), w.expensesTotal),
          fact(tr('Material delivered'), w.receiptsTotal),
          if (w.flagged.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(trf('{n} items need a closer look', {'n': w.flagged.length}),
                  style: theme.textTheme.bodySmall?.copyWith(color: toneColor(context, PillTone.warn))),
            ),
        ]),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.names,
    required this.busy,
    this.onApprove,
    this.onSendBack,
    this.onFixed,
    this.onEvidence,
    this.extra,
  });

  /// More about the item (the daily close's held money).
  final Widget? extra;
  final CloseItem item;
  final Map<String, String> names;
  final bool busy;
  final VoidCallback? onApprove;
  final VoidCallback? onSendBack;
  final VoidCallback? onFixed;
  final VoidCallback? onEvidence;

  @override
  Widget build(BuildContext context) {
    final i = item;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final tone = switch (i.state) {
      ItemState.approved => PillTone.ok,
      ItemState.sentBack => PillTone.warn,
      ItemState.changed || ItemState.fixed => PillTone.danger,
      ItemState.waiting => PillTone.neutral,
    };
    final last = i.last;
    final accepted = i.acceptedQty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Text(i.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                      decoration: i.expense?.voided == true ? TextDecoration.lineThrough : null)),
            ),
            if (i.amount != null && i.kind != CloseKind.attendance)
              Padding(
                padding: const EdgeInsets.only(left: 8, right: 8),
                child: Text(rupees(i.amount!), style: theme.textTheme.titleSmall),
              ),
          ]),
          if (i.detail.isNotEmpty) Text(i.detail, style: muted),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: [
            StatusPill(stateLabel(i.state), tone: tone),
            if (accepted != null && i.quantity != null && accepted < i.quantity! - 0.0001)
              StatusPill(trf('{qty} accepted', {'qty': [fmtQty(accepted), i.unit].where((s) => s.isNotEmpty).join(' ')}),
                  tone: PillTone.warn),
          ]),
          for (final f in i.flags)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                Icon(Icons.error_outline, size: 16, color: toneColor(context, PillTone.warn)),
                const SizedBox(width: 6),
                Expanded(child: Text(f.label, style: theme.textTheme.bodySmall)),
              ]),
            ),
          if (last != null && (last.note ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  '${decisionLabel(last.decision)} · ${names[last.decidedBy] ?? tr('Someone on the team')}: "${last.note!.trim()}"',
                  style: muted),
            ),
          ?extra,
          Wrap(alignment: WrapAlignment.end, spacing: 4, children: [
            if (onEvidence != null)
              TextButton.icon(
                onPressed: onEvidence,
                icon: const Icon(Icons.photo_outlined, size: 18),
                label: Text(i.kind == CloseKind.receipt ? tr('Slip') : tr('Bill')),
              ),
            if (onFixed != null) TextButton(onPressed: busy ? null : onFixed, child: Text(tr('Mark fixed'))),
            if (onSendBack != null) TextButton(onPressed: busy ? null : onSendBack, child: Text(tr('Send back'))),
            if (onApprove != null) FilledButton.tonal(onPressed: busy ? null : onApprove, child: Text(tr('Approve'))),
          ]),
        ]),
      ),
    );
  }
}
