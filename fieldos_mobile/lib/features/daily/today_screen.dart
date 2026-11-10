/// Today: the supervisor's daily site close. Pulls in the attendance,
/// deliveries, expenses and work report already recorded, lets a quiet day
/// be closed in seconds ("No deliveries", "No expenses", "Site closed"),
/// and writes the WhatsApp report they send anyway. The same screen, for a
/// manager, shows whether the report was received and when the
/// supervisor's phone last synced, with follow-up and backup actions.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/close/week_close_screen.dart' show closeNamesProvider;
import 'package:fieldos_mobile/features/commercial/commercial_widgets.dart' show askText;
import 'package:fieldos_mobile/features/daily/day_close.dart';
import 'package:fieldos_mobile/features/daily/day_close_data.dart';
import 'package:fieldos_mobile/features/daily/day_close_widgets.dart';
import 'package:fieldos_mobile/features/project/project_detail_screen.dart';
import 'package:fieldos_mobile/features/reminders/reminders.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

/// Opens the day's close for [project] ([day] defaults to today).
Future<void> openToday(BuildContext context, Project project, {DateTime? day}) => Navigator.of(context)
    .push(MaterialPageRoute<void>(builder: (_) => TodayScreen(project: project, day: day ?? DateTime.now())));

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key, required this.project, required this.day});
  final Project project;
  final DateTime day;

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  late DateTime _day = dayOf(widget.day);
  bool? _siteClosed;
  bool? _noDeliveries;
  bool? _noExpenses;
  bool _busy = false;

  void _refresh() {
    ref.invalidate(siteRecordsProvider(widget.project.id));
    ref.invalidate(dayBoardProvider(widget.project.companyId));
  }

  NothingMarks _marks(DayClose d) => NothingMarks(
        siteClosed: _siteClosed ?? d.marks.siteClosed,
        noDeliveries: _noDeliveries ?? d.marks.noDeliveries,
        noExpenses: _noExpenses ?? d.marks.noExpenses,
      );

  DayCloseActions _actions() {
    final s = ref.read(sessionProvider);
    return DayCloseActions(ref.read(appDatabaseProvider), userId: s.user!.id, role: s.role ?? 'viewer');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(siteRecordsProvider(widget.project.id));
    final names = ref.watch(closeNamesProvider(widget.project.companyId)).value ?? const {};
    final sync = ref.watch(memberSyncProvider(widget.project.companyId)).value ?? const {};
    final session = ref.watch(sessionProvider);
    final isToday = _day == dayOf(DateTime.now());
    return Scaffold(
      appBar: AppBar(
        title: Text(isToday ? tr('Today') : fmtDate(_day, short: true)),
        actions: [
          IconButton(
            tooltip: tr('Close an earlier day'),
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: _day,
                firstDate: now.subtract(const Duration(days: 60)),
                lastDate: now,
              );
              if (d != null) {
                setState(() {
                  _day = dayOf(d);
                  _siteClosed = _noDeliveries = _noExpenses = null;
                });
              }
            },
          ),
          if (_actions().canManage)
            IconButton(
              tooltip: tr('Cutoff and supervisors'),
              icon: const Icon(Icons.tune),
              onPressed: () async {
                final r = await ref.read(siteRecordsProvider(widget.project.id).future);
                if (!context.mounted) return;
                await showCloseSetupSheet(context, project: widget.project, current: r.setup);
                _refresh();
              },
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st, onRetry: _refresh),
        data: (records) {
          final d = records.day(_day);
          return FutureBuilder<bool>(
            future: d.submission == null
                ? Future.value(false)
                : ref.read(appDatabaseProvider).dayCloseDao.isWaitingToSync(d.submission!.id),
            builder: (context, waiting) => _body(context, records, d, names, sync, session.user!.id,
                waitingToSync: waiting.data ?? false),
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, SiteRecords records, DayClose d, Map<String, String> names,
      Map<String, MemberSyncStatusData> sync, String me, {required bool waitingToSync}) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final actions = _actions();
    final marks = _marks(d);
    final items = checklist(d.snapshot, marks);
    final missing = [for (final i in items) if (i.state == CheckState.missing) i.kind];
    final sent = d.isSubmitted;
    final editable = actions.canRecord && !sent;
    String who(String id) => id == me ? tr('you') : (names[id] ?? tr('Someone on the team'));

    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
      Text(widget.project.name, style: theme.textTheme.titleLarge),
      const SizedBox(height: 4),
      DayStatusLine(day: d, now: now, waitingToSync: waitingToSync, names: names, sync: sync, me: me),
      if (d.changedSinceSubmit) ...[
        const SizedBox(height: 8),
        FormMessage(tr('Something for this day changed after it was sent. Reopen and send it again.'), error: true),
      ],
      if (!sent && missing.isNotEmpty && actions.canRecord) ...[
        const SizedBox(height: 8),
        Text(
          trf('Still to do: {items}', {'items': missing.map(checkLabel).join(', ')}),
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
      const SizedBox(height: 12),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('Site closed today')),
        subtitle: Text(tr('No work, holiday, rain or a strike: nothing else to fill in.')),
        value: marks.siteClosed,
        onChanged: editable ? (v) => setState(() => _siteClosed = v) : null,
      ),
      for (final i in items)
        CheckTile(
          item: i,
          snapshot: d.snapshot,
          marks: marks,
          editable: editable,
          onNothing: i.kind == CheckKind.deliveries
              ? (v) => setState(() => _noDeliveries = v)
              : i.kind == CheckKind.expenses
                  ? (v) => setState(() => _noExpenses = v)
                  : null,
          onRecord: () => _record(i.kind),
          onQuickWork: i.kind == CheckKind.work && editable ? () => _quickWork(d) : null,
        ),
      if (d.snapshot.backdated.isNotEmpty) ...[
        const SectionHeader('Added later'),
        for (final e in d.snapshot.backdated)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history),
            title: Text('${checkLabel(e.kind)} · ${e.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(trf('Work date {work} · entered {entered} by {who}', {
              'work': fmtDate(e.workDay, short: true),
              'entered': fmtDateTime(e.enteredAt),
              'who': who(e.by),
            })),
          ),
      ],
      const SizedBox(height: 16),
      if (actions.canRecord && !sent)
        FilledButton.icon(
          icon: const Icon(Icons.send),
          label: Text(_day == dayOf(now) ? tr("Send today's report") : tr("Send this day's report")),
          onPressed: missing.isEmpty && !_busy ? () => _submit(d, marks) : null,
        ),
      if (sent && d.submission != null)
        Text(
          trf('Sent by {who} on {date}', {'who': who(d.submission!.recordedBy), 'date': fmtDateTime(d.submission!.createdAt)}),
          style: theme.textTheme.bodySmall,
        ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.share_outlined),
        label: Text(tr('Share the report on WhatsApp')),
        onPressed: () => _share(d, marks, records),
      ),
      if (sent && actions.canRecord)
        TextButton.icon(
          icon: const Icon(Icons.edit_outlined),
          label: Text(tr('Reopen to correct')),
          onPressed: _busy ? null : () => _reopen(d),
        ),
      if (actions.canRecord && (d.wasMissed(now) || d.submittedLate) && d.missReasons.isEmpty)
        MissReasonCard(onPick: (r) => _missReason(d, r)),
      for (final m in d.missReasons)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.info_outline),
          title: Text(trf('Why it was late: {reason}', {
            'reason': [missReasonLabel(MissReasonKey.parse(m.reason) ?? MissReason.other), m.note ?? '']
                .where((s) => s.isNotEmpty)
                .join(' · ')
          })),
          subtitle: Text('${who(m.recordedBy)}, ${fmtDateTime(m.createdAt)}'),
        ),
      for (final f in d.followUps)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.phone_callback_outlined),
          title: Text(trf('Followed up: {note}', {'note': f.note ?? ''})),
          subtitle: Text('${who(f.recordedBy)}, ${fmtDateTime(f.createdAt)}'),
        ),
      if (actions.canManage && !sent && d.status(now) != DayStatus.open)
        Wrap(spacing: 8, children: [
          TextButton.icon(
            icon: const Icon(Icons.phone_callback_outlined),
            label: Text(tr('Record a follow-up')),
            onPressed: () => _followUp(d),
          ),
          TextButton.icon(
            icon: const Icon(Icons.person_add_alt),
            label: Text(tr('Assign a backup supervisor')),
            onPressed: () async {
              await showCloseSetupSheet(context, project: widget.project, current: records.setup, backupFirst: true);
              _refresh();
            },
          ),
        ]),
    ]);
  }

  void _record(CheckKind k) {
    final tab = switch (k) {
      CheckKind.attendance => 5,
      CheckKind.deliveries => 4,
      CheckKind.expenses => 6,
      CheckKind.work => 1,
    };
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => ProjectDetailScreen(project: widget.project, initialTab: tab)))
        .then((_) => _refresh());
  }

  Future<void> _quickWork(DayClose d) async {
    final text = await askText(context, title: tr('Work done'), label: tr('What was done on site'));
    if (text == null || text.isEmpty) return;
    final user = ref.read(sessionProvider).user!;
    final now = DateTime.now();
    final at = _day == dayOf(now) ? now : _day.add(const Duration(hours: 18));
    await ref.read(appDatabaseProvider).dprDao.create(DprEntriesCompanion.insert(
          id: const Uuid().v4(),
          projectId: widget.project.id,
          createdBy: user.id,
          entryDate: at,
          workSummary: text,
          manpowerCount: Value(d.snapshot.people.length),
        ));
    _refresh();
  }

  Future<void> _submit(DayClose d, NothingMarks marks) async {
    setState(() => _busy = true);
    try {
      final db = ref.read(appDatabaseProvider);
      final weekClosed = await weekAlreadyClosed(db, widget.project, _day);
      await _actions().submit(d, marks);
      await ref.read(reminderSchedulerProvider).refresh();
      _refresh();
      if (!mounted) return;
      showSnack(
          context,
          weekClosed
              ? tr('Sent. That week is already closed, so the manager will review the change.')
              : tr('Sent. Now share it on WhatsApp.'));
      final records = await ref.read(siteRecordsProvider(widget.project.id).future);
      if (mounted) await _share(records.day(_day), marks, records);
    } catch (e, st) {
      if (mounted) showSnack(context, friendlyError(e, st), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(DayClose d, NothingMarks marks, SiteRecords records) =>
      SharePlus.instance.share(ShareParams(text: whatsAppReport(d.snapshot, marks, issues: records.issues)));

  Future<void> _reopen(DayClose d) async {
    final note = await askText(context, title: tr('Reopen to correct'), label: tr('What needs correcting (optional)'));
    if (note == null) return;
    await _actions().reopen(d, note: note);
    setState(() => _siteClosed = _noDeliveries = _noExpenses = null);
    _refresh();
  }

  Future<void> _missReason(DayClose d, MissReason r) async {
    String? note;
    if (r == MissReason.other) {
      note = await askText(context, title: tr('Something else'), label: tr('What happened'));
      if (note == null || note.isEmpty) return;
    }
    await _actions().recordMissReason(d, r, note: note);
    _refresh();
    if (mounted) showSnack(context, tr('Thanks. This helps fix the real cause.'));
  }

  Future<void> _followUp(DayClose d) async {
    final note = await askText(context, title: tr('Record a follow-up'), label: tr('What you did (e.g. called, he will send by 10)'));
    if (note == null || note.isEmpty) return;
    await _actions().followUp(d, note);
    _refresh();
  }
}
