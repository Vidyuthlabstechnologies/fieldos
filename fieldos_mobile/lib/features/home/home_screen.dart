import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/approvals/approvals_screen.dart';
import 'package:fieldos_mobile/features/dashboard/dashboard_screen.dart';
import 'package:fieldos_mobile/features/subcontractor/subcontractor_screen.dart';
import 'package:fieldos_mobile/features/project/project_detail_screen.dart';
import 'package:fieldos_mobile/features/settings/settings_screen.dart';
import 'package:fieldos_mobile/features/map/site_map_screen.dart';
import 'package:fieldos_mobile/features/team/team_sync_screen.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_bootstrap.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final company = session.activeCompany!;
    final projectsAsync = ref.watch(projectsProvider(company.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(company.name),
        actions: [
          Consumer(
            builder: (context, ref, _) {
              final pending = ref.watch(pendingApprovalsProvider);
              final count = pending.maybeWhen(data: (l) => l.length, orElse: () => 0);
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.approval),
                    tooltip: 'Approvals',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ApprovalsScreen(companyId: company.id)),
                    ),
                  ),
                  if (count > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text('$count',
                            style: const TextStyle(fontSize: 10, color: Colors.white),
                            textAlign: TextAlign.center),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.dashboard),
            tooltip: 'Dashboard',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DashboardScreen(companyId: company.id, companyName: company.name),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.groups),
            tooltip: 'Team & sync',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TeamSyncScreen()),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'map':
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => SiteMapScreen(companyId: company.id)));
                case 'subcontractors':
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => SubcontractorsScreen(companyId: company.id)),
                  );
                case 'settings':
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
                case 'logout':
                  ref.read(cloudSyncBootstrapProvider).stop();
                  ref.read(sessionProvider.notifier).logout();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'map', child: ListTile(leading: Icon(Icons.map), title: Text('Site map'))),
              PopupMenuItem(
                  value: 'subcontractors', child: ListTile(leading: Icon(Icons.engineering), title: Text('Subcontractors'))),
              PopupMenuItem(value: 'settings', child: ListTile(leading: Icon(Icons.settings), title: Text('Settings'))),
              PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout), title: Text('Log out'))),
            ],
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Text('Projects', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (session.companies.length > 1)
                  DropdownButton<Company>(
                    value: company,
                    items: session.companies
                        .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                        .toList(),
                    onChanged: (c) {
                      if (c != null) ref.read(sessionProvider.notifier).selectCompany(c);
                    },
                  ),
              ],
            ),
          ),
          Expanded(
            child: projectsAsync.when(
              data: (projects) => projects.isEmpty
                  ? const Center(child: Text('No projects yet. Tap + to add one.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: projects.length,
                      itemBuilder: (context, i) {
                        final p = projects[i];
                        return Card(
                          child: ListTile(
                            title: Text(p.name),
                            subtitle: Text(p.clientName ?? p.status),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: p)),
                            ),
                          ),
                        );
                      },
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New project'),
        onPressed: () => _createProject(context, ref, company.id),
      ),
    );
  }

  Future<void> _createProject(BuildContext context, WidgetRef ref, String companyId) async {
    final nameC = TextEditingController();
    final clientC = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New project'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Project name')),
            TextField(controller: clientC, decoration: const InputDecoration(labelText: 'Client (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (nameC.text.trim().isNotEmpty) Navigator.pop(ctx, true);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (result != true) return;
    await ref.read(appDatabaseProvider).projectDao.create(ProjectsCompanion.insert(
          id: Uuid().v4(),
          companyId: companyId,
          name: nameC.text.trim(),
          clientName: Value(clientC.text.trim()),
          status: Value('planning'),
        ));
    ref.invalidate(projectsProvider(companyId));
  }
}
