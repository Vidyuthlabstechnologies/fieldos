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
import 'package:fieldos_mobile/services/message_report_service.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';
import 'package:fieldos_mobile/l10n/language.dart';

final projectMessagesProvider = StreamProvider.autoDispose.family<List<ProjectMessage>, String>(
  (ref, projectId) => ref.watch(appDatabaseProvider).messageDao.watchForProject(projectId),
);

/// Messages this phone has reported: shown folded away for the reporter.
final reportedMessagesProvider = FutureProvider.autoDispose<Set<String>>(
  (ref) => ref.watch(messageReportServiceProvider).reportedIds(),
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
    await ref
        .read(appDatabaseProvider)
        .messageDao
        .send(
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

  Future<void> _messageMenu(ProjectMessage m) async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.flag_outlined),
          title: Text(tr('Report this message')),
          subtitle: Text(tr('The FieldOS team reviews it. The sender is not told who reported it.')),
          onTap: () => Navigator.pop(ctx, 'report'),
        ),
      ),
    );
    if (pick != 'report' || !mounted) return;
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) => ReportMessageDialog(messageId: m.id),
    );
    if (sent == true && mounted) {
      ref.invalidate(reportedMessagesProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('Thanks. We review reports within 24 hours.'))));
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
    final reported = ref.watch(reportedMessagesProvider).value ?? const <String>{};

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
                itemBuilder: (context, i) {
                  final m = list[i];
                  final mine = m.senderId == me;
                  return _Bubble(
                    message: m,
                    mine: mine,
                    reported: reported.contains(m.id),
                    onLongPress: mine || !signedIn ? null : () => _messageMenu(m),
                  );
                },
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
  const _Bubble({required this.message, required this.mine, this.reported = false, this.onLongPress});
  final ProjectMessage message;
  final bool mine;
  final bool reported;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = fmtDateTime(message.createdAt);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
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
                Text(
                  message.senderName,
                  style: TextStyle(fontWeight: FontWeight.w600, color: scheme.primary),
                ),
              if (reported)
                Text(tr('You reported this message.'), style: const TextStyle(fontStyle: FontStyle.italic))
              else
                Text(message.body),
              const SizedBox(height: 2),
              Text(time, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks why, then sends the report.
class ReportMessageDialog extends ConsumerStatefulWidget {
  const ReportMessageDialog({super.key, required this.messageId});
  final String messageId;

  @override
  ConsumerState<ReportMessageDialog> createState() => _ReportMessageDialogState();
}

/// Why a message is reported, as English keys shown through tr().
const reportReasonLabels = {
  ReportReason.abuse: 'Abuse or threats',
  ReportReason.spam: 'Spam or fraud',
  ReportReason.inappropriate: 'Sexual or offensive content',
  ReportReason.other: 'Something else',
};

class _ReportMessageDialogState extends ConsumerState<ReportMessageDialog> {
  static const _labels = reportReasonLabels;
  ReportReason? _reason;
  final _details = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(messageReportServiceProvider)
          .report(messageId: widget.messageId, reason: reason, details: _details.text);
      if (mounted) Navigator.pop(context, true);
    } on MessageReportException catch (e) {
      if (mounted) setState(() => _error = tr(e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Report this message')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('What is wrong with it?')),
            RadioGroup<ReportReason>(
              groupValue: _reason,
              onChanged: (v) => setState(() => _reason = v),
              child: Column(
                children: [
                  for (final e in _labels.entries)
                    RadioListTile<ReportReason>(
                      value: e.key,
                      title: Text(tr(e.value)),
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            TextField(
              controller: _details,
              maxLength: 1000,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(labelText: tr('More details (optional)')),
            ),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
        FilledButton(onPressed: _busy || _reason == null ? null : _send, child: Text(tr('Report'))),
      ],
    );
  }
}
