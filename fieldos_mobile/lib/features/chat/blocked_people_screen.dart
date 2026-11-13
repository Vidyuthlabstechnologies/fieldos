import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/features/chat/project_chat_view.dart';
import 'package:fieldos_mobile/l10n/language.dart';

/// Settings › Blocked people: unblock someone blocked in project chat.
class BlockedPeopleScreen extends ConsumerWidget {
  const BlockedPeopleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(blockedSendersProvider).value ?? const <String, String>{};
    return Scaffold(
      appBar: AppBar(title: Text(tr('Blocked people'))),
      body: blocked.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(tr('Nobody is blocked. To block someone, press and hold one of their chat messages.'),
                    textAlign: TextAlign.center),
              ),
            )
          : ListView(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(tr('Their chat messages are hidden on this phone. They stay in the company, and their site records are not hidden.')),
              ),
              for (final e in blocked.entries)
                ListTile(
                  leading: const Icon(Icons.block),
                  title: Text(e.value),
                  trailing: TextButton(
                    onPressed: () async {
                      await ref.read(chatBlockServiceProvider).unblock(e.key);
                      ref.invalidate(blockedSendersProvider);
                    },
                    child: Text(tr('Unblock')),
                  ),
                ),
            ]),
    );
  }
}
