import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/project/project_status.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/company_plan.dart';
import 'package:fieldos_mobile/l10n/language.dart';

/// Asks for a new project's name, client and stage, saves it, and returns
/// it (null if the person closed the sheet).
Future<Project?> showNewProjectSheet(BuildContext context, {required String companyId}) =>
    showModalBottomSheet<Project>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => NewProjectSheet(companyId: companyId),
    );

class NewProjectSheet extends ConsumerStatefulWidget {
  const NewProjectSheet({super.key, required this.companyId});

  final String companyId;

  @override
  ConsumerState<NewProjectSheet> createState() => _NewProjectSheetState();
}

class _NewProjectSheetState extends ConsumerState<NewProjectSheet> {
  final _name = TextEditingController();
  final _client = TextEditingController();
  final _clientFocus = FocusNode();
  String _status = 'active';
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _client.dispose();
    _clientFocus.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final client = _client.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) {
      setState(() => _error = 'Give the project a name, such as the site or building.');
      return;
    }
    if (name.length > 200 || client.length > 200) {
      setState(() => _error = 'Keep the names under 200 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final db = ref.read(appDatabaseProvider);
      if (countsAsActiveSite(_status)) {
        final blocked = await newActiveSiteBlocked(db, widget.companyId);
        if (blocked != null) {
          if (mounted) setState(() => _error = blocked);
          return;
        }
      }
      final project = await db.projectDao.create(ProjectsCompanion.insert(
            id: const Uuid().v4(),
            companyId: widget.companyId,
            name: name,
            // An empty client is no client, not a blank line on every card.
            clientName: Value(client.isEmpty ? null : client),
            status: Value(_status),
          ));
      if (mounted) Navigator.of(context).pop(project);
    } catch (e, st) {
      if (mounted) setState(() => _error = friendlyError(e, st));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('New project'), style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              "One project for each site. Its daily reports, labour, materials, money and photos stay together.",
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _clientFocus.requestFocus(),
              decoration: InputDecoration(
                labelText: tr('Project name'),
                hintText: tr('For example Green Valley Villas, Block A'),
                prefixIcon: Icon(Icons.apartment_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _client,
              focusNode: _clientFocus,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _busy ? null : _create(),
              decoration: InputDecoration(
                labelText: tr('Client (optional)'),
                prefixIcon: Icon(Icons.handshake_outlined),
              ),
            ),
            const SizedBox(height: 16),
            Text(tr('Stage'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                for (final s in const ['planning', 'active'])
                  ButtonSegment(value: s, label: Text(projectStatusLabel(s))),
              ],
              selected: {_status},
              onSelectionChanged: (v) => setState(() => _status = v.first),
            ),
            const SizedBox(height: 6),
            Text(projectStatusHint(_status),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            if (_error != null) ...[
              const SizedBox(height: 12),
              FormMessage(_error!),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _create,
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(tr('Create project')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lets the person move a project to another stage. Returns the new stage,
/// or null if nothing changed.
Future<String?> showProjectStatusSheet(BuildContext context, {required String current}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(tr('Project stage'), style: theme.textTheme.titleLarge),
            ),
            RadioGroup<String>(
              groupValue: current,
              onChanged: (v) => Navigator.of(ctx).pop(v == current ? null : v),
              child: Column(
                children: [
                  for (final s in projectStatuses)
                    RadioListTile<String>(
                      value: s,
                      title: Text(projectStatusLabel(s)),
                      subtitle: Text(projectStatusHint(s)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
