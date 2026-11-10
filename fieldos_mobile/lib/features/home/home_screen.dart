import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/tasks/my_tasks_screen.dart';
import 'package:fieldos_mobile/features/approvals/approvals_screen.dart';
import 'package:fieldos_mobile/features/close/week_close_screen.dart';
import 'package:fieldos_mobile/features/daily/daily_reports_screen.dart';
import 'package:fieldos_mobile/features/daily/today_home_card.dart';
import 'package:fieldos_mobile/features/commercial/exceptions_screen.dart';
import 'package:fieldos_mobile/features/assistant/assistant_screen.dart';
import 'package:fieldos_mobile/features/brief/owner_brief_screen.dart';
import 'package:fieldos_mobile/features/dashboard/dashboard_screen.dart';
import 'package:fieldos_mobile/features/home/quick_actions.dart';
import 'package:fieldos_mobile/features/map/site_map_screen.dart';
import 'package:fieldos_mobile/features/project/new_project_sheet.dart';
import 'package:fieldos_mobile/features/project/project_detail_screen.dart';
import 'package:fieldos_mobile/features/project/project_status.dart';
import 'package:fieldos_mobile/features/project/task_plan.dart';
import 'package:fieldos_mobile/features/settings/settings_screen.dart';
import 'package:fieldos_mobile/features/subcontractor/subcontractor_screen.dart';
import 'package:fieldos_mobile/features/subscription/my_subscription_sheet.dart';
import 'package:fieldos_mobile/features/support/bug_report_screen.dart';
import 'package:fieldos_mobile/features/team/team_sync_screen.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_bootstrap.dart';
import 'package:fieldos_mobile/features/onboarding/sample_project.dart';
import 'package:fieldos_mobile/features/money/money_view.dart' show canSeeMoneyIn;
import 'package:fieldos_mobile/features/procurement/payables_screen.dart';
import 'package:fieldos_mobile/features/search/search_screen.dart';
import 'package:fieldos_mobile/features/tour/app_tour.dart';
import 'package:fieldos_mobile/l10n/language.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _newProject(BuildContext context, WidgetRef ref, String companyId) async {
    final project = await showNewProjectSheet(context, companyId: companyId);
    if (project == null || !context.mounted) return;
    ref.invalidate(projectsProvider(companyId));
    showSnack(context, trf('{name} is ready', {'name': project.name}));
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: project)));
  }

  Future<void> _trySample(BuildContext context, WidgetRef ref, String companyId, String userId) async {
    final project = await createSampleProject(ref.read(appDatabaseProvider), companyId: companyId, userId: userId);
    ref.invalidate(projectsProvider(companyId));
    ref.invalidate(sampleProjectIdProvider(companyId));
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: project)));
  }

  Future<void> _tour(BuildContext context, WidgetRef ref, String companyId) async {
    final exit = await openAppTour(context, ref, companyId: companyId);
    if (!context.mounted) return;
    switch (exit) {
      case TourExit.explore:
        final id = await sampleProjectId(ref.read(appDatabaseProvider), companyId);
        final project = id == null ? null : await ref.read(appDatabaseProvider).projectDao.byId(id);
        if (project != null && context.mounted) {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: project)));
        }
      case TourExit.newProject:
        await _newProject(context, ref, companyId);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final company = session.activeCompany!;
    final projectsAsync = ref.watch(projectsProvider(company.id));
    final hasProjects = projectsAsync.value?.isNotEmpty ?? false;

    return Scaffold(
      appBar: AppBar(
        title: _CompanyTitle(company: company, companies: session.companies),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: tr('Search'),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => SearchScreen(companyId: company.id))),
          ),
          Consumer(builder: (context, ref, _) {
            final count = ref.watch(pendingApprovalsProvider(company.id)).maybeWhen(data: (l) => l.length, orElse: () => 0);
            // In the bar only while something waits; otherwise it is in the
            // menu, so the bar stays at search and the dashboard.
            if (count == 0) return const SizedBox.shrink();
            return IconButton(
              tooltip: count > 0 ? trf('Approvals ({n} waiting)', {'n': count}) : tr('Approvals'),
              icon: Badge.count(count: count, isLabelVisible: count > 0, child: const Icon(Icons.approval_outlined)),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => ApprovalsScreen(companyId: company.id))),
            );
          }),
          IconButton(
            icon: const Icon(Icons.insights_outlined),
            tooltip: tr('Dashboard'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DashboardScreen(companyId: company.id, companyName: company.name),
            )),
          ),
          PopupMenuButton<String>(
            tooltip: tr('More'),
            onSelected: (v) {
              switch (v) {
                case 'team':
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamSyncScreen()));
                case 'approvals':
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ApprovalsScreen(companyId: company.id)));
                case 'daily':
                  Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => DailyReportsScreen(companyId: company.id)));
                case 'close':
                  Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => WeeklyCloseListScreen(companyId: company.id)));
                case 'exceptions':
                  Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => CommercialExceptionsScreen(companyId: company.id)));
                case 'brief':
                  openOwnerBrief(context, companyId: company.id, companyName: company.name);
                case 'payables':
                  openPayables(context, company.id);
                case 'tasks':
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => MyTasksScreen(companyId: company.id)));
                case 'map':
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => SiteMapScreen(companyId: company.id)));
                case 'subcontractors':
                  Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => SubcontractorsScreen(companyId: company.id)));
                case 'settings':
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
                case 'subscription':
                  showMySubscription(context);
                case 'tour':
                  _tour(context, ref, company.id);
                case 'bug':
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BugReportScreen()));
                case 'logout':
                  ref.read(cloudSyncBootstrapProvider).stop();
                  ref.read(sessionProvider.notifier).logout();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'team', child: ListTile(leading: Icon(Icons.groups_outlined), title: Text(tr('Team & sync')))),
              PopupMenuItem(
                  value: 'approvals',
                  child: ListTile(leading: Icon(Icons.approval_outlined), title: Text(tr('Approvals')))),
              PopupMenuItem(
                  value: 'daily',
                  child: ListTile(leading: Icon(Icons.today_outlined), title: Text(tr('Daily reports')))),
              PopupMenuItem(
                  value: 'close',
                  child: ListTile(leading: Icon(Icons.fact_check_outlined), title: Text(tr('Weekly close')))),
              PopupMenuItem(
                  value: 'exceptions',
                  child: ListTile(leading: Icon(Icons.rule_folder_outlined), title: Text(tr('Commercial exceptions')))),
              PopupMenuItem(
                  value: 'brief',
                  child: ListTile(leading: Icon(Icons.wb_twilight_outlined), title: Text(tr('Site brief')))),
              if (canSeeMoneyIn(session.role))
                PopupMenuItem(
                    value: 'payables',
                    child: ListTile(leading: Icon(Icons.account_balance_wallet_outlined), title: Text(tr('Who you owe')))),
              PopupMenuItem(
                  value: 'tasks', child: ListTile(leading: Icon(Icons.task_alt), title: Text(tr('My tasks')))),
              PopupMenuItem(value: 'map', child: ListTile(leading: Icon(Icons.map_outlined), title: Text(tr('Site map')))),
              PopupMenuItem(
                  value: 'subcontractors',
                  child: ListTile(leading: Icon(Icons.engineering_outlined), title: Text(tr('Subcontractors')))),
              if (ref.read(billingServiceProvider).setUp)
                PopupMenuItem(
                    value: 'subscription',
                    child: ListTile(leading: Icon(Icons.workspace_premium_outlined), title: Text(tr('My subscription')))),
              PopupMenuItem(
                  value: 'settings', child: ListTile(leading: Icon(Icons.settings_outlined), title: Text(tr('Settings')))),
              PopupMenuItem(
                  value: 'tour',
                  child: ListTile(leading: Icon(Icons.play_circle_outline), title: Text(tr('App tour')))),
              PopupMenuItem(
                  value: 'bug', child: ListTile(leading: Icon(Icons.bug_report_outlined), title: Text(tr('Report a bug')))),
              PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout), title: Text(tr('Log out')))),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // The assistant first: someone who has never learned the app can
          // just say what they need.
          const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 0), child: AssistantEntry()),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(projectsProvider(company.id).future),
              child: projectsAsync.when(
                data: (projects) => projects.isEmpty
                    ? Column(children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: TourInviteCard(onStart: () => _tour(context, ref, company.id)),
                        ),
                        Expanded(
                          child: EmptyState(
                            icon: Icons.domain_add_outlined,
                            title: tr('Start your first project'),
                            message: tr('A project is one site. Its daily reports, labour, materials, money and photos stay '
                                'together, on this phone and offline.'),
                            actionLabel: tr('New project'),
                            onAction: () => _newProject(context, ref, company.id),
                            secondaryLabel: tr('Try a sample site first'),
                            onSecondary: () => _trySample(context, ref, company.id, session.user?.id ?? ''),
                          ),
                        ),
                      ])
                    : _ProjectList(
                        company: company,
                        projects: projects,
                        userName: session.user?.name,
                        onTour: () => _tour(context, ref, company.id),
                      ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => ErrorState(error: e, stack: st, onRetry: () => ref.invalidate(projectsProvider(company.id))),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: hasProjects
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: Text(tr('New project')),
              onPressed: () => _newProject(context, ref, company.id),
            )
          : null,
    );
  }
}

/// The company's name, and a switcher when this person belongs to more
/// than one.
class _CompanyTitle extends ConsumerWidget {
  const _CompanyTitle({required this.company, required this.companies});

  final Company company;
  final List<Company> companies;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = Text(company.name, overflow: TextOverflow.ellipsis);
    if (companies.length < 2) return title;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final picked = await showModalBottomSheet<Company>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(tr('Switch company'), style: Theme.of(ctx).textTheme.titleLarge),
                ),
                for (final c in companies)
                  ListTile(
                    leading: const Icon(Icons.apartment_outlined),
                    title: Text(c.name),
                    trailing: c.id == company.id ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.of(ctx).pop(c),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
        if (picked != null && picked.id != company.id) {
          await ref.read(sessionProvider.notifier).selectCompany(picked);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: title),
          const Icon(Icons.arrow_drop_down),
        ]),
      ),
    );
  }
}

class _ProjectList extends StatelessWidget {
  const _ProjectList({required this.company, required this.projects, required this.userName, required this.onTour});

  final Company company;
  final List<Project> projects;
  final String? userName;
  final VoidCallback onTour;

  static const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final sorted = [...projects]..sort((a, b) {
        final byStage = projectStatusOrder(a.status).compareTo(projectStatusOrder(b.status));
        return byStage != 0 ? byStage : b.createdAt.compareTo(a.createdAt);
      });
    final active = projects.where((p) => p.status == 'active').length;
    final firstName = (userName ?? '').trim().split(RegExp(r'\s+')).first;
    final greeting = now.hour < 12
        ? tr('Good morning')
        : now.hour < 17
            ? tr('Good afternoon')
            : tr('Good evening');
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      // Room at the bottom for the New project button and the phone's
      // own navigation bar.
      padding: EdgeInsets.fromLTRB(16, 20, 16, 96 + MediaQuery.paddingOf(context).bottom),
      children: [
        TourInviteCard(onStart: onTour),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(firstName.isEmpty ? greeting : '$greeting, $firstName', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 2),
            Text(
              '${tr(_weekdays[now.weekday - 1])}, ${fmtDate(now, short: true)} · '
              '${active == 0 ? tr('no active sites') : active == 1 ? tr('1 active site') : trf('{n} active sites', {'n': active})}',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ]),
        ),
        // The day's four jobs as big picture buttons, one tap each.
        QuickActions(projects: projects),
        // The day's report: what is still to send (or, for a manager, which
        // sites' reports came in). Above the brief so it is seen first.
        TodayHomeCard(companyId: company.id),
        TodayBriefCard(companyId: company.id, companyName: company.name),
        const SectionHeader('Projects'),
        for (final p in sorted) ...[
          _ProjectCard(project: p),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ProjectCard extends ConsumerWidget {
  const _ProjectCard({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lateTasks = ref.watch(openTasksProvider(project.companyId)).maybeWhen(
          data: (tasks) => lateCountByProject(tasks, DateTime.now())[project.id] ?? 0,
          orElse: () => 0,
        );
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final client = project.clientName?.trim() ?? '';
    final onMap = project.locationLat != null && project.locationLng != null;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: project)));
          ref.invalidate(openTasksProvider(project.companyId));
          ref.invalidate(todayBriefProvider(project.companyId));
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.apartment_rounded, color: scheme.primary.withValues(alpha: 0.85)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.name,
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                    if (client.isNotEmpty)
                      Text(client,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    // Only what differs from normal: a running site needs no
                    // "Active" badge, so the line shows any other stage, late
                    // work, and whether the site is on the map.
                    if (project.status != 'active' || lateTasks > 0 || onMap) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (project.status != 'active')
                          StatusPill(projectStatusLabel(project.status), tone: projectStatusTone(project.status)),
                        if (lateTasks > 0)
                          _Note(lateTasks == 1 ? tr('1 task late') : trf('{n} tasks late', {'n': lateTasks}),
                              color: toneColor(context, PillTone.danger)),
                        if (onMap)
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.place_outlined, size: 15, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 2),
                            Text(tr('On the map'),
                                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                          ]),
                      ],
                    ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small dot and a few words: a status worth noticing, without a
/// coloured block around it.
class _Note extends StatelessWidget {
  const _Note(this.text, {required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
        ),
      ]);
}
