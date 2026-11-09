/// The four jobs a site does every day, as big picture buttons on Home:
/// attendance, money spent, the daily report and material that came. Each
/// is one tap to the right place, with a picture and a word or two, so
/// someone who reads slowly never has to hunt through tabs.
library;

import 'package:flutter/material.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/project/project_detail_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';

class QuickAction {
  const QuickAction(this.label, this.icon, this.tab);
  final String label;
  final IconData icon;

  /// The project tab it opens.
  final int tab;
}

/// Tab order in [ProjectDetailScreen]: Tasks, DPR, Issues, Chat, Procure,
/// Labour, Money...
List<QuickAction> quickActions() => [
      QuickAction(tr('Attendance'), Icons.how_to_reg_rounded, 5),
      QuickAction(tr('Expense'), Icons.currency_rupee_rounded, 6),
      QuickAction(tr('Daily report'), Icons.mic_rounded, 1),
      QuickAction(tr('Material'), Icons.local_shipping_rounded, 4),
    ];

/// Which sites a quick action can go to: the running ones, or every site
/// when none is marked running.
List<Project> quickActionSites(List<Project> projects) {
  final running = projects.where((p) => p.status == 'active').toList();
  return running.isEmpty ? projects : running;
}

class QuickActions extends StatelessWidget {
  const QuickActions({super.key, required this.projects});
  final List<Project> projects;

  Future<void> _open(BuildContext context, QuickAction a) async {
    final sites = quickActionSites(projects);
    if (sites.isEmpty) return;
    final site = sites.length == 1 ? sites.first : await _pickSite(context, sites);
    if (site == null || !context.mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: site, initialTab: a.tab)));
  }

  Future<Project?> _pickSite(BuildContext context, List<Project> sites) => showModalBottomSheet<Project>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(tr('Which site?'), style: Theme.of(ctx).textTheme.titleLarge),
                ),
                for (final p in sites)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      minVerticalPadding: 14,
                      leading: const Icon(Icons.apartment_rounded),
                      title: Text(p.name, style: Theme.of(ctx).textTheme.titleMedium),
                      subtitle: (p.clientName ?? '').trim().isEmpty ? null : Text(p.clientName!.trim()),
                      onTap: () => Navigator.of(ctx).pop(p),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (quickActionSites(projects).isEmpty) return const SizedBox.shrink();
    final actions = quickActions();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      // Same height for every tile, however the words wrap.
      child: IntrinsicHeight(
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _Tile(action: actions[i], onTap: () => _open(context, actions[i]))),
          ],
        ],
      ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.action, required this.onTap});
  final QuickAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: action.label,
      excludeSemantics: true,
      child: Material(
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 12),
            child: Column(children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: scheme.secondaryContainer, shape: BoxShape.circle),
                child: Icon(action.icon, size: 28, color: scheme.onSecondaryContainer),
              ),
              const SizedBox(height: 8),
              Text(
                action.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(height: 1.2),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
