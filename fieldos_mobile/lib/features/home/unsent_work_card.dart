import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/team/team_sync_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart' show appDatabaseProvider;
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

/// Looked at once a minute while Home is open.
final unsentWorkProvider = StreamProvider.autoDispose<UnsentWork>((ref) async* {
  final dao = ref.watch(appDatabaseProvider).syncOutboxDao;
  yield await dao.unsentSummary();
  yield* Stream.periodic(const Duration(minutes: 1)).asyncMap((_) => dao.unsentSummary());
});

/// Whether this company is signed in to the cloud, so "waiting to send" means
/// something. A phone that was never linked keeps its work only on the phone.
final _companyLinkedProvider = FutureProvider.autoDispose.family<bool, String>(
    (ref, companyId) => ref.watch(cloudLinksProvider).isLinked(companyId));

/// Shown on Home when work saved on this phone has not reached the cloud for a
/// while (customer review: an engineer could not tell sync was failing, and
/// the owner then saw "report not received"). Quiet for the few minutes a save
/// normally waits for the next sync.
class UnsentWorkCard extends ConsumerWidget {
  const UnsentWorkCard({super.key, required this.companyId, this.now});

  final String companyId;

  /// For tests; the real clock otherwise.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linked = ref.watch(_companyLinkedProvider(companyId)).value ?? false;
    final unsent = ref.watch(unsentWorkProvider).value;
    if (!linked || unsent == null || !unsent.needsAttention(now ?? DateTime.now())) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('unsent-work-card'),
      color: scheme.tertiaryContainer,
      child: ListTile(
        leading: Icon(Icons.cloud_upload_outlined, color: scheme.onTertiaryContainer),
        title: Text(trf('{n} waiting to send. They will retry.', {'n': unsent.total}),
            style: TextStyle(color: scheme.onTertiaryContainer)),
        trailing: Icon(Icons.chevron_right, color: scheme.onTertiaryContainer),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamSyncScreen())),
      ),
    );
  }
}
