/// The site's notes page: pinned notes first, search, write, pin, share
/// on WhatsApp, and remove with an undo.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/project/site_notes.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

final siteNotesProvider = FutureProvider.autoDispose.family<List<ProjectNote>, String>(
    (ref, projectId) => ref.watch(appDatabaseProvider).noteDao.forProject(projectId));

final _userNamesProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  return {for (final u in await db.select(db.users).get()) u.id: u.name};
});

class SiteNotesScreen extends ConsumerStatefulWidget {
  const SiteNotesScreen({super.key, required this.projectId, this.siteName});
  final String projectId;
  final String? siteName;

  @override
  ConsumerState<SiteNotesScreen> createState() => _SiteNotesScreenState();
}

class _SiteNotesScreenState extends ConsumerState<SiteNotesScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _userId => ref.read(sessionProvider).user?.id ?? '';
  bool get _isManager => Roles.canApprove(ref.read(sessionProvider).role);

  void _refresh() => ref.invalidate(siteNotesProvider(widget.projectId));

  Future<void> _write({ProjectNote? existing}) async {
    final text = await _editNote(context, existing: existing);
    if (text == null || text.trim().isEmpty || !mounted) return;
    final db = ref.read(appDatabaseProvider);
    try {
      if (existing == null) {
        await db.noteDao.create(projectId: widget.projectId, body: text, by: _userId);
      } else if (text.trim() != existing.body) {
        await db.noteDao.change(existing.id, body: text);
      }
      _refresh();
    } catch (e, st) {
      if (mounted) showSnack(context, friendlyError(e, st), error: true);
    }
  }

  Future<void> _pin(ProjectNote n) async {
    await ref.read(appDatabaseProvider).noteDao.change(n.id, pinned: !n.pinned);
    _refresh();
  }

  Future<void> _remove(ProjectNote n) async {
    final db = ref.read(appDatabaseProvider);
    await db.noteDao.change(n.id, deleted: true);
    _refresh();
    if (!mounted) return;
    showSnack(context, 'Note removed.',
        action: SnackBarAction(
          label: tr('Undo'),
          onPressed: () async {
            await db.noteDao.change(n.id, deleted: false);
            _refresh();
          },
        ));
  }

  Future<void> _open(ProjectNote n, {required String? author}) async {
    final canChange = canChangeNote(n, userId: _userId, isManager: _isManager);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(n.body, style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(height: 1.45)),
            const SizedBox(height: 10),
            Text(
              [?author, fmtDateTime(n.updatedAt)].join(' · '),
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, 'share'),
                icon: const Icon(Icons.share),
                label: Text(tr('Share')),
              ),
              OutlinedButton.icon(
                key: const Key('note-pin'),
                onPressed: () => Navigator.pop(ctx, 'pin'),
                icon: Icon(n.pinned ? Icons.push_pin : Icons.push_pin_outlined),
                label: Text(n.pinned ? tr('Unpin') : tr('Pin to top')),
              ),
              if (canChange) ...[
                OutlinedButton.icon(
                  key: const Key('note-edit'),
                  onPressed: () => Navigator.pop(ctx, 'edit'),
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(tr('Edit')),
                ),
                OutlinedButton.icon(
                  key: const Key('note-remove'),
                  onPressed: () => Navigator.pop(ctx, 'remove'),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(tr('Remove')),
                ),
              ],
            ]),
            if (!canChange) ...[
              const SizedBox(height: 8),
              Text(tr('Only the person who wrote this, the owner or a project manager can change it.'),
                  style: Theme.of(ctx).textTheme.bodySmall),
            ],
          ]),
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'share':
        await SharePlus.instance.share(ShareParams(text: noteShareText(n, siteName: widget.siteName)));
      case 'pin':
        await _pin(n);
      case 'edit':
        await _write(existing: n);
      case 'remove':
        await _remove(n);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(siteNotesProvider(widget.projectId));
    final names = ref.watch(_userNamesProvider).value ?? const {};
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.siteName == null ? tr('Site notes') : '${tr('Notes')} · ${widget.siteName}')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('note-add'),
        onPressed: () => _write(),
        icon: const Icon(Icons.add),
        label: Text(tr('New note')),
      ),
      body: notes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
        data: (all) {
          if (all.isEmpty) {
            return EmptyState(
              icon: Icons.sticky_note_2_outlined,
              title: tr('No notes yet'),
              message: tr('Keep what was agreed with the client, sizes to check and numbers to call. '
                  'Everyone on this site sees them.'),
              actionLabel: tr('Write a note'),
              onAction: () => _write(),
            );
          }
          final shown = searchNotes(all, _search.text);
          return Column(children: [
            if (all.length > 4)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: TextField(
                  key: const Key('notes-search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: tr('Search notes'),
                    isDense: true,
                  ),
                ),
              ),
            Expanded(
              child: shown.isEmpty
                  ? Center(child: Text(tr('No note has these words.')))
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final n = shown[i];
                        final rest = noteRest(n.body);
                        final author = names[n.createdBy];
                        return ListTile(
                          key: Key('note-${n.id}'),
                          onTap: () => _open(n, author: author),
                          leading: n.pinned ? Icon(Icons.push_pin, color: theme.colorScheme.primary) : null,
                          title: Text(noteTitle(n.body), style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            [?rest, [?author, fmtDateTime(n.updatedAt)].join(' · ')].join('\n'),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
            ),
          ]);
        },
      ),
    );
  }
}

Future<String?> _editNote(BuildContext context, {ProjectNote? existing}) async {
  final c = TextEditingController(text: existing?.body ?? '');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(existing == null ? tr('New note') : tr('Edit note')),
      content: SizedBox(
        width: 480,
        child: TextField(
          key: const Key('note-body'),
          controller: c,
          autofocus: true,
          minLines: 4,
          maxLines: 10,
          maxLength: 4000,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: tr('First line is the title. E.g. "Client wants the kitchen window 4 ft wide"'),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
        FilledButton(key: const Key('note-save'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
      ],
    ),
  );
  return ok == true ? c.text : null;
}
