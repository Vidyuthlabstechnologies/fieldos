/// "Get your first site running": the few steps that make FieldOS worth
/// paying for, as a checklist on Home for the owner or a manager. Each
/// step is one tap to the right screen, and ticks itself off from what is
/// actually on the phone, so nobody has to mark anything done. The sample
/// site never counts: the point is the builder's own site.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/auth/auth_service.dart' show Roles;
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/mascot/mitra.dart';
import 'package:fieldos_mobile/features/onboarding/sample_project.dart';
import 'package:fieldos_mobile/features/project/project_detail_screen.dart';
import 'package:fieldos_mobile/features/tasks/team_roster.dart' show loadRoster;
import 'package:fieldos_mobile/features/team/invite_team.dart';
import 'package:fieldos_mobile/features/team/team_sync_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

enum GetStartedStep { site, attendance, report, team }

class GetStartedProgress {
  const GetStartedProgress({required this.done, required this.steps, required this.hidden, this.site});

  /// The steps this company has, in order (no team step in a build
  /// without cloud sync).
  final List<GetStartedStep> steps;
  final Set<GetStartedStep> done;

  /// Closed by the person, or finished and closed.
  final bool hidden;

  /// The builder's own site the attendance and report steps open.
  final Project? site;

  int get doneCount => steps.where(done.contains).length;
  bool get finished => doneCount == steps.length;

  /// The first step still to do.
  GetStartedStep? get next => steps.where((s) => !done.contains(s)).firstOrNull;
}

String getStartedHiddenKey(String companyId) => 'get_started_hidden:$companyId';

/// Works out the steps from the records on the phone.
Future<GetStartedProgress> loadGetStarted(
  AppDatabase db, {
  required String companyId,
  required List<Project> projects,
  required bool cloud,
}) async {
  final sampleId = await sampleProjectId(db, companyId);
  final own = projects.where((p) => p.id != sampleId).toList()
    ..sort((a, b) {
      final running = (b.status == 'active' ? 1 : 0) - (a.status == 'active' ? 1 : 0);
      return running != 0 ? running : b.createdAt.compareTo(a.createdAt);
    });
  final ids = own.map((p) => p.id).toList();
  final done = <GetStartedStep>{if (own.isNotEmpty) GetStartedStep.site};
  if (ids.isNotEmpty) {
    final attendance =
        await (db.select(db.labourAttendance)..where((t) => t.projectId.isIn(ids))..limit(1)).get();
    if (attendance.isNotEmpty) done.add(GetStartedStep.attendance);
    final reports = await (db.select(db.dprEntries)..where((t) => t.projectId.isIn(ids))..limit(1)).get();
    if (reports.isNotEmpty) done.add(GetStartedStep.report);
  }
  if (cloud) {
    // Sent the code, or someone has already joined.
    final roster = await loadRoster(db, companyId);
    if (roster.length > 1 || await inviteShared(db, companyId)) done.add(GetStartedStep.team);
  }
  return GetStartedProgress(
    steps: [GetStartedStep.site, GetStartedStep.attendance, GetStartedStep.report, if (cloud) GetStartedStep.team],
    done: done,
    hidden: (await db.settingsDao.get(getStartedHiddenKey(companyId))) == '1',
    site: own.firstOrNull,
  );
}

final getStartedProvider = FutureProvider.autoDispose.family<GetStartedProgress, String>((ref, companyId) async {
  final db = ref.watch(appDatabaseProvider);
  final cloud = ref.watch(cloudSyncAvailableProvider);
  final projects = await ref.watch(projectsProvider(companyId).future);
  return loadGetStarted(db, companyId: companyId, projects: projects, cloud: cloud);
});

String getStartedLabel(GetStartedStep step) => switch (step) {
      GetStartedStep.site => tr('Add your first site'),
      GetStartedStep.attendance => tr("Mark today's attendance"),
      GetStartedStep.report => tr("Send today's daily report"),
      GetStartedStep.team => tr('Invite your team'),
    };

String getStartedHint(GetStartedStep step) => switch (step) {
      GetStartedStep.site => tr('Its name is enough to start.'),
      GetStartedStep.attendance => tr('Who came to site today. Wages work out from it.'),
      GetStartedStep.report => tr('Speak it in your language; FieldOS writes it up.'),
      GetStartedStep.team => tr('Send the join code to your engineers on WhatsApp.'),
    };

class GetStartedCard extends ConsumerWidget {
  const GetStartedCard({super.key, required this.companyId, required this.onNewSite});

  final String companyId;

  /// Opens the new-site sheet (Home's own flow).
  final Future<void> Function() onNewSite;

  Future<void> _open(BuildContext context, WidgetRef ref, GetStartedProgress p, GetStartedStep step) async {
    final nav = Navigator.of(context);
    switch (step) {
      case GetStartedStep.site:
        await onNewSite();
      case GetStartedStep.attendance || GetStartedStep.report:
        final site = p.site;
        if (site == null) {
          await onNewSite();
        } else {
          await nav.push(MaterialPageRoute<void>(
              builder: (_) =>
                  ProjectDetailScreen(project: site, initialTab: step == GetStartedStep.attendance ? 5 : 1)));
        }
      case GetStartedStep.team:
        await nav.push(MaterialPageRoute<void>(builder: (_) => const TeamSyncScreen()));
    }
    ref.invalidate(getStartedProvider(companyId));
  }

  Future<void> _hide(WidgetRef ref) async {
    await ref.read(appDatabaseProvider).settingsDao.set(getStartedHiddenKey(companyId), '1');
    ref.invalidate(getStartedProvider(companyId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Roles.canApprove(ref.watch(sessionProvider).role)) return const SizedBox.shrink();
    final p = ref.watch(getStartedProvider(companyId)).value;
    if (p == null || p.hidden) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final next = p.next;
    return Card(
      key: const Key('get-started'),
      margin: const EdgeInsets.only(top: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Mitra(mood: p.finished ? MitraMood.celebrate : MitraMood.checklist, size: 64),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.finished ? tr('Your site is running on FieldOS') : tr('Get your first site running'),
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    p.finished
                        ? tr('Every step done. Your evening report will be ready on time.')
                        : trf('{done} of {total} done · about 5 minutes',
                            {'done': p.doneCount, 'total': p.steps.length}),
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ]),
              ),
              IconButton(
                key: const Key('get-started-hide'),
                tooltip: tr('Hide'),
                icon: const Icon(Icons.close),
                onPressed: () => _hide(ref),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: p.doneCount / p.steps.length,
                  minHeight: 6,
                  semanticsLabel: tr('Getting started'),
                ),
              ),
            ),
            if (!p.finished)
              for (final step in p.steps)
                _StepRow(
                  step: step,
                  done: p.done.contains(step),
                  isNext: step == next,
                  onTap: p.done.contains(step) ? null : () => _open(context, ref, p, step),
                )
            else
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: TextButton(onPressed: () => _hide(ref), child: Text(tr('Done'))),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.done, required this.isNext, required this.onTap});

  final GetStartedStep step;
  final bool done;
  final bool isNext;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = getStartedLabel(step);
    return Semantics(
      checked: done,
      button: !done,
      child: InkWell(
        key: ValueKey('get-started-${step.name}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(children: [
              Icon(
                done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                color: done ? scheme.primary : (isNext ? scheme.primary : scheme.outline),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      decoration: done ? TextDecoration.lineThrough : null,
                      color: done ? scheme.onSurfaceVariant : null,
                    ),
                  ),
                  if (isNext)
                    Text(getStartedHint(step),
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ]),
              ),
              if (!done) Icon(Icons.chevron_right, color: isNext ? scheme.primary : scheme.onSurfaceVariant),
            ]),
          ),
        ),
      ),
    );
  }
}
