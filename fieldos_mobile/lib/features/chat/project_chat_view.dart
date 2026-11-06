/// Project team chat: one conversation per site, like the WhatsApp group
/// every contractor already runs, but kept next to the project's DPRs,
/// issues and approvals, and written offline-first (a message typed with
/// no signal is queued and sent on the next sync).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';
import 'package:fieldos_mobile/l10n/language.dart';

final projectMessagesProvider = StreamProvider.autoDispose.family<List<ProjectMessage>, String>(
  (ref, projectId) => ref.watch(appDatabaseProvider).messageDao.watchForProject(projectId),
);

class ProjectChatView extends ConsumerStatefulWidget {
  const ProjectChatView({super.key, required this.projectId});
  final String projectId;

  @override
  ConsumerState<ProjectChatView> createState() => _ProjectChatViewState();
}

class _ProjectChatViewState extends ConsumerState<ProjectChatView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _live = false;

  @override
  void initState() {
    super.initState();
    _goLive();
  }

  Future<void> _goLive() async {
    final service = ref.read(cloudSyncServiceProvider);
    if (!service.isSignedIn) return;
    try {
      await ref.read(cloudSyncEngineProvider).subscribeToProjectMessages(widget.projectId);
      if (mounted) setState(() => _live = true);
    } catch (_) {
      // No live channel: messages still arrive with the periodic sync.
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final user = ref.read(sessionProvider).user;
    if (text.isEmpty || user == null) return;
    _input.clear();
    await ref.read(appDatabaseProvider).messageDao.send(
          projectId: widget.projectId,
          senderId: user.id,
          senderName: user.name.length > 120 ? user.name.substring(0, 120) : user.name,
          body: text.length > 4000 ? text.substring(0, 4000) : text,
        );
    if (ref.read(cloudSyncServiceProvider).isSignedIn) {
      // Push straight away rather than waiting for the next 5-minute tick;
      // offline, it simply stays queued.
      unawaited(ref.read(cloudSyncEngineProvider).pushPending().then((_) {}, onError: (_) {}));
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(sessionProvider).user?.id;
    final messages = ref.watch(projectMessagesProvider(widget.projectId));
    final signedIn = ref.watch(cloudSyncServiceProvider).isSignedIn;

    return Column(
      children: [
        if (!signedIn)
          MaterialBanner(
            content: Text(tr('Messages stay on this phone until you sign in under Team & sync.')),
            actions: [const SizedBox.shrink()],
          )
        else if (!_live)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: messages.when(
            data: (list) {
              if (list.isEmpty) {
                return Center(child: Text(tr('No messages yet. Say what is happening on site.')));
              }
              _scrollToEnd();
              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(12),
                itemCount: list.length,
                itemBuilder: (context, i) => _Bubble(message: list[i], mine: list[i].senderId == me),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => ErrorState(error: e, stack: st),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(hintText: tr('Message the team'), border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(onPressed: _send, icon: const Icon(Icons.send), tooltip: tr('Send')),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});
  final ProjectMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = fmtDateTime(message.createdAt);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: mine ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine)
              Text(message.senderName, style: TextStyle(fontWeight: FontWeight.w600, color: scheme.primary)),
            Text(message.body),
            const SizedBox(height: 2),
            Text(time, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}
