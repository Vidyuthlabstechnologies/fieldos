/// Every open task across the company's sites in one list, grouped by when
/// it is due, so a site engineer sees what is theirs without opening each
/// project. With Team & sync on it starts on the tasks given to you.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/project/project_detail_screen.dart';
import 'package:fieldos_mobile/features/project/task_plan.dart';
import 'package:fieldos_mobile/features/project/tasks_tab.dart';
import 'package:fieldos_mobile/features/tasks/team_roster.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

enum TaskGroup { late, thisWeek, later, noDate }

const taskGroupTitles = {
  TaskGroup.late: 'Late',
  TaskGroup.thisWeek: 'Due in the next 7 days',
  TaskGroup.later: 'Later',
  TaskGroup.noDate: 'No due date',
};

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

TaskGroup groupOf(Task t, DateTime now) {
  if (isLate(t, now)) return TaskGroup.late;
  if (t.dueDate == null) return TaskGroup.noDate;
  return _day(t.dueDate!).difference(_day(now)).inDays <= 7 ? TaskGroup.thisWeek : TaskGroup.later;
}

/// Open tasks grouped for the list, each group in the Tasks tab's order.
/// [mine] keeps only the ones assigned to [myUserId].
Map<TaskGroup, List<Task>> groupTasks(Iterable<Task> tasks, DateTime now, {String? myUserId, bool mine = false}) {
  final picked = tasks.where((t) => isOpen(t) && (!mine || (myUserId != null && t.assigneeId == myUserId)));
  final out = <TaskGroup, List<Task>>{};
  for (final t in sortTasks(picked, now)) {
    out.putIfAbsent(groupOf(t, now), () => []).add(t);
  }
  out[TaskGroup.late]?.sort((a, b) => daysLate(b, now).compareTo(daysLate(a, now)));
  return {for (final g in TaskGroup.values) if (out[g] != null) g: out[g]!};
}

class MyTasksScreen extends ConsumerStatefulWidget {
  const MyTasksScreen({super.key, required this.companyId});
  final String companyId;

  @override
  ConsumerState<MyTasksScreen> createState() => _MyTasksScreenState();
}

class _MyTasksScreenState extends ConsumerState<MyTasksScreen> {
  bool? _mine;

  void _refresh() {
    ref.invalidate(openTasksProvider(widget.companyId));
  }

  Future<void> _open(Task t, Project? project, TeamRoster roster) async {
    final result = await showTaskSheet(context, existing: t, roster: roster);
    if (result == null || !mounted) return;
    if (result.id.present && result.id.value == duplicateMarker) {
      // Copies are made from the site's own Tasks tab.
      if (project != null) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: project)));
      }
    } else {
      await ref.read(appDatabaseProvider).taskDao.edit(t.id, result);
    }
    ref.invalidate(tasksProvider(t.projectId));
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(openTasksProvider(widget.companyId));
    final projects = ref.watch(projectsProvider(widget.companyId)).value ?? const <Project>[];
    final roster = ref.watch(teamRosterProvider(widget.companyId)).value ??
        const TeamRoster(members: [], myUserId: null);
    final canFilter = roster.myUserId != null;
    final mine = canFilter && (_mine ?? true);
    final byId = {for (final p in projects) p.id: p};
    final now = DateTime.now();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(tr('My tasks'))),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: tasksAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => EmptyState(icon: Icons.error_outline, title: tr('Could not load tasks'), message: '$e'),
          data: (tasks) {
            final groups = groupTasks(tasks, now, myUserId: roster.myUserId, mine: mine);
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
              children: [
                if (canFilter) ...[
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(value: true, label: Text(tr('Given to me'))),
                      ButtonSegment(value: false, label: Text(tr('Everyone'))),
                    ],
                    selected: {mine},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _mine = s.first),
                  ),
                  const SizedBox(height: 8),
                ] else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Text(
                      tr('Open tasks from all your sites. Turn on Team & sync to give tasks to people.'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                if (groups.isEmpty)
                  EmptyState(
                    compact: true,
                    icon: Icons.task_alt,
                    title: mine ? tr('Nothing given to you') : tr('No open tasks'),
                    message: mine
                        ? tr('Tasks someone gives you on any site show here.')
                        : tr('Add tasks from a project\'s Tasks tab.'),
                  ),
                for (final e in groups.entries) ...[
                  SectionHeader('${tr(taskGroupTitles[e.key]!)} (${e.value.length})'),
                  for (final t in e.value)
                    TaskCard(
                      task: t,
                      now: now,
                      site: byId[t.projectId]?.name,
                      assignee: mine ? null : roster.labelFor(t.assigneeId),
                      onTap: () => _open(t, byId[t.projectId], roster),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
