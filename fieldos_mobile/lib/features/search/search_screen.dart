import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/features/project/project_detail_screen.dart';
import 'package:fieldos_mobile/features/search/search.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

const _kindIcon = {
  SearchKind.project: Icons.domain_outlined,
  SearchKind.task: Icons.checklist,
  SearchKind.issue: Icons.report_problem_outlined,
  SearchKind.worker: Icons.badge_outlined,
  SearchKind.report: Icons.edit_note,
  SearchKind.supplier: Icons.local_shipping_outlined,
};

/// The project tab a hit opens on.
const searchHitTab = {
  SearchKind.project: 0,
  SearchKind.task: 0,
  SearchKind.report: 1,
  SearchKind.issue: 2,
  SearchKind.worker: 10,
};

String _kindLabel(SearchKind k) => switch (k) {
  SearchKind.project => tr('Project'),
  SearchKind.task => tr('Task'),
  SearchKind.issue => tr('Issue'),
  SearchKind.worker => tr('Worker'),
  SearchKind.report => tr('Daily report'),
  SearchKind.supplier => tr('Supplier'),
};

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, required this.companyId});
  final String companyId;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<SearchHit>? _hits;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _changed(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final hits = await searchCompany(ref.read(appDatabaseProvider), widget.companyId, q);
      if (mounted && _query.text == q) setState(() => _hits = q.trim().length < 2 ? null : hits);
    });
  }

  Future<void> _open(SearchHit h) async {
    final pid = h.projectId;
    if (pid == null) return;
    final project = await ref.read(appDatabaseProvider).projectDao.byId(pid);
    if (project == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectDetailScreen(project: project, initialTab: searchHitTab[h.kind] ?? 0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hits = _hits;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _query,
          autofocus: true,
          onChanged: _changed,
          textInputAction: TextInputAction.search,
          style: const TextStyle(color: Colors.white),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            hintText: tr('Search projects, tasks, workers, reports'),
            hintStyle: const TextStyle(color: Colors.white70),
            border: InputBorder.none,
            filled: false,
          ),
        ),
        actions: [
          if (_query.text.isNotEmpty)
            IconButton(
              tooltip: tr('Clear'),
              icon: const Icon(Icons.close),
              onPressed: () {
                _query.clear();
                setState(() => _hits = null);
              },
            ),
        ],
      ),
      body: hits == null
          ? EmptyState(
              icon: Icons.search,
              title: tr('Find anything'),
              message: tr('Type at least two letters: a project, a task, a worker, a problem or words from a report.'),
            )
          : hits.isEmpty
          ? EmptyState(icon: Icons.search_off, title: tr('Nothing found'))
          : ListView.separated(
              itemCount: hits.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final h = hits[i];
                return ListTile(
                  leading: CircleAvatar(child: Icon(_kindIcon[h.kind], size: 20)),
                  title: Text(h.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [
                      _kindLabel(h.kind),
                      if (h.kind != SearchKind.project) ?h.projectName,
                      ?h.detail,
                    ].where((s) => s.isNotEmpty).join(' · '),
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  onTap: h.projectId == null ? null : () => _open(h),
                );
              },
            ),
    );
  }
}
