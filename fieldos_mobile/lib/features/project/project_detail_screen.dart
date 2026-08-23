import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/labour/labour_screen.dart';
import 'package:fieldos_mobile/features/procurement/procurement_screen.dart';
import 'package:fieldos_mobile/features/equipment/equipment_screen.dart';
import 'package:fieldos_mobile/features/inspections/inspections_screen.dart';
import 'package:fieldos_mobile/features/documents/documents_screen.dart';
import 'package:fieldos_mobile/features/workers/workers_screen.dart';
import 'package:fieldos_mobile/features/estimation/estimation_screen.dart';
import 'package:fieldos_mobile/providers.dart';

class ProjectDetailScreen extends ConsumerStatefulWidget {
  const ProjectDetailScreen({super.key, required this.project});
  final Project project;

  @override
  ConsumerState<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 10, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.project.name),
        bottom: TabBar(
          isScrollable: true,
          tabs: const [
            Tab(text: 'Tasks', icon: Icon(Icons.checklist)),
            Tab(text: 'DPR', icon: Icon(Icons.edit_note)),
            Tab(text: 'Issues', icon: Icon(Icons.report_problem)),
            Tab(text: 'Procure', icon: Icon(Icons.shopping_cart)),
            Tab(text: 'Labour', icon: Icon(Icons.people)),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider(project.id));
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(tasksProvider(project.id)),
      child: tasks.when(
        data: (items) => ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final t = items[i];
            return Card(
              child: ListTile(
                title: Text(t.title),
                subtitle: Text('Status: ${t.status}'
                    '${t.dueDate != null ? '  •  Due ${t.dueDate!.toLocal().toString().split(' ').first}' : ''}'),
                trailing: DropdownButton<String>(
                  value: t.status,
                  items: const ['todo', 'in_progress', 'done']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (s) {
                    if (s != null) {
                      ref.read(appDatabaseProvider).taskDao.updateStatus(t.id, s);
                      ref.invalidate(tasksProvider(project.id));
                    }
                  },
                ),
              ),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
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

class _DprDraftResult {
  const _DprDraftResult(this.confirmed, this.summary, this.manpower, this.weather, this.selectedIssues);
  final bool confirmed;
  final String summary;
  final int manpower;
  final String? weather;
  final List<String> selectedIssues;
}

class _DprTabState extends ConsumerState<_DprTab> {
  bool _voicing = false;
  String? _voiceError;

  /// Agentic DPR draft dialog: editable fields plus any issues the agent
  /// flagged from the narrative, presented as a checklist the user confirms.
  Future<_DprDraftResult> _showDraftDialog({
    required String title,
    required String initialSummary,
    int initialManpower = 0,
    String? initialWeather,
    List<String> detectedIssues = const [],
  }) async {
    final summaryC = TextEditingController(text: initialSummary);
    final manpowerC = TextEditingController(text: initialManpower.toString());
    final weatherC = TextEditingController(text: initialWeather ?? '');
    final selected = <String>{...detectedIssues};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: summaryC, maxLines: 4, decoration: const InputDecoration(labelText: 'Work summary')),
                const SizedBox(height: 8),
                TextField(controller: manpowerC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Manpower count')),
                const SizedBox(height: 8),
                TextField(controller: weatherC, decoration: const InputDecoration(labelText: 'Weather (optional)')),
                if (detectedIssues.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Agent-detected issues', style: TextStyle(fontWeight: FontWeight.w600)),
                  ...detectedIssues.map((iss) => CheckboxListTile(
                        value: selected.contains(iss),
                        title: Text(iss),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) => setDialogState(
                          () => v == true ? selected.add(iss) : selected.remove(iss),
                        ),
                      )),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, summaryC.text.trim().isNotEmpty),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    return _DprDraftResult(
      confirmed == true,
      summaryC.text.trim(),
      int.tryParse(manpowerC.text.trim()) ?? 0,
      weatherC.text.trim().isEmpty ? null : weatherC.text.trim(),
      selected.toList(),
    );
  }

  /// Persist a DPR and any issues the user confirmed from the agent's checklist,
  /// linking each issue back to the DPR that raised it.
  Future<void> _persistDpr({
    required String summary,
    required int manpower,
    String? weather,
    required String source,
    required List<String> issues,
  }) async {
    final user = ref.read(sessionProvider).user;
    if (user == null) return;
    final dprId = Uuid().v4();
    await ref.read(appDatabaseProvider).dprDao.create(DprEntriesCompanion.insert(
          id: dprId,
          projectId: widget.project.id,
          createdBy: user.id,
          entryDate: DateTime.now(),
          workSummary: summary,
          manpowerCount: Value(manpower),
          weather: Value(weather),
          source: Value(source),
        ));
    for (final iss in issues) {
      await ref.read(appDatabaseProvider).issueDao.create(IssuesCompanion.insert(
            id: Uuid().v4(),
            projectId: widget.project.id,
            dprEntryId: Value(dprId),
            description: iss,
            severity: const Value('medium'),
            status: const Value('open'),
          ));
    }
    ref.invalidate(dprProvider(widget.project.id));
    ref.invalidate(issuesProvider(widget.project.id));
  }

  Future<void> _recordAndDraft() async {
    setState(() => _voicing = true);
    try {
      final voice = ref.read(voiceServiceProvider);
      final bytes = await voice.record();
      final agent = ref.read(voiceDprAgentProvider);
      final result = await agent.run({'audioBytes': bytes, 'filename': 'dpr_voice.m4a'});
      if (!result.ok) {
        setState(() => _voiceError = result.message);
        return;
      }
      final data = result.data;
      final detected = (data['detected_issues'] as List?)?.cast<String>() ?? const <String>[];
      if (!mounted) return;
      final draft = await _showDraftDialog(
        title: 'Voice DPR draft',
        initialSummary: (data['work_summary'] as String?) ?? '',
        initialManpower: (data['manpower_count'] as int?) ?? 0,
        initialWeather: data['weather'] as String?,
        detectedIssues: detected,
      );
      if (draft.confirmed) {
        await _persistDpr(
          summary: draft.summary,
          manpower: draft.manpower,
          weather: draft.weather,
          source: 'voice',
          issues: draft.selectedIssues,
        );
      }
    } catch (e) {
      setState(() => _voiceError = 'Voice capture failed: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _voicing = false);
    }
  }

  Future<void> _addManually() async {
    final summaryC = TextEditingController();
    final entered = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New DPR entry'),
        content: TextField(controller: summaryC, maxLines: 4, decoration: const InputDecoration(labelText: 'Work summary')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, summaryC.text.trim().isNotEmpty),
            child: const Text('Next'),
          ),
        ],
      ),
    );
    if (entered != true) return;
    final detected = ((await ref.read(dprIntakeAgentProvider).run({'transcript': summaryC.text.trim()}))
            .data['detected_issues'] as List?)
            ?.cast<String>() ??
        const <String>[];
    final draft = await _showDraftDialog(
      title: 'New DPR entry',
      initialSummary: summaryC.text.trim(),
      detectedIssues: detected,
    );
    if (draft.confirmed) {
      await _persistDpr(
        summary: draft.summary,
        manpower: draft.manpower,
        weather: draft.weather,
        source: 'manual',
        issues: draft.selectedIssues,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpr = ref.watch(dprProvider(widget.project.id));
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () async => ref.invalidate(dprProvider(widget.project.id)),
          child: dpr.when(
            data: (items) => ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final d = items[i];
                return Card(
                  child: ListTile(
                    title: Text(d.workSummary),
                    subtitle: Text('${d.entryDate.toLocal().toString().split(' ').first}  •  '
                        '${d.manpowerCount} workers  •  ${d.weather ?? '—'}  •  ${d.source}'),
                  ),
                );
              },
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
          ),
        ),
        if (_voiceError != null)
          Positioned(
            bottom: 144,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(8)),
              child: Text(_voiceError!, style: const TextStyle(color: Colors.red)),
            ),
          ),
        Positioned(
          bottom: 16,
          right: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.extended(
                heroTag: 'dpr_manual',
                icon: const Icon(Icons.edit_note),
                label: const Text('Add entry'),
                onPressed: _addManually,
              ),
              const SizedBox(height: 12),
              FloatingActionButton.extended(
                heroTag: 'dpr_voice',
                icon: _voicing ? const CircularProgressIndicator() : const Icon(Icons.mic),
                label: Text(_voicing ? 'Listening…' : 'Voice DPR'),
                onPressed: _voicing ? null : _recordAndDraft,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IssuesTab extends ConsumerWidget {
  const _IssuesTab({required this.project});
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issues = ref.watch(issuesProvider(project.id));
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(issuesProvider(project.id)),
      child: issues.when(
        data: (items) => ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final iss = items[i];
            return Card(
              child: ListTile(
                title: Text(iss.description),
                subtitle: Text('${iss.severity} • ${iss.status}'),
                trailing: iss.status != 'resolved'
                    ? TextButton(
                        onPressed: () {
                          ref.read(appDatabaseProvider).issueDao.resolve(iss.id);
                          ref.invalidate(issuesProvider(project.id));
                        },
                        child: const Text('Resolve'),
                      )
                    : const Icon(Icons.check_circle, color: Colors.green),
              ),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }
}
