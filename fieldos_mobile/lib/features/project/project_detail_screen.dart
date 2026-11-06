import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/core/brand.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/project/dpr_draft_screen.dart';
import 'package:fieldos_mobile/features/project/new_project_sheet.dart';
import 'package:fieldos_mobile/features/project/project_status.dart';
import 'package:fieldos_mobile/features/project/voice_report_sheet.dart';
import 'package:fieldos_mobile/features/chat/project_chat_view.dart';
import 'package:fieldos_mobile/features/labour/labour_screen.dart';
import 'package:fieldos_mobile/features/procurement/procurement_screen.dart';
import 'package:fieldos_mobile/features/reports/dpr_report.dart';
import 'package:fieldos_mobile/features/equipment/equipment_screen.dart';
import 'package:fieldos_mobile/features/inspections/inspections_screen.dart';
import 'package:fieldos_mobile/features/documents/documents_screen.dart';
import 'package:fieldos_mobile/features/workers/workers_screen.dart';
import 'package:fieldos_mobile/features/estimation/estimation_screen.dart';
import 'package:fieldos_mobile/features/money/money_view.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

class ProjectDetailScreen extends ConsumerStatefulWidget {
  const ProjectDetailScreen({super.key, required this.project});
  final Project project;

  @override
  ConsumerState<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late String _status = widget.project.status;
  void Function()? _liveUpdateCallback;
  void Function()? _liveDprUpdateCallback;
  void Function()? _liveIssuesUpdateCallback;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 12, vsync: this);
    _maybeSubscribeToLiveUpdates();
  }

  /// If cloud sync is on, subscribe to live Realtime updates for this
  /// project's tasks so a colleague's change on another device shows up
  /// here without waiting for the next periodic/manual sync. Offline-only
  /// users (the default) never touch the network here at all.
  Future<void> _maybeSubscribeToLiveUpdates() async {
    final service = ref.read(cloudSyncServiceProvider);
    if (!service.isSignedIn) return;
    final engine = ref.read(cloudSyncEngineProvider);
    
    // Tasks realtime
    _liveUpdateCallback = () {
      if (mounted) ref.invalidate(tasksProvider(widget.project.id));
    };
    engine.onTasksChanged = _liveUpdateCallback;
    
    // DPR entries realtime
    _liveDprUpdateCallback = () {
      if (mounted) ref.invalidate(dprProvider(widget.project.id));
    };
    engine.onDprEntriesChanged = _liveDprUpdateCallback;
    
    // Issues realtime
    _liveIssuesUpdateCallback = () {
      if (mounted) ref.invalidate(issuesProvider(widget.project.id));
    };
    engine.onIssuesChanged = _liveIssuesUpdateCallback;
    
    try {
      await engine.subscribeToProjectTasks(widget.project.id);
      await engine.subscribeToProjectDprEntries(widget.project.id);
      await engine.subscribeToProjectIssues(widget.project.id);
    } catch (_) {
      // A failed live-update subscription shouldn't block viewing the
      // project -- the periodic/manual sync paths still cover this data,
      // just without the immediate push. Nothing to surface here that the
      // user could act on from this screen.
    }
  }

  @override
  void dispose() {
    // Only clears the callback if it's still ours -- the underlying
    // SyncEngine is a single app-wide instance (see cloud_sync_providers.dart),
    // so if the user already navigated to a different project screen before
    // this one finished disposing, that screen's initState may have already
    // replaced onTasksChanged with its own callback; clearing unconditionally
    // here would wipe out the newer, still-active one. Leaving the
    // subscription itself open (not unsubscribing) keeps this project's data
    // fresh in the background even after navigating away -- the same "keep
    // syncing" philosophy as PeriodicSyncTrigger.
    final engine = ref.read(cloudSyncEngineProvider);
    if (identical(engine.onTasksChanged, _liveUpdateCallback)) {
      engine.onTasksChanged = null;
    }
    if (identical(engine.onDprEntriesChanged, _liveDprUpdateCallback)) {
      engine.onDprEntriesChanged = null;
    }
    if (identical(engine.onIssuesChanged, _liveIssuesUpdateCallback)) {
      engine.onIssuesChanged = null;
    }
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _changeStage() async {
    final next = await showProjectStatusSheet(context, current: _status);
    if (next == null || !mounted) return;
    try {
      await ref.read(appDatabaseProvider).projectDao.setStatus(widget.project.id, next);
      if (!mounted) return;
      setState(() => _status = next);
      ref.invalidate(projectsProvider(widget.project.companyId));
      showSnack(context, '${widget.project.name}: ${projectStatusLabel(next).toLowerCase()}');
    } catch (e, st) {
      if (mounted) showSnack(context, friendlyError(e, st), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.project.name),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) {
              if (v == 'stage') _changeStage();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'stage',
                child: ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('Project stage'),
                  subtitle: Text(projectStatusLabel(_status)),
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          // These tabs sit on the navy bar, so they set their own colours
          // rather than the theme's on-page ones.
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Brand.amber,
          indicatorWeight: 3,
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: 'Tasks', icon: Icon(Icons.checklist)),
            Tab(text: 'DPR', icon: Icon(Icons.edit_note)),
            Tab(text: 'Issues', icon: Icon(Icons.report_problem)),
            Tab(text: 'Chat', icon: Icon(Icons.forum)),
            Tab(text: 'Procure', icon: Icon(Icons.shopping_cart)),
            Tab(text: 'Labour', icon: Icon(Icons.people)),
            Tab(text: 'Money', icon: Icon(Icons.currency_rupee)),
            Tab(text: 'Equipment', icon: Icon(Icons.construction)),
            Tab(text: 'Inspections', icon: Icon(Icons.fact_check)),
            Tab(text: 'Documents', icon: Icon(Icons.folder)),
            Tab(text: 'Workers', icon: Icon(Icons.badge)),
            Tab(text: 'Estimation', icon: Icon(Icons.calculate)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _TasksTab(project: widget.project),
          _DprTab(project: widget.project),
          _IssuesTab(project: widget.project),
          ProjectChatView(projectId: widget.project.id),
          Builder(
            builder: (context) {
              final userId = ref.watch(sessionProvider).user?.id ?? '';
              return ProcurementView(
                projectId: widget.project.id,
                companyId: widget.project.companyId,
                userId: userId,
              );
            },
          ),
          Builder(
            builder: (context) {
              final userId = ref.watch(sessionProvider).user?.id ?? '';
              return LabourView(
                projectId: widget.project.id,
                companyId: widget.project.companyId,
                userId: userId,
              );
            },
          ),
          Builder(
            builder: (context) => MoneyView(
              projectId: widget.project.id,
              userId: ref.watch(sessionProvider).user?.id ?? '',
            ),
          ),
          Builder(
            builder: (context) {
              final userId = ref.watch(sessionProvider).user?.id ?? '';
              return EquipmentView(
                projectId: widget.project.id,
                userId: userId,
              );
            },
          ),
          Builder(
            builder: (context) {
              final userId = ref.watch(sessionProvider).user?.id ?? '';
              return InspectionsView(
                projectId: widget.project.id,
                userId: userId,
              );
            },
          ),
          Builder(
            builder: (context) {
              final userId = ref.watch(sessionProvider).user?.id ?? '';
              return DocumentsView(
                projectId: widget.project.id,
                userId: userId,
              );
            },
          ),
          Builder(
            builder: (context) {
              final userId = ref.watch(sessionProvider).user?.id ?? '';
              return WorkersView(
                projectId: widget.project.id,
                userId: userId,
              );
            },
          ),
          Builder(
            builder: (context) {
              final userId = ref.watch(sessionProvider).user?.id ?? '';
              return EstimationView(
                projectId: widget.project.id,
                userId: userId,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TasksTab extends ConsumerWidget {
  const _TasksTab({required this.project});
  final Project project;

  static const _statusLabels = {'todo': 'To do', 'in_progress': 'In progress', 'done': 'Done'};

  Future<void> _addTask(BuildContext context, WidgetRef ref) async {
    final titleC = TextEditingController();
    DateTime? dueDate;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('New task'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleC,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'What needs doing?'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today),
                label: Text(dueDate == null ? 'Due date (optional)' : 'Due ${fmtDate(dueDate!)}'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                  );
                  if (picked != null) setDialogState(() => dueDate = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, titleC.text.trim().isNotEmpty),
              child: const Text('Add task'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await ref.read(appDatabaseProvider).taskDao.create(TasksCompanion.insert(
          id: const Uuid().v4(),
          projectId: project.id,
          title: titleC.text.trim(),
          dueDate: Value(dueDate),
        ));
    ref.invalidate(tasksProvider(project.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider(project.id));
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () async => ref.invalidate(tasksProvider(project.id)),
          child: tasks.when(
            data: (items) {
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.checklist,
                  title: 'No tasks yet',
                  message: 'Add the jobs for this site so everyone knows what is next and what is late.',
                  actionLabel: 'Add a task',
                  onAction: () => _addTask(context, ref),
                );
              }
              // Open work first, soonest due first; done at the bottom.
              final sorted = [...items]..sort((a, b) {
                  final ad = a.status == 'done' ? 1 : 0, bd = b.status == 'done' ? 1 : 0;
                  if (ad != bd) return ad - bd;
                  final ax = a.dueDate ?? DateTime(9999), bx = b.dueDate ?? DateTime(9999);
                  return ax.compareTo(bx);
                });
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                itemCount: sorted.length,
                itemBuilder: (_, i) {
                  final t = sorted[i];
                  final overdue = t.status != 'done' && t.dueDate != null && t.dueDate!.isBefore(startOfToday);
                  return Card(
                    child: ListTile(
                      title: Text(
                        t.title,
                        style: t.status == 'done'
                            ? TextStyle(decoration: TextDecoration.lineThrough, color: Theme.of(context).colorScheme.onSurfaceVariant)
                            : null,
                      ),
                      subtitle: t.dueDate == null
                          ? null
                          : Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(children: [
                                Text('Due ${fmtDate(t.dueDate!, short: true)}'),
                                if (overdue) ...[const SizedBox(width: 8), const StatusPill('Late', tone: PillTone.danger)],
                              ]),
                            ),
                      trailing: DropdownButton<String>(
                        value: _statusLabels.containsKey(t.status) ? t.status : 'todo',
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final e in _statusLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                        ],
                        onChanged: (s) async {
                          if (s == null) return;
                          await ref.read(appDatabaseProvider).taskDao.updateStatus(t.id, s);
                          ref.invalidate(tasksProvider(project.id));
                        },
                      ),
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => ErrorState(error: e, stack: st, onRetry: () => ref.invalidate(tasksProvider(project.id))),
          ),
        ),
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton.extended(
            heroTag: 'task_add',
            icon: const Icon(Icons.add),
            label: const Text('Add task'),
            onPressed: () => _addTask(context, ref),
          ),
        ),
      ],
    );
  }
}

class _DprTab extends ConsumerStatefulWidget {
  const _DprTab({required this.project});
  final Project project;

  @override
  ConsumerState<_DprTab> createState() => _DprTabState();
}

class _DprTabState extends ConsumerState<_DprTab> {
  /// Speak the report: the phone listens, then the draft screen checks it.
  Future<void> _speak() async {
    final report = await showVoiceReportSheet(context);
    if (report == null || !mounted) return;
    final draft = await openDprDraft(
      context,
      project: widget.project,
      text: report.text,
      spokenIn: report.typeInstead ? null : report.language,
      viaSarvam: report.viaSarvam,
    );
    if (draft != null) await _persist(draft, source: report.typeInstead ? 'manual' : 'voice');
  }

  Future<void> _type() async {
    final draft = await openDprDraft(context, project: widget.project);
    if (draft != null) await _persist(draft, source: 'manual');
  }

  /// Saves the DPR, its photos and the problems the person kept, each
  /// issue linked back to the report that raised it.
  Future<void> _persist(DprDraftResult draft, {required String source}) async {
    final user = ref.read(sessionProvider).user;
    if (user == null) return;
    final db = ref.read(appDatabaseProvider);
    try {
      final dprId = const Uuid().v4();
      final dpr = await db.dprDao.create(DprEntriesCompanion.insert(
        id: dprId,
        projectId: widget.project.id,
        createdBy: user.id,
        entryDate: draft.date,
        workSummary: draft.summary,
        manpowerCount: Value(draft.manpower),
        weather: Value(draft.weather),
        source: Value(source),
      ));
      for (final iss in draft.issues) {
        await db.issueDao.create(IssuesCompanion.insert(
          id: const Uuid().v4(),
          projectId: widget.project.id,
          dprEntryId: Value(dprId),
          description: iss,
          severity: const Value('medium'),
          status: const Value('open'),
        ));
      }
      for (final path in draft.photoPaths) {
        await db.dprDao.addPhoto(DprPhotosCompanion.insert(id: const Uuid().v4(), dprEntryId: dprId, photoPath: path));
      }
      ref.invalidate(dprProvider(widget.project.id));
      ref.invalidate(issuesProvider(widget.project.id));
      if (!mounted) return;
      final raised = draft.issues.length;
      showSnack(
        context,
        raised == 0 ? 'Report saved.' : 'Report saved, and $raised problem${raised == 1 ? '' : 's'} raised as issues.',
        action: SnackBarAction(label: 'Share', onPressed: () => _share(dpr)),
      );
    } catch (e, st) {
      if (mounted) showSnack(context, friendlyError(e, st), error: true);
    }
  }

  Future<void> _share(DprEntry d) async {
    try {
      await shareDprReport(
        db: ref.read(appDatabaseProvider),
        companyName: ref.read(sessionProvider).activeCompany?.name ?? '',
        project: widget.project,
        dpr: d,
      );
    } catch (e, st) {
      if (mounted) showSnack(context, 'Could not share the report. ${friendlyError(e, st)}', error: true);
    }
  }

  void _showDetails(DprEntry d, int issueCount) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('${fmtDay(d.entryDate)} · ${fmtDate(d.entryDate)}', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            _DprFacts(dpr: d, issueCount: issueCount),
            const SizedBox(height: 16),
            SelectableText(d.workSummary, style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(height: 1.45)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _share(d);
              },
              icon: const Icon(Icons.ios_share),
              label: const Text('Share as PDF'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dpr = ref.watch(dprProvider(widget.project.id));
    final issues = ref.watch(issuesProvider(widget.project.id)).valueOrNull ?? const <Issue>[];
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () async => ref.invalidate(dprProvider(widget.project.id)),
          child: dpr.when(
            data: (items) {
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.mic_none,
                  title: 'No daily reports yet',
                  message: 'Speak today\'s progress in your own language. FieldOS fills in the headcount, '
                      'the weather and any problems for you, even without internet.',
                  actionLabel: 'Speak a report',
                  onAction: _speak,
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 168),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final d = items[i];
                  final issueCount = issues.where((x) => x.dprEntryId == d.id).length;
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _showDetails(d, issueCount),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                child: Text(
                                  '${fmtDay(d.entryDate)} · ${fmtDate(d.entryDate, short: true)}',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              if (d.source == 'voice')
                                Tooltip(
                                  message: 'Spoken report',
                                  child: Icon(Icons.mic_none, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                              IconButton(
                                icon: const Icon(Icons.ios_share),
                                tooltip: 'Share as PDF',
                                onPressed: () => _share(d),
                              ),
                            ]),
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Text(d.workSummary, maxLines: 3, overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(height: 10),
                            _DprFacts(dpr: d, issueCount: issueCount),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => ErrorState(error: e, stack: st, onRetry: () => ref.invalidate(dprProvider(widget.project.id))),
          ),
        ),
        Positioned(
          bottom: 16,
          right: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.small(
                heroTag: 'dpr_type',
                tooltip: 'Type a report',
                onPressed: _type,
                child: const Icon(Icons.keyboard_alt_outlined),
              ),
              const SizedBox(height: 12),
              FloatingActionButton.extended(
                heroTag: 'dpr_voice',
                icon: const Icon(Icons.mic),
                label: const Text('Speak report'),
                onPressed: _speak,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// People, weather and issues of a report, as small labels.
class _DprFacts extends StatelessWidget {
  const _DprFacts({required this.dpr, required this.issueCount});
  final DprEntry dpr;
  final int issueCount;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        StatusPill(dpr.manpowerCount > 0 ? '${dpr.manpowerCount} people' : 'Headcount not given'),
        if (dpr.weather != null && dpr.weather!.isNotEmpty) StatusPill(dpr.weather!),
        if (issueCount > 0) StatusPill('$issueCount issue${issueCount == 1 ? '' : 's'}', tone: PillTone.warn),
      ],
    );
  }
}

class _IssuesTab extends ConsumerWidget {
  const _IssuesTab({required this.project});
  final Project project;

  static const _severityTone = {'high': PillTone.danger, 'medium': PillTone.warn, 'low': PillTone.neutral};

  Future<void> _addIssue(BuildContext context, WidgetRef ref) async {
    final descC = TextEditingController();
    String severity = 'medium';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('New issue'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: descC,
                maxLines: 3,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'What is the problem?'),
              ),
              const SizedBox(height: 16),
              const Text('How serious?'),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'low', label: Text('Low')),
                  ButtonSegment(value: 'medium', label: Text('Medium')),
                  ButtonSegment(value: 'high', label: Text('High')),
                ],
                selected: {severity},
                onSelectionChanged: (s) => setDialogState(() => severity = s.first),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, descC.text.trim().isNotEmpty),
              child: const Text('Raise issue'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await ref.read(appDatabaseProvider).issueDao.create(IssuesCompanion.insert(
          id: const Uuid().v4(),
          projectId: project.id,
          description: descC.text.trim(),
          severity: Value(severity),
        ));
    ref.invalidate(issuesProvider(project.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issues = ref.watch(issuesProvider(project.id));
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () async => ref.invalidate(issuesProvider(project.id)),
          child: issues.when(
            data: (items) {
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.verified_outlined,
                  title: 'No issues',
                  message: 'Problems you raise, or that FieldOS finds in your daily reports, appear here until they are fixed.',
                  actionLabel: 'Raise an issue',
                  onAction: () => _addIssue(context, ref),
                );
              }
              final sorted = [...items]..sort((a, b) {
                  final ar = a.status == 'resolved' ? 1 : 0, br = b.status == 'resolved' ? 1 : 0;
                  if (ar != br) return ar - br;
                  return b.createdAt.compareTo(a.createdAt);
                });
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                itemCount: sorted.length,
                itemBuilder: (_, i) {
                  final iss = sorted[i];
                  final resolved = iss.status == 'resolved';
                  return Card(
                    child: ListTile(
                      title: Text(iss.description),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          StatusPill(
                            '${iss.severity[0].toUpperCase()}${iss.severity.substring(1)}',
                            tone: _severityTone[iss.severity] ?? PillTone.neutral,
                          ),
                          if (iss.dprEntryId != null) const StatusPill('From a daily report'),
                          Text(
                            resolved && iss.resolvedAt != null
                                ? 'Fixed ${fmtDate(iss.resolvedAt!, short: true)}'
                                : 'Raised ${fmtDate(iss.createdAt, short: true)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ]),
                      ),
                      trailing: resolved
                          ? const Icon(Icons.check_circle, color: Brand.ok)
                          : TextButton(
                              onPressed: () async {
                                await ref.read(appDatabaseProvider).issueDao.resolve(iss.id);
                                ref.invalidate(issuesProvider(project.id));
                              },
                              child: const Text('Mark fixed'),
                            ),
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => ErrorState(error: e, stack: st, onRetry: () => ref.invalidate(issuesProvider(project.id))),
          ),
        ),
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton.extended(
            heroTag: 'issue_add',
            icon: const Icon(Icons.add),
            label: const Text('Raise issue'),
            onPressed: () => _addIssue(context, ref),
          ),
        ),
      ],
    );
  }
}
