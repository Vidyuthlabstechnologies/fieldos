import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

/// Shown on Home when the server says this build is too old to sync
/// (issue #146). Work on the phone carries on; only cloud sync waits.
class AppUpdateBanner extends ConsumerWidget {
  const AppUpdateBanner({super.key});

  static final playStoreUrl = Uri.parse('https://play.google.com/store/apps/details?id=com.mldynamic.fieldos');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final needed = ref.watch(appUpdateRequiredProvider).value;
    if (needed == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final note = needed.note?.trim();
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.system_update, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(tr('A newer FieldOS is needed'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.onErrorContainer)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(needed.message, style: TextStyle(color: scheme.onErrorContainer)),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(note, style: TextStyle(color: scheme.onErrorContainer)),
          ],
          const SizedBox(height: 12),
          if (Platform.isAndroid)
            FilledButton.icon(
              onPressed: () => launchUrl(playStoreUrl, mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new),
              label: Text(tr('Update now')),
            )
          else
            Text(tr('Open the App Store and update FieldOS.'), style: TextStyle(color: scheme.onErrorContainer)),
        ]),
      ),
    );
  }
}
