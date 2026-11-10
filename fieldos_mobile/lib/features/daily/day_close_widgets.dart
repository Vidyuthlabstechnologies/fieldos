/// Pieces shared by Today and the manager's daily reports board.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/close/week_close_screen.dart' show closeNamesProvider;
import 'package:fieldos_mobile/features/daily/day_close.dart';
import 'package:fieldos_mobile/features/daily/day_close_data.dart';
import 'package:fieldos_mobile/features/tasks/team_roster.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

/// Whose phone the manager should look at for a site's day: the person
/// it is expected from, or else whoever sent the site's reports before.
String? reporterFor(SiteRecords r, DateTime day) {
  final named = r.setup.responsibleOn(day);
  if (named != null) return named;
  for (final e in r.events.reversed) {
    if (e.kind == 'submitted') return e.recordedBy;
  }
  return null;
}

/// The day's state in a few words, with how worried to be. On the
/// supervisor's phone [waitingToSync] says the report is saved but not
/// sent yet; on the manager's, [lastSync] says when the supervisor's phone
/// last reached the server, which is all anyone can know until it does.
(String, PillTone) dayStatusText(DayClose d, DateTime now, {bool waitingToSync = false, DateTime? lastSync}) {
  final s = d.submission;
  if (s != null) {
    if (waitingToSync) return (tr('Saved on this phone · waiting to sync'), PillTone.warn);
    if (d.changedSinceSubmit) return (tr('Changed after it was sent'), PillTone.warn);
    if (s.siteClosed) return (tr('Site closed'), PillTone.ok);
    if (d.submittedLate) {
      return (trf('Submitted late · {when}', {'when': fmtDateTime(s.createdAt, now: now)}), PillTone.warn);
    }
    return (trf('Submitted at {time}', {'time': fmtTime(s.createdAt)}), PillTone.ok);
  }
  final synced = lastSync == null ? null : fmtDateTime(lastSync, now: now);
  switch (d.status(now)) {
    case DayStatus.open:
      return (trf('Due by {time}', {'time': fmtTime(d.setup.cutoffOn(d.day))}), PillTone.neutral);
    case DayStatus.notReceived:
      return (
        synced == null ? tr('Report not received') : trf('Report not received · last synced {when}', {'when': synced}),
        PillTone.danger
      );
    case DayStatus.missed:
      return (
        synced == null ? tr('Report missing') : trf('Report missing · last synced {when}', {'when': synced}),
        PillTone.danger
      );
    case DayStatus.submitted:
    case DayStatus.siteClosed:
      return (tr('Submitted'), PillTone.ok);
  }
}

class DayStatusLine extends StatelessWidget {
  const DayStatusLine(
      {super.key,
      required this.day,
      required this.now,
      required this.waitingToSync,
      required this.names,
      required this.sync,
      required this.me,
      this.reporter});
  final DayClose day;
  final DateTime now;
  final bool waitingToSync;
  final Map<String, String> names;
  final Map<String, MemberSyncStatusData> sync;
  final String me;
  final String? reporter;

  @override
  Widget build(BuildContext context) {
    final who = reporter ?? day.setup.responsibleOn(day.day);
    final last = who == null || who == me ? null : sync[who]?.lastSyncedAt;
    final (label, tone) = dayStatusText(day, now, waitingToSync: waitingToSync, lastSync: last);
    final pending = who == null || who == me ? 0 : (sync[who]?.pending ?? 0);
    return Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      StatusPill(label, tone: tone),
      if (who != null && who != me)
        Text(trf('From {who}', {'who': names[who] ?? tr('Someone on the team')}),
            style: Theme.of(context).textTheme.bodySmall),
      if (pending > 0 && day.submission == null)
        Text(trf('{n} changes still on their phone', {'n': pending}), style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

class CheckTile extends StatelessWidget {
  const CheckTile({
    super.key,
    required this.item,
    required this.snapshot,
    required this.marks,
    required this.editable,
    required this.onRecord,
    this.onNothing,
    this.onQuickWork,
  });
  final CheckItem item;
  final DaySnapshot snapshot;
  final NothingMarks marks;
  final bool editable;
  final VoidCallback onRecord;
  final ValueChanged<bool>? onNothing;
  final VoidCallback? onQuickWork;

  String _detail() => switch (item.kind) {
        CheckKind.attendance => item.count == 1 ? tr('1 person') : trf('{n} people', {'n': item.count}),
        CheckKind.deliveries => item.count == 1 ? tr('1 delivery') : trf('{n} deliveries', {'n': item.count}),
        CheckKind.expenses => trf('{n} entries, {amount}', {'n': item.count, 'amount': rupees(item.amount)}),
        CheckKind.work => snapshot.reports.map((r) => r.workSummary.trim()).join(' · '),
      };

  String? _nothingLabel() => switch (item.kind) {
        CheckKind.deliveries => tr('No deliveries'),
        CheckKind.expenses => tr('No expenses'),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (item.state) {
      CheckState.recorded => (Icons.check_circle, toneColor(context, PillTone.ok)),
      CheckState.nothing => (Icons.remove_circle_outline, toneColor(context, PillTone.neutral)),
      CheckState.missing => (Icons.radio_button_unchecked, toneColor(context, PillTone.warn)),
    };
    final nothing = _nothingLabel();
    final subtitle = switch (item.state) {
      CheckState.recorded => _detail(),
      CheckState.nothing => marks.siteClosed ? tr('Site closed') : (nothing ?? tr('Nothing today')),
      CheckState.missing => tr('Not recorded yet'),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(checkLabel(item.kind), style: Theme.of(context).textTheme.titleSmall),
                Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
            if (editable && !marks.siteClosed)
              TextButton(
                onPressed: onRecord,
                child: Text(item.state == CheckState.recorded ? tr('Add more') : tr('Record')),
              ),
          ]),
          if (editable && !marks.siteClosed && (onQuickWork != null || (nothing != null && item.count == 0)))
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Wrap(spacing: 8, children: [
                if (nothing != null && item.count == 0 && onNothing != null)
                  FilterChip(
                    label: Text(nothing),
                    selected: item.state == CheckState.nothing,
                    onSelected: onNothing,
                  ),
                if (onQuickWork != null && item.count == 0)
                  ActionChip(
                    avatar: const Icon(Icons.edit_note, size: 18),
                    label: Text(tr('Type one line')),
                    onPressed: onQuickWork,
                  ),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Asked every time a report came in late, for the two-week pilot: each
/// cause needs a different fix.
class MissReasonCard extends StatelessWidget {
  const MissReasonCard({super.key, required this.onPick});
  final ValueChanged<MissReason> onPick;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Why was this report late?'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(tr('One tap. It tells us whether to fix the reminder, the signal or the typing.'),
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final r in MissReason.values) ActionChip(label: Text(missReasonLabel(r)), onPressed: () => onPick(r)),
            ]),
          ]),
        ),
      );
}

/// The site's cutoff, supervisor and backup supervisor. Owner or PM only.
Future<void> showCloseSetupSheet(BuildContext context,
        {required Project project, required CloseSetup current, bool backupFirst = false}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SetupSheet(project: project, current: current, backupFirst: backupFirst),
    );

class _SetupSheet extends ConsumerStatefulWidget {
  const _SetupSheet({required this.project, required this.current, required this.backupFirst});
  final Project project;
  final CloseSetup current;
  final bool backupFirst;

  @override
  ConsumerState<_SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends ConsumerState<_SetupSheet> {
  late int _cutoff = widget.current.cutoffMinutes;
  late String? _supervisor = widget.current.supervisorId;
  late String? _backup = widget.current.backupId;
  late DateTime? _until = widget.current.backupUntil;

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(teamRosterProvider(widget.project.companyId)).value;
    final names = ref.watch(closeNamesProvider(widget.project.companyId)).value ?? const {};
    final me = ref.watch(sessionProvider).user!.id;
    // The roster names this phone's own account by its cloud id; records
    // made on this phone carry the local id (sync swaps them).
    final people = <String, String>{
      me: tr('Me'),
      for (final m in roster?.members ?? const [])
        if (m.userId != roster?.myUserId) m.userId: memberLabel(m),
    };
    for (final id in [_supervisor, _backup]) {
      if (id != null && !people.containsKey(id)) people[id] = names[id] ?? tr('Someone on the team');
    }
    final time = TimeOfDay(hour: _cutoff ~/ 60, minute: _cutoff % 60);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Daily report setup'), style: Theme.of(context).textTheme.titleLarge),
        Text(widget.project.name, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule),
          title: Text(tr('Report due by')),
          trailing: Text(time.format(context)),
          onTap: () async {
            final t = await showTimePicker(context: context, initialTime: time);
            if (t != null) setState(() => _cutoff = t.hour * 60 + t.minute);
          },
        ),
        DropdownButtonFormField<String?>(
          initialValue: _supervisor,
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('Site supervisor')),
          items: [
            DropdownMenuItem(value: null, child: Text(tr('Anyone on the site'))),
            for (final e in people.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => setState(() => _supervisor = v),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          initialValue: _backup,
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('Backup supervisor')),
          items: [
            DropdownMenuItem(value: null, child: Text(tr('None'))),
            for (final e in people.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => setState(() => _backup = v),
        ),
        if (_backup != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(tr('Covers until')),
            trailing: Text(_until == null ? tr('Until I change it') : fmtDate(_until!, short: true)),
            onTap: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                  context: context,
                  initialDate: _until ?? now,
                  firstDate: dayOf(now),
                  lastDate: now.add(const Duration(days: 90)));
              setState(() => _until = d == null ? null : dayOf(d));
            },
          ),
        if (roster == null || roster.members.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(tr('Turn on Team & sync to pick teammates.'), style: Theme.of(context).textTheme.bodySmall),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            final s = ref.read(sessionProvider);
            try {
              await DayCloseActions(ref.read(appDatabaseProvider), userId: s.user!.id, role: s.role ?? 'viewer').saveSetup(
                  widget.project.id,
                  CloseSetup(cutoffMinutes: _cutoff, supervisorId: _supervisor, backupId: _backup, backupUntil: _until));
              if (context.mounted) Navigator.of(context).pop();
            } catch (e, st) {
              if (context.mounted) showSnack(context, friendlyError(e, st), error: true);
            }
          },
          child: Text(tr('Save')),
        ),
      ]),
    );
  }
}
