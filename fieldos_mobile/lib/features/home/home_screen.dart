import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/approvals/approvals_screen.dart';
import 'package:fieldos_mobile/features/dashboard/dashboard_screen.dart';
import 'package:fieldos_mobile/features/map/site_map_screen.dart';
import 'package:fieldos_mobile/features/project/new_project_sheet.dart';
import 'package:fieldos_mobile/features/project/project_detail_screen.dart';
import 'package:fieldos_mobile/features/project/project_status.dart';
import 'package:fieldos_mobile/features/settings/settings_screen.dart';
import 'package:fieldos_mobile/features/subcontractor/subcontractor_screen.dart';
import 'package:fieldos_mobile/features/subscription/my_subscription_sheet.dart';
import 'package:fieldos_mobile/features/support/bug_report_screen.dart';
import 'package:fieldos_mobile/features/team/team_sync_screen.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_bootstrap.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _newProject(BuildContext context, WidgetRef ref, String companyId) async {
    final project = await showNewProjectSheet(context, companyId: companyId);
    if (project == null || !context.mounted) return;
    ref.invalidate(projectsProvider(companyId));
    showSnack(context, '${project.name} is ready');
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: project)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final company = session.activeCompany!;
    final projectsAsync = ref.watch(projectsProvider(company.id));
    final hasProjects = projectsAsync.valueOrNull?.isNotEmpty ?? false;

    return Scaffold(
      appBar: AppBar(
        title: _CompanyTitle(company: company, companies: session.companies),
        actions: [
          Consumer(builder: (context, ref, _) {
            final count = ref.watch(pendingApprovalsProvider(company.id)).maybeWhen(data: (l) => l.length, orElse: () => 0);
            return IconButton(
              tooltip: count > 0 ? 'Approvals ($count waiting)' : 'Approvals',
              icon: Badge.count(count: count, isLabelVisible: count > 0, child: const Icon(Icons.approval_outlined)),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => ApprovalsScreen(companyId: company.id))),
            );
          }),
          IconButton(
            icon: const Icon(Icons.insights_outlined),
            tooltip: 'Dashboard',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DashboardScreen(companyId: company.id, companyName: company.name),
            )),
          ),
          IconButton(
            icon: const Icon(Icons.groups_outlined),
            tooltip: 'Team & sync',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamSyncScreen())),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) {
              switch (v) {
                case 'map':
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => SiteMapScreen(companyId: company.id)));
                case 'subcontractors':
                  Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => SubcontractorsScreen(companyId: company.id)));
                case 'settings':
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
                case 'subscription':
                  showMySubscription(context);
                case 'bug':
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BugReportScreen()));
                case 'logout':
                  ref.read(cloudSyncBootstrapProvider).stop();
                  ref.read(sessionProvider.notifier).logout();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'map', child: ListTile(leading: Icon(Icons.map_outlined), title: Text('Site map'))),
              const PopupMenuItem(
                  value: 'subcontractors',
                  child: ListTile(leading: Icon(Icons.engineering_outlined), title: Text('Subcontractors'))),
              if (ref.read(billingServiceProvider).setUp)
                const PopupMenuItem(
                    value: 'subscription',
                    child: ListTile(leading: Icon(Icons.workspace_premium_outlined), title: Text('My subscription'))),
              const PopupMenuItem(
                  value: 'settings', child: ListTile(leading: Icon(Icons.settings_outlined), title: Text('Settings'))),
              const PopupMenuItem(
                  value: 'bug', child: ListTile(leading: Icon(Icons.bug_report_outlined), title: Text('Report a bug'))),
              const PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout), title: Text('Log out'))),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(projectsProvider(company.id).future),
        child: projectsAsync.when(
          data: (projects) => projects.isEmpty
              ? EmptyState(
                  icon: Icons.domain_add_outlined,
                  title: 'Start your first project',
                  message: 'A project is one site. Its daily reports, labour, materials, money and photos stay '
                      'together, on this phone and offline.',
                  actionLabel: 'New project',
                  onAction: () => _newProject(context, ref, company.id),
                )
              : _ProjectList(projects: projects, userName: session.user?.name),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => ErrorState(error: e, stack: st, onRetry: () => ref.invalidate(projectsProvider(company.id))),
        ),
      ),
      floatingActionButton: hasProjects
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('New project'),
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
                  child: Text('Switch company', style: Theme.of(ctx).textTheme.titleLarge),
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
  const _ProjectList({required this.projects, required this.userName});

  final List<Project> projects;
  final String? userName;

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
        ? 'Good morning'
        : now.hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 96),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(firstName.isEmpty ? greeting : '$greeting, $firstName', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 2),
            Text(
              '${_weekdays[now.weekday - 1]}, ${fmtDate(now, short: true)} · '
              '${active == 0 ? 'no active sites' : active == 1 ? '1 active site' : '$active active sites'}',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ]),
        ),
        const SectionHeader('Projects'),
        for (final p in sorted) ...[
          _ProjectCard(project: p),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final client = project.clientName?.trim() ?? '';
    final onMap = project.locationLat != null && project.locationLng != null;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: project))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.apartment_rounded, color: scheme.onSecondaryContainer),
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
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusPill(projectStatusLabel(project.status), tone: projectStatusTone(project.status)),
                        if (onMap)
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.place_outlined, size: 15, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 2),
                            Text('On the map',
                                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                          ]),
                      ],
                    ),
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
