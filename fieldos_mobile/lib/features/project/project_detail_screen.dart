import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/features/project/site_notes_screen.dart';
import 'package:fieldos_mobile/features/portals/portal_share.dart';
import 'package:fieldos_mobile/core/brand.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/export/export_action.dart';
import 'package:fieldos_mobile/features/close/week_close_screen.dart';
import 'package:fieldos_mobile/features/daily/today_screen.dart';
import 'package:fieldos_mobile/features/commercial/commercial_screens.dart';
import 'package:fieldos_mobile/features/team/site_team_screen.dart';
import 'package:fieldos_mobile/features/money/measurement_book_screen.dart';
import 'package:fieldos_mobile/features/procurement/supplier_invoices_screen.dart';
import 'package:fieldos_mobile/features/reports/period_report_screen.dart';
import 'package:fieldos_mobile/features/shared/photo_viewer.dart';
import 'package:fieldos_mobile/features/project/dpr_draft_screen.dart';
import 'package:fieldos_mobile/features/project/new_project_sheet.dart';
import 'package:fieldos_mobile/features/project/project_status.dart';
import 'package:fieldos_mobile/features/project/tasks_tab.dart';
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
import 'package:fieldos_mobile/features/money/cash_book_screen.dart';
import 'package:fieldos_mobile/features/reports/pilot_scorecard_screen.dart';
import 'package:fieldos_mobile/features/reports/rera_screen.dart';
import 'package:fieldos_mobile/features/procurement/material_check_screen.dart';
import 'package:fieldos_mobile/features/money/entry_history_screen.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';
import 'package:fieldos_mobile/features/onboarding/sample_project.dart';
import 'package:fieldos_mobile/features/reminders/reminders.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/sync/sync_engine.dart';
import 'package:fieldos_mobile/services/company_plan.dart';

class ProjectDetailScreen extends ConsumerStatefulWidget {
  const ProjectDetailScreen({super.key, required this.project, this.initialTab = 0});
  final Project project;

  /// The tab to open on (0 tasks, 1 reports, 2 issues, 10 workers...).
  final int initialTab;

  @override
  ConsumerState<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late String _status = widget.project.status;
  void Function()? _liveUpdateCallback;
  void Function()? _liveDprUpdateCallback;
  void Function()? _liveIssuesUpdateCallback;

  /// The sync engine this screen hooked its callbacks onto, kept so
  /// [dispose] can unhook them without `ref` (which is gone by then).
  SyncEngine? _liveEngine;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 12, vsync: this, initialIndex: widget.initialTab.clamp(0, 11));
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
    _liveEngine = engine;

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
    final engine = _liveEngine;
    if (engine != null) {
      if (identical(engine.onTasksChanged, _liveUpdateCallback)) engine.onTasksChanged = null;
      if (identical(engine.onDprEntriesChanged, _liveDprUpdateCallback)) engine.onDprEntriesChanged = null;
      if (identical(engine.onIssuesChanged, _liveIssuesUpdateCallback)) engine.onIssuesChanged = null;
    }
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _changeStage() async {
    final next = await showProjectStatusSheet(context, current: _status);
    if (next == null || !mounted) return;
    try {
      final db = ref.read(appDatabaseProvider);
      // Reopening a completed site takes one of the company plan's sites.
      if (!countsAsActiveSite(_status) && countsAsActiveSite(next)) {
        final blocked = await newActiveSiteBlocked(db, widget.project.companyId, reopening: widget.project.id);
        if (blocked != null) {
          if (mounted) showSnack(context, blocked, error: true);
          return;
        }
      }
      await db.projectDao.setStatus(widget.project.id, next);
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
            tooltip: tr('More'),
            onSelected: (v) {
              if (v == 'stage') _changeStage();
              if (v == 'report') openPeriodReport(context, widget.project);
              if (v == 'today') openToday(context, widget.project);
              if (v == 'close') {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => WeekCloseScreen(project: widget.project, weekOf: DateTime.now()),
                ));
              }
              if (v == 'commercial') {
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => CommercialScreen(project: widget.project)));
              }
              if (v == 'measure') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => MeasurementBookScreen(project: widget.project)));
              }
              if (v == 'invoices') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => SupplierInvoicesScreen(project: widget.project)));
              }
              if (v == 'team') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => SiteTeamScreen(project: widget.project)));
              }
              if (v == 'excel') exportProjectToExcel(context, ref, widget.project);
              if (v == 'client') shareClientAccess(context, ref, widget.project);
              if (v == 'pilot') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => PilotScorecardScreen(project: widget.project)));
              }
              if (v == 'history') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => EntryHistoryScreen(project: widget.project)));
              }
              if (v == 'materialcheck') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => MaterialCheckScreen(project: widget.project)));
              }
              if (v == 'rera') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReraScreen(project: widget.project)));
              }
              if (v == 'cash') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => CashBookScreen(project: widget.project)));
              }
              if (v == 'notes') {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SiteNotesScreen(projectId: widget.project.id, siteName: widget.project.name),
                ));
              }
            },
            itemBuilder: (_) => [
              if (canSeeMoneyIn(ref.watch(sessionProvider).role))
                PopupMenuItem(
                  value: 'pilot',
                  child: ListTile(
                    leading: const Icon(Icons.insights_outlined),
                    title: Text(tr('Pilot scorecard')),
                  ),
                ),
              if (Roles.canApprove(ref.watch(sessionProvider).role))
                PopupMenuItem(
                  value: 'history',
                  child: ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(tr('Change history')),
                  ),
                ),
              if (Roles.canApprove(ref.watch(sessionProvider).role))
                PopupMenuItem(
                  value: 'materialcheck',
                  child: ListTile(
                    leading: const Icon(Icons.fact_check_outlined),
                    title: Text(tr('Material check')),
                  ),
                ),
              PopupMenuItem(
                value: 'rera',
                child: ListTile(
                  leading: const Icon(Icons.apartment_outlined),
                  title: Text(tr('RERA quarterly report')),
                ),
              ),
              PopupMenuItem(
                value: 'cash',
                child: ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: Text(tr('Cash book')),
                ),
              ),
              PopupMenuItem(
                value: 'notes',
                child: ListTile(
                  leading: const Icon(Icons.sticky_note_2_outlined),
                  title: Text(tr('Site notes')),
                ),
              ),
              PopupMenuItem(
                value: 'today',
                child: ListTile(
                  leading: const Icon(Icons.today_outlined),
                  title: Text(tr("Today's report")),
                ),
              ),
              PopupMenuItem(
                value: 'close',
                child: ListTile(
                  leading: const Icon(Icons.fact_check_outlined),
                  title: Text(tr('Weekly close')),
                ),
              ),
              PopupMenuItem(
                value: 'commercial',
                child: ListTile(
                  leading: const Icon(Icons.handshake_outlined),
                  title: Text(tr('Work orders, variations and cost')),
                ),
              ),
              PopupMenuItem(
                value: 'measure',
                child: ListTile(
                  leading: const Icon(Icons.straighten),
                  title: Text(tr('Measurement book')),
                ),
              ),
              PopupMenuItem(
                value: 'invoices',
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(tr('Supplier invoices')),
                ),
              ),
              PopupMenuItem(
                value: 'team',
                child: ListTile(
                  leading: const Icon(Icons.groups_outlined),
                  title: Text(tr('Site team')),
                ),
              ),
              if (Roles.canApprove(ref.read(sessionProvider).role))
                PopupMenuItem(
                  key: const Key('menu-share-client'),
                  value: 'client',
                  child: ListTile(
                    leading: const Icon(Icons.person_pin_circle_outlined),
                    title: Text(tr('Share with the client')),
                  ),
                ),
              PopupMenuItem(
                value: 'report',
                child: ListTile(
                  leading: const Icon(Icons.summarize_outlined),
                  title: Text(tr('Weekly or monthly report')),
                ),
              ),
              PopupMenuItem(
                value: 'excel',
                child: ListTile(
                  leading: const Icon(Icons.table_view_outlined),
                  title: Text(tr('Export to Excel')),
                ),
              ),
              PopupMenuItem(
                value: 'stage',
                child: ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: Text(tr('Project stage')),
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
          tabs: [
            Tab(text: tr('Tasks'), icon: Icon(Icons.checklist)),
            Tab(text: tr('DPR'), icon: Icon(Icons.edit_note)),
            Tab(text: tr('Issues'), icon: Icon(Icons.report_problem)),
            Tab(text: tr('Chat'), icon: Icon(Icons.forum)),
            Tab(text: tr('Procure'), icon: Icon(Icons.shopping_cart)),
            Tab(text: tr('Labour'), icon: Icon(Icons.people)),
            Tab(text: tr('Money'), icon: Icon(Icons.currency_rupee)),
            Tab(text: tr('Equipment'), icon: Icon(Icons.construction)),
            Tab(text: tr('Inspections'), icon: Icon(Icons.fact_check)),
            Tab(text: tr('Documents'), icon: Icon(Icons.folder)),
            Tab(text: tr('Workers'), icon: Icon(Icons.badge)),
            Tab(text: tr('Estimation'), icon: Icon(Icons.calculate)),
          ],
        ),
      ),
      body: Column(
        children: [
          SampleProjectBanner(project: widget.project),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                TasksTab(project: widget.project),
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
                    project: widget.project,
                    projectId: widget.project.id,
                    userId: ref.watch(sessionProvider).user?.id ?? '',
                  ),
                ),
                Builder(
                  builder: (context) {
                    final userId = ref.watch(sessionProvider).user?.id ?? '';
                    return EquipmentView(projectId: widget.project.id, userId: userId);
                  },
                ),
                Builder(
                  builder: (context) {
                    final userId = ref.watch(sessionProvider).user?.id ?? '';
                    return InspectionsView(projectId: widget.project.id, userId: userId);
                  },
                ),
                Builder(
                  builder: (context) {
                    final userId = ref.watch(sessionProvider).user?.id ?? '';
                    return DocumentsView(projectId: widget.project.id, userId: userId);
                  },
                ),
                Builder(
                  builder: (context) {
                    final userId = ref.watch(sessionProvider).user?.id ?? '';
                    return WorkersView(projectId: widget.project.id, userId: userId);
                  },
                ),
                Builder(
                  builder: (context) {
                    final userId = ref.watch(sessionProvider).user?.id ?? '';
                    return EstimationView(projectId: widget.project.id, userId: userId);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
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
      final dpr = await db.dprDao.create(
        DprEntriesCompanion.insert(
          id: dprId,
          projectId: widget.project.id,
          createdBy: user.id,
          entryDate: draft.date,
          workSummary: draft.summary,
          manpowerCount: Value(draft.manpower),
          weather: Value(draft.weather),
          source: Value(source),
        ),
      );
      for (final iss in draft.issues) {
        await db.issueDao.create(
          IssuesCompanion.insert(
            id: const Uuid().v4(),
            projectId: widget.project.id,
            dprEntryId: Value(dprId),
            description: iss,
            severity: const Value('medium'),
            status: const Value('open'),
          ),
        );
      }
      for (final path in draft.photoPaths) {
        await db.dprDao.addPhoto(DprPhotosCompanion.insert(id: const Uuid().v4(), dprEntryId: dprId, photoPath: path));
      }
      for (final e in draft.taskProgress.entries) {
        await db.taskDao.setProgress(e.key, e.value);
      }
      if (draft.taskProgress.isNotEmpty) {
        ref.invalidate(tasksProvider(widget.project.id));
        ref.invalidate(openTasksProvider(widget.project.companyId));
      }
      ref.invalidate(dprProvider(widget.project.id));
      ref.invalidate(issuesProvider(widget.project.id));
      // Today's report is in: tonight's reminder may no longer be needed.
      unawaited(ref.read(reminderSchedulerProvider).refresh());
      if (!mounted) return;
      final raised = draft.issues.length;
      showSnack(
        context,
        raised == 0 ? tr('Report saved.') : trf('Report saved, and {n} problems raised as issues.', {'n': raised}),
        action: SnackBarAction(label: tr('Share'), onPressed: () => _share(dpr)),
      );
    } catch (e, st) {
      if (mounted) showSnack(context, friendlyError(e, st), error: true);
    }
  }

  Future<void> _share(DprEntry d) async {
    showSnack(context, 'Preparing the report…');
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

  /// The report's author, an owner or a PM may take photos off it.
  bool _canChangeReport(DprEntry d) {
    final session = ref.read(sessionProvider);
    return d.createdBy == session.user?.id || Roles.canApprove(session.role);
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
            DprPhotosBlock(
              dpr: d,
              shareText: '${widget.project.name} · ${fmtDate(d.entryDate)}',
              canDelete: _canChangeReport(d),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _share(d);
              },
              icon: const Icon(Icons.ios_share),
              label: Text(tr('Share as PDF')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dpr = ref.watch(dprProvider(widget.project.id));
    final issues = ref.watch(issuesProvider(widget.project.id)).value ?? const <Issue>[];
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () async => ref.invalidate(dprProvider(widget.project.id)),
          child: dpr.when(
            data: (items) {
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.mic_none,
                  title: tr('No daily reports yet'),
                  message: tr(
                    'Speak today\'s progress in your own language. FieldOS fills in the headcount, '
                    'the weather and any problems for you, even without internet.',
                  ),
                  actionLabel: tr('Speak a report'),
                  onAction: _speak,
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 168),
                itemCount: items.length + 1,
                itemBuilder: (_, index) {
                  if (index == 0) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.summarize_outlined),
                          label: Text(tr('Weekly or monthly report')),
                          onPressed: () => openPeriodReport(context, widget.project),
                        ),
                      ),
                    );
                  }
                  final i = index - 1;
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
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${fmtDay(d.entryDate)} · ${fmtDate(d.entryDate, short: true)}',
                                    style: Theme.of(context).textTheme.titleSmall,
                                  ),
                                ),
                                if (d.source == 'voice')
                                  Tooltip(
                                    message: tr('Spoken report'),
                                    child: Icon(
                                      Icons.mic_none,
                                      size: 18,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.ios_share),
                                  tooltip: tr('Share as PDF'),
                                  onPressed: () => _share(d),
                                ),
                              ],
                            ),
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
            error: (e, st) =>
                ErrorState(error: e, stack: st, onRetry: () => ref.invalidate(dprProvider(widget.project.id))),
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
                tooltip: tr('Type a report'),
                onPressed: _type,
                child: const Icon(Icons.keyboard_alt_outlined),
              ),
              const SizedBox(height: 12),
              FloatingActionButton.extended(
                heroTag: 'dpr_voice',
                icon: const Icon(Icons.mic),
                label: Text(tr('Speak report')),
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
        StatusPill(dpr.manpowerCount > 0 ? trf('{n} people', {'n': dpr.manpowerCount}) : tr('Headcount not given')),
        if (dpr.weather != null && dpr.weather!.isNotEmpty) StatusPill(dpr.weather!),
        if (issueCount > 0) StatusPill(issueCount == 1 ? tr('1 issue') : trf('{n} issues', {'n': issueCount}), tone: PillTone.warn),
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
          title: Text(tr('New issue')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: descC,
                maxLines: 3,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: tr('What is the problem?')),
              ),
              const SizedBox(height: 16),
              Text(tr('How serious?')),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'low', label: Text(tr('Low'))),
                  ButtonSegment(value: 'medium', label: Text(tr('Medium'))),
                  ButtonSegment(value: 'high', label: Text(tr('High'))),
                ],
                selected: {severity},
                onSelectionChanged: (s) => setDialogState(() => severity = s.first),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, descC.text.trim().isNotEmpty),
              child: Text(tr('Raise issue')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(appDatabaseProvider)
        .issueDao
        .create(
          IssuesCompanion.insert(
            id: const Uuid().v4(),
            projectId: project.id,
            description: descC.text.trim(),
            severity: Value(severity),
          ),
        );
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
                  title: tr('No issues'),
                  message: tr(
                    'Problems you raise, or that FieldOS finds in your daily reports, appear here until they are fixed.',
                  ),
                  actionLabel: tr('Raise an issue'),
                  onAction: () => _addIssue(context, ref),
                );
              }
              final sorted = [...items]
                ..sort((a, b) {
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
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            StatusPill(
                              '${iss.severity[0].toUpperCase()}${iss.severity.substring(1)}',
                              tone: _severityTone[iss.severity] ?? PillTone.neutral,
                            ),
                            if (iss.dprEntryId != null) const StatusPill('From a daily report'),
                            Text(
                              resolved && iss.resolvedAt != null
                                  ? trf('Fixed {date}', {'date': fmtDate(iss.resolvedAt!, short: true)})
                                  : trf('Raised {date}', {'date': fmtDate(iss.createdAt, short: true)}),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      trailing: resolved
                          ? const Icon(Icons.check_circle, color: Brand.ok)
                          // A long "Mark fixed" (Tamil) wraps instead of taking the whole tile.
                          : ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.3),
                              child: TextButton(
                                onPressed: () async {
                                  await ref.read(appDatabaseProvider).issueDao.resolve(iss.id);
                                  ref.invalidate(issuesProvider(project.id));
                                },
                                child: Text(tr('Mark fixed'), textAlign: TextAlign.center),
                              ),
                            ),
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) =>
                ErrorState(error: e, stack: st, onRetry: () => ref.invalidate(issuesProvider(project.id))),
          ),
        ),
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton.extended(
            heroTag: 'issue_add',
            icon: const Icon(Icons.add),
            label: Text(tr('Raise issue')),
            onPressed: () => _addIssue(context, ref),
          ),
        ),
      ],
    );
  }
}

/// A saved report's photos. Whoever may change the report can delete one
/// from the full-screen viewer, and the strip reloads.
class DprPhotosBlock extends ConsumerStatefulWidget {
  const DprPhotosBlock({super.key, required this.dpr, required this.shareText, this.canDelete = false});
  final DprEntry dpr;
  final String shareText;
  final bool canDelete;

  @override
  ConsumerState<DprPhotosBlock> createState() => _DprPhotosBlockState();
}

class _DprPhotosBlockState extends ConsumerState<DprPhotosBlock> {
  late Future<List<DprPhoto>> _photos = _load();

  Future<List<DprPhoto>> _load() => ref.read(appDatabaseProvider).dprDao.photosFor(widget.dpr.id);

  Future<void> _delete(List<DprPhoto> photos, String path) async {
    final db = ref.read(appDatabaseProvider);
    for (final p in photos.where((p) => p.photoPath == path)) {
      await db.dprDao.deletePhoto(p.id);
    }
    if (!mounted) return;
    final next = _load();
    setState(() {
      _photos = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DprPhoto>>(
      future: _photos,
      builder: (ctx, snap) {
        final photos = snap.data ?? const <DprPhoto>[];
        final paths = photosOnThisPhone(photos.map((p) => p.photoPath));
        if (paths.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader('Photos'),
          PhotoStrip(
            paths: paths,
            shareText: widget.shareText,
            onDelete: widget.canDelete ? (path) => _delete(photos, path) : null,
          ),
        ]);
      },
    );
  }
}
