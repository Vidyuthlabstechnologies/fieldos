/// One site's execution screen (FOS-205 to FOS-208): the two-week lookahead
/// with what each task waits for, the drawing register, RFIs, quality hold
/// points and defects, and handover by unit.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/close/week_close_screen.dart' show closeNamesProvider;
import 'package:fieldos_mobile/features/commercial/commercial_widgets.dart' show askText, KeyValue;
import 'package:fieldos_mobile/features/execution/execution_data.dart';
import 'package:fieldos_mobile/features/execution/execution_rules.dart';
import 'package:fieldos_mobile/features/shared/photo_capture.dart';
import 'package:fieldos_mobile/features/shared/photo_viewer.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

/// Who is using the screen, and what they may do. The server refuses the
/// same things (site_execution_guard).
class _Me {
  _Me(this.userId, this.role);
  final String userId;
  final String? role;
  bool get canDecide => Roles.canApprove(role);
  bool get canWrite => role != null && Roles.canWrite(role!);
}

_Me _me(WidgetRef ref) {
  final s = ref.read(sessionProvider);
  return _Me(s.user!.id, s.role);
}

String _who(Map<String, String> names, String? id) =>
    id == null ? tr('Someone on the team') : names[id] ?? tr('Someone on the team');

/// Runs a write, refreshes the screen and shows a refusal as a message.
Future<bool> _act(BuildContext context, WidgetRef ref, String projectId, Future<void> Function() run, {String? done}) async {
  try {
    await run();
    ref.invalidate(executionDataProvider(projectId));
    if (done != null && context.mounted) showSnack(context, done);
    return true;
  } on ExecutionRefused catch (e) {
    if (context.mounted) showSnack(context, e.message, error: true);
  } catch (e) {
    if (context.mounted) showSnack(context, trf('Could not save: {error}', {'error': '$e'}), error: true);
  }
  return false;
}

Future<String?> _pickDay(BuildContext context, {String? initial}) async {
  final now = DateTime.now();
  final d = await showDatePicker(
    context: context,
    initialDate: parseDay(initial) ?? now,
    firstDate: now.subtract(const Duration(days: 365)),
    lastDate: now.add(const Duration(days: 730)),
  );
  return d == null ? null : ymd(d);
}

String _day(String? ymdText) {
  final d = parseDay(ymdText);
  return d == null ? '' : fmtDate(d, short: true);
}

/// Opens a drawing or photo: images in the viewer, PDFs in the phone's own
/// reader through the share sheet.
Future<void> _openFile(BuildContext context, String path, {String? title}) async {
  if (!File(path).existsSync()) {
    showSnack(context, tr('The file is not on this phone yet. Sync and try again.'), error: true);
    return;
  }
  if (path.toLowerCase().endsWith('.pdf')) {
    await SharePlus.instance.share(ShareParams(files: [XFile(path)], text: title));
  } else {
    await showPhotoViewer(context, [path], shareText: title);
  }
}

class SiteExecutionScreen extends ConsumerWidget {
  const SiteExecutionScreen({super.key, required this.project, this.initialTab = 0});
  final Project project;
  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(executionDataProvider(project.id));
    final names = ref.watch(closeNamesProvider(project.companyId)).value ?? const <String, String>{};
    return DefaultTabController(
      length: 5,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: Text(trf('{site}: plan, quality and handover', {'site': project.name})),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: tr('Two-week lookahead')),
              Tab(text: tr('Drawings')),
              Tab(text: tr('RFIs')),
              Tab(text: tr('Quality')),
              Tab(text: tr('Handover')),
            ],
          ),
        ),
        body: data.when(
          data: (d) => TabBarView(
            children: [
              _LookaheadTab(project: project, data: d),
              _DrawingsTab(project: project, data: d, names: names),
              _RfisTab(project: project, data: d, names: names),
              _QualityTab(project: project, data: d, names: names),
              _HandoverTab(project: project, data: d, names: names),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => ErrorState(error: e, stack: st),
        ),
      ),
    );
  }
}

// --- FOS-205: the lookahead ----------------------------------------------------

class _LookaheadTab extends ConsumerWidget {
  const _LookaheadTab({required this.project, required this.data});
  final Project project;
  final ExecutionData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final items = data.lookahead(now);
    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.date_range_outlined,
        title: tr('Nothing planned for the next two weeks'),
        message: tr('Tasks with a start or due date in the next 14 days show here, with what each one is waiting for.'),
      );
    }
    final blocked = items.where((i) => !i.ready).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            trf('{n} tasks in the next two weeks, {b} waiting on something', {'n': items.length, 'b': blocked}),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        for (final i in items) _LookaheadCard(project: project, data: data, item: i, now: now),
      ],
    );
  }
}

class _LookaheadCard extends ConsumerWidget {
  const _LookaheadCard({required this.project, required this.data, required this.item, required this.now});
  final Project project;
  final ExecutionData data;
  final LookaheadItem item;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = _me(ref);
    final theme = Theme.of(context);
    final t = item.task;
    final lateTask = item.start.isBefore(DateTime(now.year, now.month, now.day));
    final cleared = [
      for (final c in data.constraints)
        if (c.taskId == t.id && !data.isOpen(c)) c,
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(t.title, style: theme.textTheme.titleSmall)),
                item.ready
                    ? StatusPill(tr('Ready to start'), tone: PillTone.ok)
                    : StatusPill(
                        trf('Waiting on {n}', {'n': item.open.length}),
                        tone: item.late.isNotEmpty ? PillTone.danger : PillTone.warn,
                      ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              lateTask
                  ? trf('Was to start {day}', {'day': fmtDate(item.start, short: true)})
                  : trf('Starts {day}', {'day': fmtDate(item.start, short: true)}),
              style: theme.textTheme.bodySmall?.copyWith(color: lateTask ? toneColor(context, PillTone.danger) : null),
            ),
            for (final c in item.open) _ConstraintRow(project: project, data: data, c: c, late: item.late.contains(c)),
            if (cleared.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(trf('{n} cleared', {'n': cleared.length}), style: theme.textTheme.bodySmall),
              ),
            if (me.canWrite)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(tr('Add what it waits for')),
                  onPressed: () => _addConstraint(context, ref, t),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _addConstraint(BuildContext context, WidgetRef ref, Task task) async {
    final desc = TextEditingController();
    String kind = 'material';
    String? needBy;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('What does this task wait for?')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('Kind')),
                  items: [
                    for (final k in constraintKinds.where((k) => k != 'rfi' && k != 'hold_point'))
                      DropdownMenuItem(value: k, child: Text(constraintKindLabel(k))),
                  ],
                  onChanged: (v) => set(() => kind = v ?? kind),
                ),
                TextField(
                  controller: desc,
                  maxLines: 2,
                  decoration: InputDecoration(labelText: tr('What exactly'), hintText: tr('e.g. 12 mm steel, 2 t')),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(needBy == null ? tr('Needed by (optional)') : trf('Needed by {day}', {'day': _day(needBy)})),
                  onTap: () async {
                    final d = await _pickDay(ctx, initial: needBy);
                    if (d != null) set(() => needBy = d);
                  },
                ),
                Text(
                  tr('RFIs and hold points raised for this task are added on their own.'),
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final db = ref.read(appDatabaseProvider);
    await _act(
      context,
      ref,
      project.id,
      () => db.siteExecutionDao.addConstraint(
        projectId: project.id,
        taskId: task.id,
        kind: kind,
        description: desc.text,
        by: _me(ref).userId,
        needBy: needBy,
      ),
    );
  }
}

class _ConstraintRow extends ConsumerWidget {
  const _ConstraintRow({required this.project, required this.data, required this.c, required this.late});
  final Project project;
  final ExecutionData data;
  final TaskConstraint c;
  final bool late;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final linked = c.linkId != null;
    final need = c.needBy == null ? null : trf('needed by {day}', {'day': _day(c.needBy)});
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        late ? Icons.error_outline : Icons.radio_button_unchecked,
        size: 20,
        color: late ? toneColor(context, PillTone.danger) : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text('${constraintKindLabel(c.kind)}: ${c.description}'),
      subtitle: Text([?need, if (linked) tr('clears when the record is done')].join(' · ')),
      trailing: linked || !_me(ref).canWrite
          ? null
          : IconButton(
              tooltip: tr('Mark cleared'),
              icon: const Icon(Icons.check_circle_outline),
              onPressed: () async {
                final note = await askText(context, title: tr('Mark cleared'), label: tr('Note (e.g. delivered, GRN number)'));
                if (note == null || !context.mounted) return;
                final db = ref.read(appDatabaseProvider);
                await _act(
                  context,
                  ref,
                  project.id,
                  () => db.siteExecutionDao.clearConstraint(c.id, by: _me(ref).userId, note: note),
                );
              },
            ),
    );
  }
}

// --- FOS-206: drawings ---------------------------------------------------------

(String, PillTone) _revisionPill(ExecutionData d, DrawingRevision r) {
  if (r.status == 'pending') return (tr('Waiting for approval'), PillTone.warn);
  if (r.status == 'rejected') return (tr('Rejected'), PillTone.danger);
  if (d.isSuperseded(r)) return (tr('Superseded'), PillTone.neutral);
  return (tr('On site'), PillTone.ok);
}

class _DrawingsTab extends ConsumerWidget {
  const _DrawingsTab({required this.project, required this.data, required this.names});
  final Project project;
  final ExecutionData data;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = _me(ref);
    final drawings = data.drawings;
    return Scaffold(
      body: drawings.isEmpty
          ? EmptyState(
              icon: Icons.architecture_outlined,
              title: tr('No drawings yet'),
              message: tr('Keep every drawing and its revisions here. The site sees only the latest approved revision.'),
              actionLabel: me.canWrite ? tr('Add drawing') : null,
              onAction: me.canWrite ? () => _addDrawing(context, ref) : null,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              children: [
                for (final disc in drawingDisciplines)
                  if (drawings.any((x) => x.discipline == disc)) ...[
                    SectionHeader(disciplineLabel(disc), padding: const EdgeInsets.fromLTRB(4, 8, 4, 6)),
                    for (final dr in drawings.where((x) => x.discipline == disc)) _drawingCard(context, ref, dr),
                  ],
              ],
            ),
      floatingActionButton: me.canWrite && drawings.isNotEmpty
          ? FloatingActionButton.extended(
              heroTag: 'drawing',
              icon: const Icon(Icons.add),
              label: Text(tr('Add drawing')),
              onPressed: () => _addDrawing(context, ref),
            )
          : null,
    );
  }

  Widget _drawingCard(BuildContext context, WidgetRef ref, Drawing dr) {
    final current = data.currentRevision(dr.id);
    final pending = data.revisionsOf(dr.id).where((r) => r.status == 'pending').length;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text('${dr.number}  ${dr.title}'),
        subtitle: Text(
          [
            current == null ? tr('No approved revision yet') : trf('{rev} on site', {'rev': current.rev}),
            if (pending > 0) trf('{n} waiting for approval', {'n': pending}),
          ].join(' · '),
        ),
        trailing: current == null
            ? StatusPill(tr('Not for construction'), tone: PillTone.warn)
            : IconButton(
                tooltip: tr('Open the current revision'),
                icon: const Icon(Icons.open_in_new),
                onPressed: () => _openFile(context, current.filePath, title: '${dr.number} ${current.rev}'),
              ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _DrawingScreen(project: project, drawingId: dr.id, names: names),
          ),
        ),
      ),
    );
  }

  Future<void> _addDrawing(BuildContext context, WidgetRef ref) async {
    final number = TextEditingController();
    final title = TextEditingController();
    String discipline = 'architectural';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Add drawing')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: number,
                  decoration: InputDecoration(labelText: tr('Drawing number'), hintText: 'S-12'),
                ),
                TextField(
                  controller: title,
                  decoration: InputDecoration(labelText: tr('Title')),
                ),
                DropdownButtonFormField<String>(
                  initialValue: discipline,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('Discipline')),
                  items: [for (final d in drawingDisciplines) DropdownMenuItem(value: d, child: Text(disciplineLabel(d)))],
                  onChanged: (v) => set(() => discipline = v ?? discipline),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final db = ref.read(appDatabaseProvider);
    await _act(
      context,
      ref,
      project.id,
      () => db.siteExecutionDao.addDrawing(
        projectId: project.id,
        number: number.text,
        title: title.text,
        discipline: discipline,
        by: _me(ref).userId,
      ),
    );
  }
}

/// One drawing's register: every revision, newest first, with who approved it.
class _DrawingScreen extends ConsumerWidget {
  const _DrawingScreen({required this.project, required this.drawingId, required this.names});
  final Project project;
  final String drawingId;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = _me(ref);
    final data = ref.watch(executionDataProvider(project.id));
    return data.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(
        body: ErrorState(error: e, stack: st),
      ),
      data: (d) {
        final dr = d.drawingById[drawingId];
        if (dr == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(tr('This drawing is no longer on the phone.'))),
          );
        }
        final revs = d.revisionsOf(drawingId)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return Scaffold(
          appBar: AppBar(title: Text('${dr.number}  ${dr.title}')),
          body: revs.isEmpty
              ? EmptyState(
                  icon: Icons.upload_file_outlined,
                  title: tr('No revisions yet'),
                  message: tr('Upload the drawing as a photo or PDF. It goes to the site once a manager approves it.'),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                  children: [for (final r in revs) _revisionCard(context, ref, d, dr, r, me)],
                ),
          floatingActionButton: me.canWrite
              ? FloatingActionButton.extended(
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(tr('Upload revision')),
                  onPressed: () => _upload(context, ref, dr, revs.length),
                )
              : null,
        );
      },
    );
  }

  Widget _revisionCard(BuildContext context, WidgetRef ref, ExecutionData d, Drawing dr, DrawingRevision r, _Me me) {
    final (label, tone) = _revisionPill(d, r);
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(r.rev, style: theme.textTheme.titleMedium)),
                StatusPill(label, tone: tone),
              ],
            ),
            Text(
              trf('Uploaded by {who}, {when}', {'who': _who(names, r.uploadedBy), 'when': fmtDateTime(r.createdAt)}),
              style: theme.textTheme.bodySmall,
            ),
            if ((r.note ?? '').isNotEmpty) Text(r.note!),
            if (r.decidedAt != null)
              Text(
                trf('{decision} by {who}, {when}', {
                  'decision': r.status == 'approved' ? tr('Approved') : tr('Rejected'),
                  'who': _who(names, r.decidedBy),
                  'when': fmtDateTime(r.decidedAt!),
                }),
                style: theme.textTheme.bodySmall,
              ),
            if ((r.decisionNote ?? '').isNotEmpty) Text(r.decisionNote!, style: theme.textTheme.bodySmall),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: Text(tr('Open')),
                  onPressed: () => _openFile(context, r.filePath, title: '${dr.number} ${r.rev}'),
                ),
                if (r.status == 'pending' && me.canDecide) ...[
                  TextButton(onPressed: () => _decide(context, ref, r, false), child: Text(tr('Reject'))),
                  FilledButton(onPressed: () => _decide(context, ref, r, true), child: Text(tr('Approve for construction'))),
                ],
              ],
            ),
            if (r.status == 'pending' && !me.canDecide)
              Text(tr('The owner or a project manager approves drawings.'), style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Future<void> _decide(BuildContext context, WidgetRef ref, DrawingRevision r, bool approve) async {
    final note = await askText(
      context,
      title: approve ? tr('Approve for construction') : tr('Reject'),
      label: tr('Note (optional)'),
    );
    if (note == null || !context.mounted) return;
    final db = ref.read(appDatabaseProvider);
    await _act(
      context,
      ref,
      project.id,
      () => db.siteExecutionDao.decideRevision(r.id, approve: approve, by: _me(ref).userId, note: note),
    );
  }

  Future<void> _upload(BuildContext context, WidgetRef ref, Drawing dr, int count) async {
    final files = await captureCameraFirstMany(context, prefix: 'drawing', sharp: true, allowPdf: true, max: 1);
    if (files.isEmpty || !context.mounted) return;
    final rev = TextEditingController(text: 'R$count');
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Upload revision')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: rev,
              decoration: InputDecoration(labelText: tr('Revision')),
            ),
            TextField(
              controller: note,
              decoration: InputDecoration(labelText: tr('What changed (optional)')),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final db = ref.read(appDatabaseProvider);
    await _act(
      context,
      ref,
      project.id,
      () => db.siteExecutionDao.addRevision(
        drawingId: dr.id,
        rev: rev.text,
        filePath: files.single.path,
        by: _me(ref).userId,
        note: note.text,
      ),
      done: tr('Uploaded. It reaches the site once approved.'),
    );
  }
}

// --- FOS-206: RFIs -------------------------------------------------------------

class _RfisTab extends ConsumerWidget {
  const _RfisTab({required this.project, required this.data, required this.names});
  final Project project;
  final ExecutionData data;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = _me(ref);
    final now = DateTime.now();
    final rfis = [...data.rfis]
      ..sort((a, b) {
        int rank(Rfi r) => r.status == 'open'
            ? 0
            : r.status == 'answered'
            ? 1
            : 2;
        final c = rank(a).compareTo(rank(b));
        return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
      });
    final theme = Theme.of(context);
    return Scaffold(
      body: rfis.isEmpty
          ? EmptyState(
              icon: Icons.help_outline,
              title: tr('No RFIs yet'),
              message: tr(
                'Ask the architect or consultant a question in writing, with a photo, and keep their answer on record.',
              ),
              actionLabel: me.canWrite ? tr('Raise RFI') : null,
              onAction: me.canWrite ? () => _raise(context, ref) : null,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              children: [
                for (final r in rfis)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(data.rfiNo(r), style: theme.textTheme.labelLarge),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(r.askedOf ?? '', style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                              ),
                              Flexible(
                                flex: 2,
                                child: switch (r.status) {
                                  'open' when data.rfiOverdue(r, now) => StatusPill(tr('Overdue'), tone: PillTone.danger),
                                  'open' => StatusPill(tr('Waiting for answer'), tone: PillTone.warn),
                                  'answered' => StatusPill(tr('Answered'), tone: PillTone.ok),
                                  _ => StatusPill(tr('Closed')),
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(r.question, style: theme.textTheme.bodyLarge),
                          Text(
                            [
                              trf('Raised by {who}, {when}', {
                                'who': _who(names, r.raisedBy),
                                'when': fmtDate(r.createdAt, short: true),
                              }),
                              if (r.dueOn != null) trf('answer by {day}', {'day': _day(r.dueOn)}),
                              if (r.drawingId != null && data.drawingById[r.drawingId] != null)
                                data.drawingById[r.drawingId]!.number,
                            ].join(' · '),
                            style: theme.textTheme.bodySmall,
                          ),
                          PhotoStrip(paths: [for (final p in data.photosOf(r.id, 'rfi')) p.filePath], size: 64),
                          if (r.answer != null) ...[
                            const SizedBox(height: 6),
                            Text(tr('Answer'), style: theme.textTheme.labelMedium),
                            Text(r.answer!),
                            if (r.answeredAt != null)
                              Text(
                                '${_who(names, r.answeredBy)}, ${fmtDate(r.answeredAt!, short: true)}',
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                          if (me.canWrite && r.status != 'closed')
                            Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 4,
                              children: [
                                if (r.status == 'open')
                                  TextButton(onPressed: () => _answer(context, ref, r), child: Text(tr('Record the answer'))),
                                if (r.status == 'answered')
                                  TextButton(
                                    onPressed: () => _act(
                                      context,
                                      ref,
                                      project.id,
                                      () => ref.read(appDatabaseProvider).siteExecutionDao.closeRfi(r.id, by: me.userId),
                                    ),
                                    child: Text(tr('Close')),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
      floatingActionButton: me.canWrite && rfis.isNotEmpty
          ? FloatingActionButton.extended(
              heroTag: 'rfi',
              icon: const Icon(Icons.add),
              label: Text(tr('Raise RFI')),
              onPressed: () => _raise(context, ref),
            )
          : null,
    );
  }

  Future<void> _answer(BuildContext context, WidgetRef ref, Rfi r) async {
    final a = await askText(context, title: tr('Record the answer'), label: tr('What they said'));
    if (a == null || !context.mounted) return;
    await _act(
      context,
      ref,
      project.id,
      () => ref.read(appDatabaseProvider).siteExecutionDao.answerRfi(r.id, answer: a, by: _me(ref).userId),
    );
  }

  Future<void> _raise(BuildContext context, WidgetRef ref) async {
    final question = TextEditingController();
    final askedOf = TextEditingController();
    String? taskId;
    String? drawingId;
    String? dueOn;
    var photos = <String>[];
    final upcoming = [for (final i in data.lookahead(DateTime.now())) i.task];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Raise RFI')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: question,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: tr('Question')),
                ),
                TextField(
                  controller: askedOf,
                  decoration: InputDecoration(labelText: tr('Asked of'), hintText: tr('e.g. Structural consultant')),
                ),
                if (upcoming.isNotEmpty)
                  DropdownButtonFormField<String?>(
                    initialValue: taskId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('Task it holds up (optional)')),
                    items: [
                      DropdownMenuItem(value: null, child: Text(tr('None'))),
                      for (final t in upcoming)
                        DropdownMenuItem(
                          value: t.id,
                          child: Text(t.title, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => set(() => taskId = v),
                  ),
                if (data.drawings.isNotEmpty)
                  DropdownButtonFormField<String?>(
                    initialValue: drawingId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('Drawing (optional)')),
                    items: [
                      DropdownMenuItem(value: null, child: Text(tr('None'))),
                      for (final d in data.drawings)
                        DropdownMenuItem(
                          value: d.id,
                          child: Text('${d.number} ${d.title}', overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => set(() => drawingId = v),
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(dueOn == null ? tr('Answer needed by (optional)') : trf('Answer by {day}', {'day': _day(dueOn)})),
                  onTap: () async {
                    final d = await _pickDay(ctx, initial: dueOn);
                    if (d != null) set(() => dueOn = d);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.add_a_photo_outlined),
                  title: Text(photos.isEmpty ? tr('Add photos (optional)') : trf('{n} photos', {'n': photos.length})),
                  onTap: () async {
                    final f = await captureCameraFirstMany(ctx, prefix: 'rfi', place: project.name);
                    set(() => photos = [...photos, for (final x in f) x.path]);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await _act(
      context,
      ref,
      project.id,
      () => ref
          .read(appDatabaseProvider)
          .siteExecutionDao
          .raiseRfi(
            projectId: project.id,
            question: question.text,
            by: _me(ref).userId,
            askedOf: askedOf.text,
            taskId: taskId,
            drawingId: drawingId,
            dueOn: dueOn,
            photos: photos,
          ),
    );
  }
}

// --- FOS-207: quality ----------------------------------------------------------

(String, PillTone) _defectPill(Defect d) => switch (d.status) {
  'fixed' => (tr('Fixed, to check'), PillTone.warn),
  'closed' => (tr('Closed'), PillTone.ok),
  _ => (d.severity == 'critical' ? tr('Open, critical') : tr('Open'), d.severity == 'minor' ? PillTone.warn : PillTone.danger),
};

class _QualityTab extends ConsumerWidget {
  const _QualityTab({required this.project, required this.data, required this.names});
  final Project project;
  final ExecutionData data;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = _me(ref);
    final now = DateTime.now();
    final holds = [...data.holdPoints]
      ..sort((a, b) => (a.status == 'released' ? 1 : 0).compareTo(b.status == 'released' ? 1 : 0));
    final defects = [...data.defects]
      ..sort((a, b) {
        int rank(Defect d) => d.status == 'open'
            ? 0
            : d.status == 'fixed'
            ? 1
            : 2;
        final c = rank(a).compareTo(rank(b));
        return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
      });
    final unitName = {for (final u in data.units) u.id: u.name};
    final theme = Theme.of(context);
    return Scaffold(
      body: holds.isEmpty && defects.isEmpty
          ? EmptyState(
              icon: Icons.verified_outlined,
              title: tr('No hold points or defects yet'),
              message: tr(
                'A hold point stops work until it is inspected and released. A defect is fixed with a photo and checked by someone else.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
              children: [
                if (holds.isNotEmpty) SectionHeader(tr('Hold points'), padding: const EdgeInsets.fromLTRB(4, 12, 4, 6)),
                for (final h in holds)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(h.title),
                      subtitle: Text(
                        [
                          if ((h.location ?? '').isNotEmpty) h.location!,
                          if (h.unitId != null && unitName[h.unitId] != null) unitName[h.unitId]!,
                          if (h.decidedAt != null) '${_who(names, h.decidedBy)}, ${fmtDate(h.decidedAt!, short: true)}',
                          if ((h.note ?? '').isNotEmpty) h.note!,
                        ].join(' · '),
                      ),
                      trailing: switch (h.status) {
                        'released' => StatusPill(tr('Released'), tone: PillTone.ok),
                        'rejected' => StatusPill(tr('Not released'), tone: PillTone.danger),
                        _ => StatusPill(tr('Waiting for inspection'), tone: PillTone.warn),
                      },
                      onTap: h.status == 'released' ? null : () => _decideHold(context, ref, h, me),
                    ),
                  ),
                if (defects.isNotEmpty) SectionHeader(tr('Defects and snags'), padding: const EdgeInsets.fromLTRB(4, 16, 4, 6)),
                for (final d in defects)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(d.description, style: theme.textTheme.titleSmall)),
                              Builder(
                                builder: (_) {
                                  final (l, t) = _defectPill(d);
                                  return StatusPill(l, tone: t);
                                },
                              ),
                            ],
                          ),
                          Text(
                            [
                              severityLabel(d.severity),
                              if (d.unitId != null && unitName[d.unitId] != null) unitName[d.unitId]!,
                              if ((d.location ?? '').isNotEmpty) d.location!,
                              trf('raised {day}', {'day': fmtDate(d.createdAt, short: true)}),
                              if (data.defectAgeing(d, now)) tr('open a week or more'),
                              if (d.reopenCount > 0) trf('reopened {n} times', {'n': d.reopenCount}),
                            ].join(' · '),
                            style: theme.textTheme.bodySmall,
                          ),
                          PhotoStrip(paths: [for (final p in data.photosOf(d.id, 'defect')) p.filePath], size: 64),
                          if (d.fixedAt != null) ...[
                            const SizedBox(height: 4),
                            Text(trf('Fixed by {who}', {'who': _who(names, d.fixedBy)}), style: theme.textTheme.labelMedium),
                            if ((d.fixNote ?? '').isNotEmpty) Text(d.fixNote!),
                            PhotoStrip(paths: [for (final p in data.photosOf(d.id, 'defect_fix')) p.filePath], size: 64),
                          ],
                          if (d.closedAt != null)
                            Text(
                              trf('Checked and closed by {who}', {'who': _who(names, d.closedBy)}),
                              style: theme.textTheme.bodySmall,
                            ),
                          if (me.canWrite && d.status != 'closed')
                            Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 4,
                              children: [
                                if (d.status == 'open')
                                  FilledButton.tonal(onPressed: () => _fix(context, ref, d), child: Text(tr('Mark fixed'))),
                                if (d.status == 'fixed' && d.fixedBy != me.userId) ...[
                                  TextButton(onPressed: () => _verify(context, ref, d, false), child: Text(tr('Reopen'))),
                                  FilledButton(
                                    onPressed: () => _verify(context, ref, d, true),
                                    child: Text(tr('Accept and close')),
                                  ),
                                ],
                                if (d.status == 'fixed' && d.fixedBy == me.userId)
                                  Text(tr('Someone else checks your fix.'), style: theme.textTheme.bodySmall),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
      floatingActionButton: me.canWrite
          ? FloatingActionButton.extended(
              heroTag: 'quality',
              icon: const Icon(Icons.add),
              label: Text(tr('Add')),
              onPressed: () => _addMenu(context, ref),
            )
          : null,
    );
  }

  Future<void> _addMenu(BuildContext context, WidgetRef ref) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.report_problem_outlined),
              title: Text(tr('Raise a defect')),
              onTap: () => Navigator.pop(ctx, 'defect'),
            ),
            ListTile(
              leading: const Icon(Icons.pan_tool_outlined),
              title: Text(tr('Add a hold point')),
              onTap: () => Navigator.pop(ctx, 'hold'),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_check),
              title: Text(tr("Add the company's standard hold points")),
              onTap: () => Navigator.pop(ctx, 'standards'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (v) {
      case 'defect':
        await raiseDefectDialog(context, ref, project, data);
      case 'hold':
        await _addHold(context, ref);
      case 'standards':
        await _applyStandards(context, ref);
    }
  }

  Future<void> _addHold(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final location = TextEditingController();
    String? taskId;
    String? unitId;
    final upcoming = [for (final i in data.lookahead(DateTime.now())) i.task];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Add a hold point')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: InputDecoration(
                    labelText: tr('What is inspected'),
                    hintText: tr('e.g. Reinforcement check before pour'),
                  ),
                ),
                TextField(
                  controller: location,
                  decoration: InputDecoration(labelText: tr('Where (optional)')),
                ),
                if (upcoming.isNotEmpty)
                  DropdownButtonFormField<String?>(
                    initialValue: taskId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('Task it holds up (optional)')),
                    items: [
                      DropdownMenuItem(value: null, child: Text(tr('None'))),
                      for (final t in upcoming)
                        DropdownMenuItem(
                          value: t.id,
                          child: Text(t.title, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => set(() => taskId = v),
                  ),
                if (data.units.isNotEmpty)
                  DropdownButtonFormField<String?>(
                    initialValue: unitId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('Unit (optional)')),
                    items: [
                      DropdownMenuItem(value: null, child: Text(tr('None'))),
                      for (final u in data.units) DropdownMenuItem(value: u.id, child: Text(u.name)),
                    ],
                    onChanged: (v) => set(() => unitId = v),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await _act(
      context,
      ref,
      project.id,
      () => ref
          .read(appDatabaseProvider)
          .siteExecutionDao
          .addHoldPoint(
            projectId: project.id,
            title: title.text,
            by: _me(ref).userId,
            location: location.text,
            taskId: taskId,
            unitId: unitId,
          ),
    );
  }

  Future<void> _applyStandards(BuildContext context, WidgetRef ref) async {
    final db = ref.read(appDatabaseProvider);
    final standards = (await db.siteExecutionDao.standardsFor(project.companyId)).where((s) => s.kind == 'hold_point').toList();
    if (!context.mounted) return;
    if (standards.isEmpty) {
      showSnack(
        context,
        tr('The company has no standard hold points yet. Add them from Home > Site execution across sites.'),
        error: true,
      );
      return;
    }
    final where = await askText(
      context,
      title: tr("Add the company's standard hold points"),
      label: tr('Where (e.g. Block A, 3rd floor)'),
    );
    if (where == null || !context.mounted) return;
    await _act(
      context,
      ref,
      project.id,
      () => db.siteExecutionDao.applyHoldPointStandards(
        companyId: project.companyId,
        projectId: project.id,
        location: where,
        by: _me(ref).userId,
      ),
      done: trf('{n} hold points added', {'n': standards.length}),
    );
  }

  Future<void> _decideHold(BuildContext context, WidgetRef ref, HoldPoint h, _Me me) async {
    if (!me.canDecide) {
      showSnack(context, tr('The owner or a project manager releases hold points.'));
      return;
    }
    var photos = <String>[];
    final note = TextEditingController();
    final release = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(h.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: note,
                decoration: InputDecoration(labelText: tr('Inspection note')),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add_a_photo_outlined),
                title: Text(photos.isEmpty ? tr('Add photos (optional)') : trf('{n} photos', {'n': photos.length})),
                onTap: () async {
                  final f = await captureCameraFirstMany(ctx, prefix: 'hold', place: h.location ?? project.name);
                  set(() => photos = [...photos, for (final x in f) x.path]);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel'))),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Not released'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Release'))),
          ],
        ),
      ),
    );
    if (release == null || !context.mounted) return;
    await _act(
      context,
      ref,
      project.id,
      () => ref
          .read(appDatabaseProvider)
          .siteExecutionDao
          .decideHoldPoint(h.id, release: release, by: me.userId, note: note.text, photos: photos),
    );
  }

  Future<void> _fix(BuildContext context, WidgetRef ref, Defect d) async {
    final photos = await captureCameraFirstMany(context, prefix: 'fix', place: d.location ?? project.name);
    if (photos.isEmpty || !context.mounted) return;
    final note = await askText(context, title: tr('Mark fixed'), label: tr('What was done (optional)'));
    if (note == null || !context.mounted) return;
    await _act(
      context,
      ref,
      project.id,
      () => ref
          .read(appDatabaseProvider)
          .siteExecutionDao
          .markFixed(d.id, by: _me(ref).userId, note: note, photos: [for (final p in photos) p.path]),
      done: tr('Marked fixed. Someone else checks it.'),
    );
  }

  Future<void> _verify(BuildContext context, WidgetRef ref, Defect d, bool accept) async {
    final note = await askText(
      context,
      title: accept ? tr('Accept and close') : tr('Reopen'),
      label: accept ? tr('Note (optional)') : tr('What is still wrong'),
    );
    if (note == null || !context.mounted) return;
    await _act(
      context,
      ref,
      project.id,
      () => ref.read(appDatabaseProvider).siteExecutionDao.verifyFix(d.id, accept: accept, by: _me(ref).userId, note: note),
    );
  }
}

/// Raise a defect with a photo, optionally in a unit.
Future<void> raiseDefectDialog(BuildContext context, WidgetRef ref, Project project, ExecutionData data, {String? unitId}) async {
  final desc = TextEditingController();
  final location = TextEditingController();
  String severity = 'minor';
  String? unit = unitId;
  String? dueOn;
  var photos = <String>[];
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(tr('Raise a defect')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: desc,
                maxLines: 2,
                decoration: InputDecoration(labelText: tr('What is wrong')),
              ),
              TextField(
                controller: location,
                decoration: InputDecoration(labelText: tr('Where (e.g. master bedroom)')),
              ),
              DropdownButtonFormField<String>(
                initialValue: severity,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Severity')),
                items: [for (final s in defectSeverities) DropdownMenuItem(value: s, child: Text(severityLabel(s)))],
                onChanged: (v) => set(() => severity = v ?? severity),
              ),
              if (data.units.isNotEmpty)
                DropdownButtonFormField<String?>(
                  initialValue: unit,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('Unit (optional)')),
                  items: [
                    DropdownMenuItem(value: null, child: Text(tr('None'))),
                    for (final u in data.units) DropdownMenuItem(value: u.id, child: Text(u.name)),
                  ],
                  onChanged: (v) => set(() => unit = v),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text(dueOn == null ? tr('Fix by (optional)') : trf('Fix by {day}', {'day': _day(dueOn)})),
                onTap: () async {
                  final d = await _pickDay(ctx, initial: dueOn);
                  if (d != null) set(() => dueOn = d);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add_a_photo_outlined),
                title: Text(photos.isEmpty ? tr('Add photos') : trf('{n} photos', {'n': photos.length})),
                onTap: () async {
                  final f = await captureCameraFirstMany(ctx, prefix: 'defect', place: project.name);
                  set(() => photos = [...photos, for (final x in f) x.path]);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  await _act(
    context,
    ref,
    project.id,
    () => ref
        .read(appDatabaseProvider)
        .siteExecutionDao
        .raiseDefect(
          projectId: project.id,
          description: desc.text,
          by: _me(ref).userId,
          severity: severity,
          unitId: unit,
          location: location.text,
          dueOn: dueOn,
          photos: photos,
        ),
  );
}

// --- FOS-208: handover ---------------------------------------------------------

(String, PillTone) _unitPill(UnitState s) => switch (s) {
  UnitState.handedOver => (tr('Handed over'), PillTone.ok),
  UnitState.ready => (tr('Ready to hand over'), PillTone.ok),
  UnitState.notReady => (tr('Not ready'), PillTone.warn),
};

class _HandoverTab extends ConsumerWidget {
  const _HandoverTab({required this.project, required this.data, required this.names});
  final Project project;
  final ExecutionData data;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = _me(ref);
    final groups = data.unitsByFloor();
    final handed = data.units.where((u) => u.handedOverAt != null).length;
    return Scaffold(
      body: data.units.isEmpty
          ? EmptyState(
              icon: Icons.key_outlined,
              title: tr('No units yet'),
              message: tr(
                'Add each flat, villa or zone. It can be handed over only when its defects are closed, '
                'hold points released and checklist done.',
              ),
              actionLabel: me.canWrite ? tr('Add unit') : null,
              onAction: me.canWrite ? () => _addUnit(context, ref) : null,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                  child: Text(trf('{h} of {n} handed over', {'h': handed, 'n': data.units.length})),
                ),
                for (final e in groups.entries) ...[
                  SectionHeader(e.key.isEmpty ? tr('Units') : e.key, padding: const EdgeInsets.fromLTRB(4, 12, 4, 6)),
                  for (final u in e.value)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(u.name),
                        subtitle: Text(
                          u.handedOverAt != null
                              ? trf('To {who}, {when}', {'who': u.handedTo ?? '', 'when': fmtDate(u.handedOverAt!, short: true)})
                              : data.handoverBlockers(u).join(' · '),
                        ),
                        trailing: Builder(
                          builder: (_) {
                            final (l, t) = _unitPill(data.unitState(u));
                            return StatusPill(l, tone: t);
                          },
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => _UnitScreen(project: project, unitId: u.id, names: names),
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
      floatingActionButton: me.canWrite && data.units.isNotEmpty
          ? FloatingActionButton.extended(
              heroTag: 'unit',
              icon: const Icon(Icons.add),
              label: Text(tr('Add unit')),
              onPressed: () => _addUnit(context, ref),
            )
          : null,
    );
  }

  Future<void> _addUnit(BuildContext context, WidgetRef ref) async {
    final db = ref.read(appDatabaseProvider);
    final checklist = [
      for (final s in await db.siteExecutionDao.standardsFor(project.companyId))
        if (s.kind == 'handover_check') s.item,
    ];
    if (!context.mounted) return;
    final block = TextEditingController();
    final floor = TextEditingController();
    final name = TextEditingController();
    var useChecklist = checklist.isNotEmpty;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Add unit')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(labelText: tr('Unit'), hintText: tr('e.g. Flat 304')),
                ),
                TextField(
                  controller: block,
                  decoration: InputDecoration(labelText: tr('Block or zone (optional)')),
                ),
                TextField(
                  controller: floor,
                  decoration: InputDecoration(labelText: tr('Floor (optional)')),
                ),
                if (checklist.isNotEmpty)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: useChecklist,
                    title: Text(trf("Use the company's handover checklist ({n} lines)", {'n': checklist.length})),
                    onChanged: (v) => set(() => useChecklist = v ?? false),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await _act(
      context,
      ref,
      project.id,
      () => db.siteExecutionDao.addUnit(
        projectId: project.id,
        name: name.text,
        block: block.text,
        floor: floor.text,
        by: _me(ref).userId,
        checklist: useChecklist ? checklist : const [],
      ),
    );
  }
}

class _UnitScreen extends ConsumerWidget {
  const _UnitScreen({required this.project, required this.unitId, required this.names});
  final Project project;
  final String unitId;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = _me(ref);
    final data = ref.watch(executionDataProvider(project.id));
    return data.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(
        body: ErrorState(error: e, stack: st),
      ),
      data: (d) {
        final u = d.units.where((x) => x.id == unitId).firstOrNull;
        if (u == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(tr('This unit is no longer on the phone.'))),
          );
        }
        final theme = Theme.of(context);
        final checks = d.checksOf(u.id);
        final defects = d.defects.where((x) => x.unitId == u.id).toList();
        final holds = d.holdPoints.where((x) => x.unitId == u.id).toList();
        final blockers = d.handoverBlockers(u);
        final handed = u.handedOverAt != null;
        final (label, tone) = _unitPill(d.unitState(u));
        return Scaffold(
          appBar: AppBar(
            title: Text([if ((u.block ?? '').isNotEmpty) u.block!, if ((u.floor ?? '').isNotEmpty) u.floor!, u.name].join(' · ')),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Row(children: [StatusPill(label, tone: tone)]),
              if (handed) ...[
                const SizedBox(height: 8),
                KeyValue(tr('Handed to'), u.handedTo ?? ''),
                KeyValue(tr('On'), fmtDateTime(u.handedOverAt!)),
                KeyValue(tr('By'), _who(names, u.handedOverBy)),
                if ((u.handoverNote ?? '').isNotEmpty) Text(u.handoverNote!),
              ] else if (blockers.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final b in blockers) Text('• $b', style: theme.textTheme.bodyMedium),
              ],
              SectionHeader(tr('Handover checklist')),
              if (checks.isEmpty) Text(tr('No checklist lines.'), style: theme.textTheme.bodySmall),
              for (final c in checks)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: c.done,
                  title: Text(c.item),
                  subtitle: c.doneAt == null ? null : Text('${_who(names, c.doneBy)}, ${fmtDate(c.doneAt!, short: true)}'),
                  onChanged: handed || !me.canWrite
                      ? null
                      : (v) => _act(
                          context,
                          ref,
                          project.id,
                          () => ref.read(appDatabaseProvider).siteExecutionDao.setCheck(c.id, done: v ?? false, by: me.userId),
                        ),
                ),
              if (!handed && me.canWrite)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(tr('Add checklist line')),
                    onPressed: () async {
                      final item = await askText(context, title: tr('Add checklist line'));
                      if (item == null || item.isEmpty || !context.mounted) return;
                      await _act(
                        context,
                        ref,
                        project.id,
                        () => ref
                            .read(appDatabaseProvider)
                            .siteExecutionDao
                            .addCheck(unitId: u.id, projectId: project.id, item: item, sortOrder: checks.length),
                      );
                    },
                  ),
                ),
              SectionHeader(tr('Defects')),
              if (defects.isEmpty) Text(tr('None raised.'), style: theme.textTheme.bodySmall),
              for (final x in defects)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(x.description),
                  subtitle: Text([severityLabel(x.severity), if ((x.location ?? '').isNotEmpty) x.location!].join(' · ')),
                  trailing: Builder(
                    builder: (_) {
                      final (l, t) = _defectPill(x);
                      return StatusPill(l, tone: t);
                    },
                  ),
                ),
              if (!handed && me.canWrite)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.report_problem_outlined, size: 18),
                    label: Text(tr('Raise a defect')),
                    onPressed: () => raiseDefectDialog(context, ref, project, d, unitId: u.id),
                  ),
                ),
              if (holds.isNotEmpty) ...[
                SectionHeader(tr('Hold points')),
                for (final h in holds)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(h.title),
                    trailing: h.status == 'released'
                        ? StatusPill(tr('Released'), tone: PillTone.ok)
                        : StatusPill(tr('Waiting for inspection'), tone: PillTone.warn),
                  ),
              ],
              if (!handed) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  icon: const Icon(Icons.key_outlined),
                  label: Text(tr('Hand over')),
                  onPressed: blockers.isEmpty && me.canDecide ? () => _handOver(context, ref, u, blockers) : null,
                ),
                if (!me.canDecide)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(tr('The owner or a project manager hands over a unit.'), style: theme.textTheme.bodySmall),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _handOver(BuildContext context, WidgetRef ref, HandoverUnit u, List<String> blockers) async {
    final to = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(trf('Hand over {unit}', {'unit': u.name})),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: to,
              decoration: InputDecoration(labelText: tr('Handed to'), hintText: tr('e.g. Mr. Reddy')),
            ),
            TextField(
              controller: note,
              decoration: InputDecoration(labelText: tr('Note (e.g. keys given)')),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Hand over'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _act(
      context,
      ref,
      project.id,
      () => ref
          .read(appDatabaseProvider)
          .siteExecutionDao
          .handOver(u.id, handedTo: to.text, by: _me(ref).userId, blockers: blockers, note: note.text),
      done: trf('{unit} handed over', {'unit': u.name}),
    );
  }
}
