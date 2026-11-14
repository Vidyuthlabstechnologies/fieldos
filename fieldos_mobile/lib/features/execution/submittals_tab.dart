/// The submittals register: shop drawings, product data, samples, mock-ups
/// and method statements sent for the architect's or consultant's review,
/// with their review, the round they are on, and when they are needed by.
/// A task can wait for a submittal's approval in the lookahead.
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
import 'package:fieldos_mobile/features/shared/photo_capture.dart';
import 'package:fieldos_mobile/features/shared/photo_viewer.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

String _day(String? ymdText) {
  final d = parseDay(ymdText);
  return d == null ? '' : fmtDate(d, short: true);
}

PillTone _tone(String status) => switch (status) {
      'approved' || 'approved_as_noted' => PillTone.ok,
      'revise_resubmit' => PillTone.warn,
      'rejected' => PillTone.danger,
      _ => PillTone.neutral,
    };

class SubmittalsTab extends ConsumerWidget {
  const SubmittalsTab({super.key, required this.project, required this.data, required this.names});
  final Project project;
  final ExecutionData data;
  final Map<String, String> names;

  String _who(String? id) => id == null || id.isEmpty ? tr('Someone on the team') : names[id] ?? tr('Someone on the team');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final canWrite = session.role != null && Roles.canWrite(session.role!);
    final canDecide = Roles.canApprove(session.role);
    final now = DateTime.now();
    final list = [...data.submittals]
      ..sort((a, b) {
        int rank(Submittal x) => switch (x.status) {
              'submitted' => data.submittalOverdue(x, now) ? 0 : 1,
              'revise_resubmit' || 'rejected' => 2,
              _ => 3,
            };
        final c = rank(a).compareTo(rank(b));
        return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
      });
    final theme = Theme.of(context);
    return Scaffold(
      body: list.isEmpty
          ? EmptyState(
              icon: Icons.fact_check_outlined,
              title: tr('No submittals yet'),
              message: tr(
                  'Send shop drawings, product data, samples and method statements for review, and keep the answer and every round on record.'),
              actionLabel: canWrite ? tr('New submittal') : null,
              onAction: canWrite ? () => _raise(context, ref) : null,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              children: [
                for (final x in list)
                  Card(
                    key: Key('submittal-${x.id}'),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 8, 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(data.submittalNo(x), style: theme.textTheme.labelLarge),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              [submittalKindLabel(x.kind), if (x.round > 1) trf('round {n}', {'n': x.round})].join(' · '),
                              style: theme.textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Flexible(
                            flex: 2,
                            child: data.submittalOverdue(x, now)
                                ? StatusPill(tr('Overdue'), tone: PillTone.danger)
                                : StatusPill(submittalStatusLabel(x.status), tone: _tone(x.status)),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        Text(x.title, style: theme.textTheme.bodyLarge),
                        Text(
                          [
                            if ((x.specSection ?? '').isNotEmpty) x.specSection!,
                            if ((x.fromParty ?? '').isNotEmpty) trf('from {who}', {'who': x.fromParty!}),
                            if ((x.reviewer ?? '').isNotEmpty) trf('review by {who}', {'who': x.reviewer!}),
                            if (x.requiredBy != null) trf('needed by {day}', {'day': _day(x.requiredBy)}),
                            if (x.drawingId != null && data.drawingById[x.drawingId] != null) data.drawingById[x.drawingId]!.number,
                          ].join(' · '),
                          style: theme.textTheme.bodySmall,
                        ),
                        PhotoStrip(paths: [for (final p in data.photosOf(x.id, 'submittal')) p.filePath], size: 64),
                        if (x.decidedAt != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            trf('{status} by {who}, {when}', {
                              'status': submittalStatusLabel(x.status),
                              'who': _who(x.decidedBy),
                              'when': fmtDate(x.decidedAt!, short: true),
                            }),
                            style: theme.textTheme.labelMedium,
                          ),
                          if ((x.decisionNote ?? '').isNotEmpty) Text(x.decisionNote!),
                        ],
                        for (final line in x.history.split('\n'))
                          if (parseSubmittalHistory(line) case final h?)
                            Text(
                              trf('Round {n}: {status}, {day}', {
                                'n': h.round,
                                'status': submittalStatusLabel(h.status),
                                'day': _day(h.day),
                              }) +
                                  (h.note.isEmpty ? '' : ' · ${h.note}'),
                              style: theme.textTheme.bodySmall,
                            ),
                        Wrap(alignment: WrapAlignment.end, spacing: 4, children: [
                          if (canDecide && x.status == 'submitted')
                            TextButton(
                              key: Key('submittal-review-${x.id}'),
                              onPressed: () => _review(context, ref, x),
                              child: Text(tr('Record the review')),
                            ),
                          if (canWrite && (x.status == 'revise_resubmit' || x.status == 'rejected'))
                            TextButton(
                              key: Key('submittal-resubmit-${x.id}'),
                              onPressed: () => _resubmit(context, ref, x),
                              child: Text(tr('Resubmit')),
                            ),
                        ]),
                      ]),
                    ),
                  ),
              ],
            ),
      floatingActionButton: canWrite && list.isNotEmpty
          ? FloatingActionButton.extended(
              heroTag: 'submittal',
              icon: const Icon(Icons.add),
              label: Text(tr('New submittal')),
              onPressed: () => _raise(context, ref),
            )
          : null,
    );
  }

  Future<void> _act(BuildContext context, WidgetRef ref, Future<void> Function() run, {String? done}) async {
    try {
      await run();
      ref.invalidate(executionDataProvider(project.id));
      if (done != null && context.mounted) showSnack(context, done);
    } on ExecutionRefused catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (context.mounted) showSnack(context, trf('Could not save: {error}', {'error': '$e'}), error: true);
    }
  }

  Future<void> _raise(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final spec = TextEditingController();
    final from = TextEditingController();
    final reviewer = TextEditingController();
    var kind = 'product_data';
    String? taskId;
    String? drawingId;
    String? requiredBy;
    var photos = <String>[];
    final upcoming = [for (final i in data.lookahead(DateTime.now())) i.task];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('New submittal')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                key: const Key('submittal-title'),
                controller: title,
                maxLines: 2,
                decoration: InputDecoration(labelText: tr('What is submitted'), hintText: tr('e.g. Floor tiles 600 x 600, sample board')),
              ),
              DropdownButtonFormField<String>(
                initialValue: kind,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Type')),
                items: [for (final k in submittalKinds) DropdownMenuItem(value: k, child: Text(submittalKindLabel(k)))],
                onChanged: (v) => set(() => kind = v ?? kind),
              ),
              TextField(controller: from, decoration: InputDecoration(labelText: tr('From (subcontractor or supplier)'))),
              TextField(
                controller: reviewer,
                decoration: InputDecoration(labelText: tr('Reviewed by'), hintText: tr('e.g. Architect')),
              ),
              TextField(controller: spec, decoration: InputDecoration(labelText: tr('Spec section (optional)'))),
              if (upcoming.isNotEmpty)
                DropdownButtonFormField<String?>(
                  initialValue: taskId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('Task it holds up (optional)')),
                  items: [
                    DropdownMenuItem(value: null, child: Text(tr('None'))),
                    for (final t in upcoming) DropdownMenuItem(value: t.id, child: Text(t.title, overflow: TextOverflow.ellipsis)),
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
                      DropdownMenuItem(value: d.id, child: Text('${d.number} ${d.title}', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => set(() => drawingId = v),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text(requiredBy == null ? tr('Needed by (optional)') : trf('needed by {day}', {'day': _day(requiredBy)})),
                onTap: () async {
                  final now = DateTime.now();
                  final d = await pickDate(ctx,
                      initial: parseDay(requiredBy) ?? now, first: now.subtract(const Duration(days: 30)), last: now.add(const Duration(days: 730)));
                  if (d != null) set(() => requiredBy = ymd(d));
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add_a_photo_outlined),
                title: Text(photos.isEmpty ? tr('Add photos (optional)') : trf('{n} photos', {'n': photos.length})),
                onTap: () async {
                  final f = await captureCameraFirstMany(ctx, prefix: 'submittal', place: project.name);
                  set(() => photos = [...photos, for (final x in f) x.path]);
                },
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(key: const Key('submittal-save'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await _act(
      context,
      ref,
      () => ref.read(appDatabaseProvider).siteExecutionDao.raiseSubmittal(
            projectId: project.id,
            title: title.text,
            kind: kind,
            specSection: spec.text,
            fromParty: from.text,
            reviewer: reviewer.text,
            requiredBy: requiredBy,
            drawingId: drawingId,
            taskId: taskId,
            photos: photos,
            by: ref.read(sessionProvider).user!.id,
          ),
    );
  }

  Future<void> _review(BuildContext context, WidgetRef ref, Submittal x) async {
    final note = TextEditingController();
    var status = 'approved';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Record the review')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final s in const ['approved', 'approved_as_noted', 'revise_resubmit', 'rejected'])
                  ChoiceChip(
                    key: Key('submittal-outcome-$s'),
                    label: Text(submittalStatusLabel(s)),
                    selected: status == s,
                    onSelected: (_) => set(() => status = s),
                  ),
              ]),
              TextField(
                key: const Key('submittal-note'),
                controller: note,
                maxLines: 3,
                decoration: InputDecoration(labelText: tr('What the reviewer said')),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(key: const Key('submittal-review-save'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await _act(
      context,
      ref,
      () => ref
          .read(appDatabaseProvider)
          .siteExecutionDao
          .decideSubmittal(x.id, status: status, note: note.text, by: ref.read(sessionProvider).user!.id),
    );
  }

  Future<void> _resubmit(BuildContext context, WidgetRef ref, Submittal x) async {
    final photos = await captureCameraFirstMany(context, prefix: 'submittal', place: project.name);
    if (!context.mounted) return;
    await _act(
      context,
      ref,
      () => ref
          .read(appDatabaseProvider)
          .siteExecutionDao
          .resubmitSubmittal(x.id, photos: [for (final f in photos) f.path], by: ref.read(sessionProvider).user!.id),
      done: tr('Sent for review again.'),
    );
  }
}
