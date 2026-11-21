/// The free trial, said plainly on Home while it runs: how many days are
/// left and what happens when it ends. A charge nobody saw coming is the
/// most common one-star review a subscription app gets, so the date is
/// never something people have to go looking for.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/features/subscription/my_subscription_sheet.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/subscription_access.dart';

/// The store's answer, or null without billing (development builds) or
/// when the store can't be reached.
final storeSubscriptionProvider = FutureProvider.autoDispose<SubscriptionState?>((ref) async {
  final billing = ref.watch(billingServiceProvider);
  if (!billing.setUp) return null;
  try {
    return await billing.current();
  } catch (_) {
    return null;
  }
});

/// Whole days left in a trial ending at [end], counting a part day as a
/// day ("1 day left" up to the last hour, then "ends today").
int trialDaysLeft(DateTime end, DateTime now) {
  final left = end.difference(now);
  if (left.inHours < 1) return 0;
  return (left.inMinutes / (24 * 60)).ceil();
}

class TrialNoticeCard extends ConsumerWidget {
  const TrialNoticeCard({super.key, this.now});

  /// For tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(storeSubscriptionProvider).value;
    final end = s?.expiresAt;
    if (s == null || !s.active || !s.inTrial || s.complimentary || end == null) return const SizedBox.shrink();
    final days = trialDaysLeft(end, now ?? DateTime.now());
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final store = ref.read(billingServiceProvider).cancelPath;
    final title = days <= 0
        ? tr('Your free trial ends today')
        : days == 1
            ? tr('Free trial: 1 day left')
            : trf('Free trial: {n} days left', {'n': days});
    final body = s.willRenew
        ? trf('Your plan starts on its own after that. To stop it, cancel in {path} before then.', {'path': store})
        : tr('Your trial will not renew. Choose a plan to keep your sites going.');
    return Card(
      key: const Key('trial-notice'),
      margin: const EdgeInsets.only(top: 12),
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await showMySubscription(context);
          ref.invalidate(storeSubscriptionProvider);
        },
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 8, 12),
          child: Row(children: [
            Icon(Icons.hourglass_bottom_rounded, color: toneColor(context, days <= 1 ? PillTone.warn : PillTone.neutral)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(body, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
            ),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}
