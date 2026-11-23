/// A once-a-year reminder of the rules, on Home.
///
/// The Information Technology (Intermediary Guidelines and Digital Media
/// Ethics Code) Rules, 2021, rule 3(1)(c), ask an intermediary to tell its
/// users at least once a year, in English or an Eighth Schedule language,
/// that if they break its rules it may end their access or remove what
/// they posted. Team chat and shared photos make FieldOS an intermediary
/// for that content.
///
/// The first time Home opens for a person the clock just starts (they
/// accepted the terms moments ago, at sign-up); the card first shows a
/// year later, and again every year after "Got it".
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/legal/legal_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

String rulesReminderKey(String userId) => 'rules_reminder_at:$userId';

const rulesReminderEvery = Duration(days: 365);

/// Whether [userId] is due the yearly reminder at [now]. Starts the clock
/// (and answers false) the first time it is asked.
Future<bool> rulesReminderDue(AppDatabase db, String userId, DateTime now) async {
  if (userId.isEmpty) return false;
  final raw = await db.settingsDao.get(rulesReminderKey(userId));
  final last = raw == null ? null : DateTime.tryParse(raw);
  if (last == null) {
    await db.settingsDao.set(rulesReminderKey(userId), now.toUtc().toIso8601String());
    return false;
  }
  return now.toUtc().difference(last.toUtc()) >= rulesReminderEvery;
}

Future<void> markRulesReminderSeen(AppDatabase db, String userId, DateTime now) =>
    db.settingsDao.set(rulesReminderKey(userId), now.toUtc().toIso8601String());

class RulesReminderCard extends ConsumerStatefulWidget {
  const RulesReminderCard({super.key, this.now});

  /// For tests.
  final DateTime? now;

  @override
  ConsumerState<RulesReminderCard> createState() => _RulesReminderCardState();
}

class _RulesReminderCardState extends ConsumerState<RulesReminderCard> {
  bool _due = false;

  String get _userId => ref.read(sessionProvider).user?.id ?? '';
  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    rulesReminderDue(ref.read(appDatabaseProvider), _userId, _now).then((v) {
      if (mounted && v) setState(() => _due = true);
    });
  }

  Future<void> _done() async {
    await markRulesReminderSeen(ref.read(appDatabaseProvider), _userId, _now);
    if (mounted) setState(() => _due = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_due) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      key: const Key('rules-reminder'),
      margin: const EdgeInsets.only(top: 12),
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.gavel_rounded, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(child: Text(tr('Our yearly reminder of the rules'), style: theme.textTheme.titleSmall)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              tr(
                'Please read the terms of use and privacy policy again. Do not share anything that abuses or '
                'threatens people, breaks the law or gives out someone\'s private details. If you do, we may '
                'remove it and suspend or close the account.',
              ),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            Wrap(
              spacing: 4,
              children: [
                TextButton(onPressed: () => openTerms(context), child: Text(tr('Terms of use'))),
                TextButton(onPressed: () => openPrivacyPolicy(context), child: Text(tr('Privacy policy'))),
                TextButton(key: const Key('rules-reminder-done'), onPressed: _done, child: Text(tr('Got it'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
