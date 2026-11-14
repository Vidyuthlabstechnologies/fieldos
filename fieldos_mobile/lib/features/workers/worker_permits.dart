/// Workers' permits, IDs and site cards that expire, per market: what each
/// is called, when a reminder is due, and the status shown on a worker.
///
/// Malaysia: passport, PLKS work permit (renewal opens 3 months before
/// expiry and must be filed before it), FOMEMA medical and the CIDB Green
/// Card every worker on site needs. UAE: Emirates ID and work permit. UK:
/// CSCS card and right to work. India keeps none here.
library;

import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/data/app_database.dart';

class PermitKind {
  const PermitKind(this.key, this.label, {this.blocksSiteWork = false});
  final String key;

  /// English label, shown through tr().
  final String label;

  /// Working on site with this expired is not allowed (a warning at
  /// punch-in, never a block on pay).
  final bool blocksSiteWork;
}

const _malaysia = [
  PermitKind('plks', 'PLKS work permit', blocksSiteWork: true),
  PermitKind('green_card', 'CIDB Green Card', blocksSiteWork: true),
  PermitKind('passport', 'Passport'),
  PermitKind('fomema', 'FOMEMA medical'),
];

const _uae = [
  PermitKind('work_permit', 'Work permit and residence visa', blocksSiteWork: true),
  PermitKind('emirates_id', 'Emirates ID'),
  PermitKind('passport', 'Passport'),
];

const _uk = [
  PermitKind('cscs', 'CSCS card', blocksSiteWork: true),
  PermitKind('work_permit', 'Right to work (visa)', blocksSiteWork: true),
];

/// The kinds this build's market tracks; empty in India and the US.
List<PermitKind> get permitKinds => switch (currentMarket) {
      Market.malaysia => _malaysia,
      Market.uae => _uae,
      Market.uk => _uk,
      _ => const [],
    };

PermitKind? permitKind(String key) {
  for (final k in permitKinds) {
    if (k.key == key) return k;
  }
  return null;
}

enum PermitStatus { ok, dueSoon, expired }

/// Days before expiry that count as "due soon": the PLKS renewal window.
const permitDueSoonDays = 90;

/// Reminders go out this many days before expiry.
const permitReminderDays = [90, 60, 30, 7];

int daysLeft(WorkerPermit p, DateTime today) {
  final t = DateTime(today.year, today.month, today.day);
  final e = DateTime(p.expiresOn.year, p.expiresOn.month, p.expiresOn.day);
  return e.difference(t).inDays;
}

PermitStatus permitStatus(WorkerPermit p, DateTime today) {
  final d = daysLeft(p, today);
  if (d < 0) return PermitStatus.expired;
  if (d <= permitDueSoonDays) return PermitStatus.dueSoon;
  return PermitStatus.ok;
}

/// The worst status of [workerId]'s permits, or null when none are kept.
PermitStatus? workerPermitStatus(Iterable<WorkerPermit> permits, String workerId, DateTime today) {
  PermitStatus? worst;
  for (final p in permits.where((p) => p.workerId == workerId)) {
    final s = permitStatus(p, today);
    if (worst == null || s.index > worst.index) worst = s;
  }
  return worst;
}

/// The permits that make site work a problem today: an expired PLKS,
/// Green Card, CSCS card or work permit.
List<WorkerPermit> blockingExpired(Iterable<WorkerPermit> permits, String workerId, DateTime today) => [
      for (final p in permits)
        if (p.workerId == workerId &&
            (permitKind(p.kind)?.blocksSiteWork ?? false) &&
            permitStatus(p, today) == PermitStatus.expired)
          p,
    ];

/// [number] as shown to people who are not the owner or a project
/// manager: the last 4 characters only.
String maskedNumber(String? number) {
  final n = (number ?? '').trim();
  if (n.isEmpty) return '';
  if (n.length <= 4) return n;
  return '••••${n.substring(n.length - 4)}';
}
