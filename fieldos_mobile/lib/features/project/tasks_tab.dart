/// The project's Tasks tab: progress bars, the delay view (what is late or
/// heading late, by how many days) and the look-ahead list of what starts
/// or falls due in the next two weeks.
library;

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/auth/auth_service.dart' show Roles;
import 'package:fieldos_mobile/core/date_pick.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/features/execution/activity_templates.dart';
import 'package:fieldos_mobile/services/location_service.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/project/task_plan.dart';
import 'package:fieldos_mobile/features/tasks/team_roster.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/l10n/language.dart';

/// The server also has "blocked" (waiting on something outside the team:
/// a drawing, a payment, the client); it was shown as "To do".
const taskStatusLabels = {'todo': 'To do', 'in_progress': 'In progress', 'blocked': 'Blocked', 'done': 'Done'};

enum TaskView { all, late, next14 }

final taskChecksProvider = FutureProvider.autoDispose.family<Set<String>, String>((ref, projectId) async {
  final checks = await ref.watch(appDatabaseProvider).siteOpsDao.checksFor(projectId);
  return {for (final c in checks) c.taskId};
});

class TasksTab extends ConsumerStatefulWidget {
  const TasksTab({super.key, required this.project});
  final Project project;

  @override
  ConsumerState<TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends ConsumerState<TasksTab> {
  TaskView _view = TaskView.all;

  String get _projectId => widget.project.id;

  void _refresh() {
    ref.invalidate(tasksProvider(_projectId));
    ref.invalidate(openTasksProvider(widget.project.companyId));
  }

  Future<void> _add() async {
    final roster = await ref.read(teamRosterProvider(widget.project.companyId).future);
    if (!mounted) return;
    final c = await showTaskSheet(context, roster: roster);
    if (c == null) return;
    await ref.read(appDatabaseProvider).taskDao.create(c.copyWith(id: Value(const Uuid().v4()), projectId: Value(_projectId)));
    _refresh();
  }

  Future<void> _open(Task t) async {
    final roster = await ref.read(teamRosterProvider(widget.project.companyId).future);
    if (!mounted) return;
    final result = await showTaskSheet(context, existing: t, roster: roster);
    if (result == null) return;
    final dao = ref.read(appDatabaseProvider).taskDao;
    if (result.id.present && result.id.value == duplicateMarker) {
      await dao.create(TasksCompanion.insert(
        id: const Uuid().v4(),
        projectId: _projectId,
        title: _copyTitle(t.title),
        dueDate: Value(t.dueDate),
        startDate: Value(t.startDate),
        priority: Value(t.priority),
        assigneeId: Value(t.assigneeId),
      ));
      if (mounted) showSnack(context, 'Copied. The copy starts at 0%.');
    } else {
      try {
        await dao.edit(t.id, result, asManager: Roles.canApprove(ref.read(sessionProvider).role));
      } on ExecutionRefused catch (e) {
        if (mounted) showSnack(context, e.message, error: true);
      }
    }
    _refresh();
  }

  Future<void> _verify(Task t) async {
    try {
      final fix = await LocationService().currentFix();
      await ref.read(appDatabaseProvider).siteOpsDao.verifyTask(t.id,
          lat: fix.lat, lng: fix.lng, accuracyM: fix.accuracyM, by: ref.read(sessionProvider).user!.id);
      ref.invalidate(taskChecksProvider(_projectId));
      if (mounted) showSnack(context, tr('Verified on site. You can now mark it done.'));
    } on ExecutionRefused catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } on LocationUnavailable catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, trf('Could not save: {error}', {'error': '$e'}), error: true);
    }
  }

  Future<void> _stages() async {
    final picked = <String>{};
    var start = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Add stage checklist')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(tr('Each step becomes a task that needs an on-site check before it can be marked 100%.')),
              for (final st in activityStages)
                CheckboxListTile(
                  key: Key('stage-${st.id}'),
                  contentPadding: EdgeInsets.zero,
                  value: picked.contains(st.id),
                  title: Text(tr(st.title)),
                  subtitle: Text(trf('{n} steps', {'n': st.steps.length})),
                  onChanged: (v) => set(() => v == true ? picked.add(st.id) : picked.remove(st.id)),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text(trf('Start {date}', {'date': fmtDate(start, short: true)})),
                onTap: () async {
                  final now = DateTime.now();
                  final d = await pickDate(ctx, initial: start, first: now.subtract(const Duration(days: 365)), last: now.add(const Duration(days: 1095)));
                  if (d != null) set(() => start = d);
                },
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(key: const Key('stages-save'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Add tasks'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final n = await ref.read(appDatabaseProvider).siteOpsDao.addStageChecklist(
          projectId: _projectId, stageIds: [for (final st in activityStages) if (picked.contains(st.id)) st.id], start: start);
      _refresh();
      if (mounted) showSnack(context, trf('{n} tasks added.', {'n': n}));
    } on ExecutionRefused catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksProvider(_projectId));
    final roster = ref.watch(teamRosterProvider(widget.project.companyId)).value;
    final now = DateTime.now();
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: tasks.when(
            data: (items) {
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.checklist,
                  title: tr('No tasks yet'),
                  message: tr('Add the jobs for this site so everyone knows what is next and what is late.'),
                  actionLabel: tr('Add a task'),
                  onAction: _add,
                );
              }
              final lateCount = items.where((t) => isLate(t, now)).length;
              final shown = switch (_view) {
                TaskView.all => sortTasks(items, now),
                TaskView.late => sortTasks(items.where((t) => isLate(t, now)), now)
                  ..sort((a, b) => daysLate(b, now).compareTo(daysLate(a, now))),
                TaskView.next14 => lookAhead(items, now, 14),
              };
              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                children: [
                  _ProgressHeader(tasks: items, lateCount: lateCount),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      key: const Key('stage-checklist'),
                      icon: const Icon(Icons.account_tree_outlined),
                      label: Text(tr('Add stage checklist')),
                      onPressed: _stages,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<TaskView>(
                    segments: [
                      ButtonSegment(value: TaskView.all, label: Text(tr('All'))),
                      ButtonSegment(value: TaskView.late, label: Text(lateCount > 0 ? trf('Late ({n})', {'n': lateCount}) : tr('Late'))),
                      ButtonSegment(value: TaskView.next14, label: Text(tr('Next 14 days'))),
                    ],
                    selected: {_view},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _view = s.first),
                  ),
                  const SizedBox(height: 8),
                  if (shown.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        switch (_view) {
                          TaskView.late => tr('Nothing is late. Tasks show here when they pass their due date, '
                              'or when their pace means they will finish after it.'),
                          TaskView.next14 => tr('Nothing starts or falls due in the next 14 days.'),
                          TaskView.all => '',
                        },
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  for (final t in shown)
                    TaskCard(
                      task: t,
                      now: now,
                      assignee: roster?.labelFor(t.assigneeId),
                      onTap: () => _open(t),
                      verified: (ref.watch(taskChecksProvider(_projectId)).value ?? const <String>{}).contains(t.id),
                      onVerify: t.verifyRequired && t.status != 'done' ? () => _verify(t) : null,
                    ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => ErrorState(error: e, stack: st, onRetry: _refresh),
          ),
        ),
        PositionedDirectional(
          bottom: 16,
          end: 16,
          child: FloatingActionButton.extended(
            heroTag: 'task_add',
            icon: const Icon(Icons.add),
            label: Text(tr('Add task')),
            onPressed: _add,
          ),
        ),
      ],
    );
  }
}

String _copyTitle(String title) {
  const suffix = ' (copy)';
  final base = title.length + suffix.length > 200 ? title.substring(0, 200 - suffix.length) : title;
  return '$base$suffix';
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.tasks, required this.lateCount});
  final List<Task> tasks;
  final int lateCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = projectProgress(tasks);
    final done = tasks.where((t) => t.status == 'done').length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(trf('{n}% complete', {'n': pct}), style: theme.textTheme.titleMedium)),
            if (lateCount > 0)
              Text(trf('{n} late', {'n': lateCount}),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: toneColor(context, PillTone.danger), fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: pct / 100, minHeight: 8),
          ),
          const SizedBox(height: 6),
          Text(trf('{done} of {total} tasks done', {'done': done, 'total': tasks.length}),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

/// One task: title, status, progress bar, dates and how late it is. Also
/// used on My tasks, where [site] names the project it belongs to.
class TaskCard extends StatelessWidget {
  const TaskCard({super.key, required this.task, required this.now, required this.onTap, this.assignee, this.site, this.verified = false, this.onVerify});
  final Task task;
  final DateTime now;
  final VoidCallback onTap;

  /// Who it is for ("You", a name), or null when nobody is named.
  final String? assignee;
  final String? site;

  /// The task needs an on-site check and has one; [onVerify] is set while
  /// it still needs one.
  final bool verified;
  final VoidCallback? onVerify;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = task;
    final done = t.status == 'done';
    final lateText = lateLabel(t, now);
    final forecast = forecastFinish(t, now);
    final pct = done ? 100 : t.progress;
    final dates = [
      if (t.startDate != null) trf('Start {date}', {'date': fmtDate(t.startDate!, short: true)}),
      if (t.dueDate != null) trf('Due {date}', {'date': fmtDate(t.dueDate!, short: true)}),
      if (forecast != null && t.dueDate != null) trf('Forecast {date}', {'date': fmtDate(forecast, short: true)}),
    ].join(' · ');
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (t.priority == 'high')
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6, top: 2),
                  child: Icon(Icons.flag_rounded, size: 16, color: toneColor(context, PillTone.warn)),
                ),
              Expanded(
                flex: 2,
                child: Text(
                  t.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    decoration: done ? TextDecoration.lineThrough : null,
                    color: done ? theme.colorScheme.onSurfaceVariant : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // The pill shrinks to fit rather than pushing the row off
              // screen when its word is long (Malayalam at 200% text).
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.topEnd,
                  child: StatusPill(taskStatusLabels[t.status] ?? 'To do',
                      tone: done
                          ? PillTone.ok
                          : (t.status == 'blocked'
                              ? PillTone.danger
                              : (t.status == 'in_progress' ? PillTone.warn : PillTone.neutral))),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(value: pct / 100, minHeight: 6),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 40, child: Text('$pct%', textAlign: TextAlign.end, style: theme.textTheme.bodySmall)),
            ]),
            if (site != null || assignee != null) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 12, runSpacing: 4, children: [
                if (site != null)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.domain_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(site!, style: theme.textTheme.bodySmall),
                  ]),
                if (assignee != null)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.person_outline, size: 14, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(tr(assignee!), style: theme.textTheme.bodySmall),
                  ]),
              ]),
            ],
            if (onVerify != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: verified
                    ? Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(tr('Verified on site'), style: theme.textTheme.bodySmall?.copyWith(color: toneColor(context, PillTone.ok))),
                      )
                    : TextButton.icon(
                        key: Key('verify-${t.id}'),
                        icon: const Icon(Icons.my_location, size: 18),
                        label: Text(tr('Verify on site')),
                        onPressed: onVerify,
                      ),
              ),
            if (dates.isNotEmpty || lateText != null) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (dates.isNotEmpty) Text(dates, style: theme.textTheme.bodySmall),
                if (lateText != null)
                  Text(lateText,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: toneColor(context, PillTone.danger), fontWeight: FontWeight.w600)),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Returned in place of an edit when the person taps Duplicate.
const duplicateMarker = '__duplicate__';

/// Add or edit a task. Returns the fields to write, a companion whose id is
/// [duplicateMarker] for Duplicate, or null when cancelled.
Future<TasksCompanion?> showTaskSheet(BuildContext context, {Task? existing, TeamRoster? roster}) {
  return showModalBottomSheet<TasksCompanion>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _TaskSheet(existing: existing, roster: roster),
  );
}

class _TaskSheet extends StatefulWidget {
  const _TaskSheet({this.existing, this.roster});
  final Task? existing;
  final TeamRoster? roster;

  @override
  State<_TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<_TaskSheet> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late String _priority = widget.existing?.priority ?? 'normal';
  late String _status = widget.existing?.status ?? 'todo';
  late double _progress = (widget.existing?.status == 'done' ? 100 : widget.existing?.progress ?? 0).toDouble();
  late DateTime? _start = widget.existing?.startDate;
  late DateTime? _due = widget.existing?.dueDate;
  late String? _assignee = widget.existing?.assigneeId;
  late bool _verify = widget.existing?.verifyRequired ?? false;
  String? _error;

  bool get _editing => widget.existing != null;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime? current, String help) {
    final now = DateTime.now();
    final first = now.subtract(const Duration(days: 365 * 2));
    final last = now.add(const Duration(days: 365 * 3));
    // A long job's dates can sit outside the usual range; the picker
    // refuses an initial date outside its own, so widen it to fit.
    return showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: current != null && current.isBefore(first) ? current : first,
      lastDate: current != null && current.isAfter(last) ? current : last,
      helpText: help,
    );
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = tr('Give the task a name.'));
      return;
    }
    if (_start != null && _due != null && _due!.isBefore(_start!)) {
      setState(() => _error = tr('The due date is before the start date.'));
      return;
    }
    final progress = _progress.round();
    // Keep status and progress agreeing: 100% is done, done is 100%.
    final status = progress >= 100 ? 'done' : (_status == 'done' ? 'in_progress' : (progress > 0 && _status == 'todo' ? 'in_progress' : _status));
    Navigator.pop(
      context,
      TasksCompanion(
        title: Value(title.length > 200 ? title.substring(0, 200) : title),
        priority: Value(_priority),
        status: Value(status),
        progress: Value(status == 'done' ? 100 : progress),
        startDate: Value(_start),
        dueDate: Value(_due),
        assigneeId: Value(_assignee),
        verifyRequired: Value(_verify),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_editing ? tr('Task') : tr('New task'), style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              autofocus: !_editing,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: tr('What needs doing?')),
            ),
            const SizedBox(height: 4),
            Text(tr('Priority'), style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: [for (final e in taskPriorities.entries) ButtonSegment(value: e.key, label: Text(e.value))],
              selected: {_priority},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _priority = s.first),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.play_arrow_outlined),
                  label: Text(_start == null ? tr('Start date') : trf('Start {date}', {'date': fmtDate(_start!, short: true)})),
                  onPressed: () async {
                    final d = await _pick(_start, tr('When does work start?'));
                    if (d != null) setState(() => _start = d);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.flag_outlined),
                  label: Text(_due == null ? tr('Due date') : trf('Due {date}', {'date': fmtDate(_due!, short: true)})),
                  onPressed: () async {
                    final d = await _pick(_due, tr('When must it be finished?'));
                    if (d != null) setState(() => _due = d);
                  },
                ),
              ),
            ]),
            if (widget.roster?.canAssign ?? false) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _assignee,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Assigned to'), prefixIcon: const Icon(Icons.person_outline)),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text(tr('Nobody yet'))),
                  for (final m in widget.roster!.members)
                    DropdownMenuItem<String?>(
                      value: m.userId,
                      child: Text(
                        m.userId == widget.roster!.myUserId ? '${tr('You')} (${m.email})' : m.email,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  // Someone who has since left the team keeps the task until it is moved.
                  if (_assignee != null && widget.roster!.byId(_assignee) == null)
                    DropdownMenuItem<String?>(value: _assignee, child: Text(tr('Someone on the team'))),
                ],
                onChanged: (v) => setState(() => _assignee = v),
              ),
            ],
            SwitchListTile(
              key: const Key('task-verify-required'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Needs an on-site check before 100%')),
              value: _verify,
              onChanged: (v) => setState(() => _verify = v),
            ),
            if (_editing) ...[
              const SizedBox(height: 16),
              Row(children: [
                Text(tr('Progress'), style: theme.textTheme.labelLarge),
                const Spacer(),
                Text('${_progress.round()}%', style: theme.textTheme.titleMedium),
              ]),
              Slider(
                value: _progress,
                max: 100,
                divisions: 20,
                label: '${_progress.round()}%',
                onChanged: (v) => setState(() => _progress = v),
              ),
              Text(tr('Status'), style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: [for (final e in taskStatusLabels.entries) ButtonSegment(value: e.key, label: Text(tr(e.value)))],
                selected: {_status},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() {
                  _status = s.first;
                  if (_status == 'done') _progress = 100;
                  if (_status != 'done' && _progress >= 100) _progress = 95;
                }),
              ),
            ],
            if (_error != null) ...[const SizedBox(height: 12), FormMessage(_error!)],
            const SizedBox(height: 20),
            FilledButton(onPressed: _save, child: Text(_editing ? tr('Save') : tr('Add task'))),
            if (_editing) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.copy_outlined),
                label: Text(tr('Duplicate this task')),
                onPressed: () => Navigator.pop(context, const TasksCompanion(id: Value(duplicateMarker))),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
