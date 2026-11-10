/// The daily close inside the weekly close: an item whose money covers
/// days with no submitted daily report shows what is held and why, the
/// approver can let the verified part go ahead, and paying the rest anyway
/// asks for a reason that is recorded against them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/features/close/week_close.dart';
import 'package:fieldos_mobile/features/close/week_close_screen.dart' show WeekKey, weekCloseProvider;
import 'package:fieldos_mobile/features/daily/day_close.dart';
import 'package:fieldos_mobile/features/daily/day_close_data.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

final weekVerificationProvider = FutureProvider.autoDispose.family<WeekVerification, WeekKey>((ref, k) async {
  final w = await ref.watch(weekCloseProvider(k).future);
  return loadWeekVerification(ref.watch(appDatabaseProvider), w);
});

/// Held: the part of [item] on days without a submitted daily report,
/// with no override recorded since it last changed.
bool isHeld(WeekVerification? v, CloseItem item) {
  final iv = v?.of(item);
  if (iv == null || !iv.isPartial) return false;
  final o = v!.overrideFor(item);
  return o == null || o.fingerprint != item.fingerprint;
}

/// Under a weekly item: what is held for missing day reports, what was
/// released, and any override with its reason.
class VerificationNote extends StatelessWidget {
  const VerificationNote({super.key, required this.v, required this.item, required this.names});
  final WeekVerification? v;
  final CloseItem item;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final iv = v?.of(item);
    if (iv == null || !iv.isPartial) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final days = iv.unverifiedDays.map((d) => fmtDate(d, short: true)).join(', ');
    final release = v!.releaseFor(item);
    final override = v!.overrideFor(item);
    String who(String id) => names[id] ?? tr('Someone on the team');
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.pending_actions, size: 16, color: toneColor(context, PillTone.warn)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              trf('{amount} needs checking: no daily report for {days}', {'amount': rupees(iv.unverified), 'days': days}),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ]),
        if (iv.verified > 0.005)
          Text(trf('{amount} verified by daily reports', {'amount': rupees(iv.verified)}), style: theme.textTheme.bodySmall),
        if (release != null)
          Text(
            trf('{amount} released by {who} on {date}',
                {'amount': rupees(release.amount ?? 0), 'who': who(release.recordedBy), 'date': fmtDateTime(release.createdAt)}),
            style: theme.textTheme.bodySmall,
          ),
        if (override != null)
          Text(
            trf('Approved without the day reports by {who}: "{reason}"',
                {'who': who(override.recordedBy), 'reason': override.note ?? ''}),
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
      ]),
    );
  }
}

/// What the approver chose for a held item.
enum HeldChoice { releaseVerified, overrideAll }

/// Asks how to approve an item with a held part. Returns the choice and,
/// for an override, the reason.
Future<(HeldChoice, String?)?> askHeldApproval(BuildContext context, WeekVerification v, CloseItem item) async {
  final iv = v.of(item)!;
  final c = TextEditingController();
  final out = await showDialog<(HeldChoice, String?)>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(tr('Part of this is not verified')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(trf('{amount} is for days with no daily report ({days}).', {
            'amount': rupees(iv.unverified),
            'days': iv.unverifiedDays.map((d) => fmtDate(d, short: true)).join(', '),
          })),
          const SizedBox(height: 8),
          if (iv.verified > 0.005)
            Text(trf('You can let the verified {amount} go ahead now. The rest waits for the reports.',
                {'amount': rupees(iv.verified)})),
          const SizedBox(height: 8),
          TextField(
            controller: c,
            maxLength: 280,
            maxLines: 2,
            minLines: 1,
            onChanged: (_) => set(() {}),
            decoration: InputDecoration(labelText: tr('To approve all of it, say why'), counterText: ''),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel'))),
          if (iv.verified > 0.005)
            TextButton(
              onPressed: () => Navigator.pop(ctx, (HeldChoice.releaseVerified, null)),
              child: Text(trf('Release {amount}', {'amount': rupees(iv.verified)})),
            ),
          FilledButton(
            onPressed:
                c.text.trim().isEmpty ? null : () => Navigator.pop(ctx, (HeldChoice.overrideAll, c.text.trim())),
            child: Text(tr('Approve all, with this reason')),
          ),
        ],
      ),
    ),
  );
  c.dispose();
  return out;
}
