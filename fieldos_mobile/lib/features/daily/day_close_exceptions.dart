/// A daily report still missing the next morning goes into the project
/// manager's exceptions inbox (FOS-204), next to the commercial ones, with
/// the same owner, due date and decision trail. It clears itself when the
/// report is sent. Repeat misses are escalated there, instead of more
/// reminders going to everyone.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/commercial/commercial_data.dart';
import 'package:fieldos_mobile/features/commercial/commercial_rules.dart';
import 'package:fieldos_mobile/features/daily/day_close.dart';
import 'package:fieldos_mobile/features/daily/day_close_data.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet.dart' show markDay;
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

/// How far back an unsent day stays in the inbox.
const missingDayLookback = 7;

List<CommercialException> dayCloseExceptions(SiteRecords r, List<ExceptionAction> actions, {required DateTime now}) {
  if (r.project.status != 'active') return const [];
  final start = r.trackingStart;
  if (start == null) return const [];
  final misses = r.missed(now);
  final repeat = misses.length >= repeatMissCount;
  final out = <CommercialException>[];
  final today = dayOf(now);
  for (var i = missingDayLookback; i >= 1; i--) {
    final d = today.subtract(Duration(days: i));
    if (d.isBefore(start)) continue;
    final day = r.day(d);
    if (day.status(now) != DayStatus.missed) continue;
    out.add(CommercialException(
      key: 'missing_day_report:${markDay(d)}',
      kind: ExceptionKind.missingDayReport,
      projectId: r.project.id,
      title: trf('{day}, {date}: no report received', {'day': fmtDay(d), 'date': fmtDate(d, short: true)}),
      detail: [
        repeat
            ? trf('Repeat: {n} misses in 2 weeks', {'n': misses.length})
            : tr('Follow up, or assign a backup supervisor'),
        if (day.missReasons.isNotEmpty)
          missReasonLabel(MissReasonKey.parse(day.missReasons.last.reason) ?? MissReason.other),
      ].join(' · '),
      source: ExceptionSource.dayClose,
      sourceId: markDay(d),
      defaultOwnerRole: 'manager',
      // Due the morning it became an exception; a repeat is due today.
      defaultDue: repeat ? today : d.add(const Duration(days: 1)),
      fingerprint: 'missing|${repeat ? 'repeat' : 'once'}',
    ));
  }
  return withActions(out, actions);
}

/// Days people were counted for wages but nobody was photographed on site.
///
/// Only for a site that has used roll-call photos at all (one that never did
/// would show this every day, which is noise, not a finding): from then on, a
/// day with workers marked present or punched in and no punch carrying a
/// photo stands out, as the place a paid day can be made up (customer review:
/// "workers paid with no photo"). Nothing can add the photo afterwards, so it
/// is cleared by a recorded decision.
List<CommercialException> rollCallPhotoExceptions(SiteRecords r, List<ExceptionAction> actions, {required DateTime now}) {
  if (r.project.status != 'active') return const [];
  if (!r.punches.any((p) => p.photoId != null)) return const [];
  final today = dayOf(now);
  final out = <CommercialException>[];
  for (var i = missingDayLookback; i >= 1; i--) {
    final d = today.subtract(Duration(days: i));
    final key = markDay(d);
    final dayPunches = r.punches.where((p) => markDay(p.punchIn.toLocal()) == key).toList();
    if (dayPunches.any((p) => p.photoId != null)) continue;
    final counted = <String>{
      for (final m in r.marks)
        if (m.day == key && (m.units ?? 0) > 0) m.workerId,
      for (final p in dayPunches) p.workerId ?? p.workerName,
    };
    if (counted.isEmpty) continue;
    out.add(CommercialException(
      key: 'no_roll_call_photo:$key',
      kind: ExceptionKind.noRollCallPhoto,
      projectId: r.project.id,
      title: trf('{day}, {date}: {n} counted for wages, no roll-call photo',
          {'day': fmtDay(d), 'date': fmtDate(d, short: true), 'n': counted.length}),
      detail: tr('Check who was on site before this is paid.'),
      source: ExceptionSource.dayClose,
      sourceId: key,
      defaultOwnerRole: 'manager',
      defaultDue: d.add(const Duration(days: 2)),
      fingerprint: 'photo|${counted.length}',
    ));
  }
  return withActions(out, actions);
}

/// The exceptions inbox with the daily close's items merged in.
final inboxExceptionsProvider = FutureProvider.autoDispose.family<List<SiteExceptions>, String>((ref, companyId) async {
  final sites = await ref.watch(companyExceptionsProvider(companyId).future);
  final db = ref.watch(appDatabaseProvider);
  final now = DateTime.now();
  return [
    for (final s in sites)
      SiteExceptions(s.project, s.data, [
        ...s.items,
        ...await _closeItems(db, s, now),
      ]),
  ];
});

Future<List<CommercialException>> _closeItems(AppDatabase db, SiteExceptions s, DateTime now) async {
  final records = await SiteRecords.load(db, s.project);
  return [
    ...dayCloseExceptions(records, s.data.actions, now: now),
    ...rollCallPhotoExceptions(records, s.data.actions, now: now),
  ];
}
