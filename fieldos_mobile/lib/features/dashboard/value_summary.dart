/// "This month with FieldOS": what the team recorded this month and
/// roughly how much office time that took off the owner's hands. Shown so
/// the owner sees the app paying for itself; the minutes per record are
/// conservative and the card says they are an estimate.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/mascot/mitra.dart';
import 'package:fieldos_mobile/features/onboarding/sample_project.dart' show sampleProjectId;
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

/// Minutes of paperwork each record replaces: writing and sending a daily
/// report, keeping the muster roll and working out wages, writing up a
/// voucher, checking a delivery against the challan, and typing a bill.
const minutesPerReport = 15.0;
const minutesPerAttendance = 0.5;
const minutesPerVoucher = 2.0;
const minutesPerDelivery = 3.0;
const minutesPerBill = 30.0;

class ValueSummary {
  const ValueSummary({
    required this.reports,
    required this.attendance,
    required this.vouchers,
    required this.deliveries,
    required this.bills,
  });
  final int reports;
  final int attendance;
  final int vouchers;
  final int deliveries;
  final int bills;

  int get records => reports + attendance + vouchers + deliveries + bills;

  double get hoursSaved =>
      (reports * minutesPerReport +
          attendance * minutesPerAttendance +
          vouchers * minutesPerVoucher +
          deliveries * minutesPerDelivery +
          bills * minutesPerBill) /
      60;
}

bool _inMonth(DateTime t, DateTime month) {
  final l = t.toLocal();
  return l.year == month.year && l.month == month.month;
}

/// This calendar month across the company's real sites (not the demo).
Future<ValueSummary> buildValueSummary(AppDatabase db, String companyId, {DateTime? now}) async {
  final at = now ?? DateTime.now();
  final sample = await sampleProjectId(db, companyId);
  var reports = 0, attendance = 0, vouchers = 0, deliveries = 0, bills = 0;
  for (final p in await db.projectDao.forCompany(companyId)) {
    if (p.id == sample) continue;
    reports += (await db.dprDao.forProject(p.id)).where((d) => _inMonth(d.entryDate, at)).length;
    attendance += (await db.attendanceDao.forProject(p.id)).where((a) => _inMonth(a.punchIn, at)).length;
    vouchers += (await db.expenseDao.forProject(p.id)).where((e) => _inMonth(e.createdAt, at)).length;
    deliveries += (await db.materialDao.forProject(p.id)).where((r) => r.amount > 0 && _inMonth(r.receivedOn, at)).length;
    bills += (await db.billDao.forProject(p.id)).where((b) => _inMonth(b.billDate, at)).length;
  }
  return ValueSummary(reports: reports, attendance: attendance, vouchers: vouchers, deliveries: deliveries, bills: bills);
}

final valueSummaryProvider = FutureProvider.autoDispose.family<ValueSummary, String>(
    (ref, companyId) => buildValueSummary(ref.watch(appDatabaseProvider), companyId));

String hoursLabel(double h) {
  if (h < 1) return tr('under an hour');
  final r = h.round();
  return r == 1 ? tr('about 1 hour') : trf('about {n} hours', {'n': r});
}

/// The card's count line, e.g. "1 expense · 3 daily reports".
String valueFacts(ValueSummary v) => [
      if (v.reports > 0) v.reports == 1 ? tr('1 daily report') : trf('{n} daily reports', {'n': v.reports}),
      if (v.attendance > 0)
        v.attendance == 1 ? tr('1 attendance entry') : trf('{n} attendance entries', {'n': v.attendance}),
      if (v.vouchers > 0) v.vouchers == 1 ? tr('1 expense') : trf('{n} expenses', {'n': v.vouchers}),
      if (v.deliveries > 0)
        v.deliveries == 1 ? tr('1 delivery checked') : trf('{n} deliveries checked', {'n': v.deliveries}),
      if (v.bills > 0) v.bills == 1 ? tr('1 client bill') : trf('{n} client bills', {'n': v.bills}),
    ].join(' · ');

class ValueCard extends ConsumerWidget {
  const ValueCard({super.key, required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(valueSummaryProvider(companyId)).valueOrNull;
    if (v == null || v.records == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final facts = valueFacts(v);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
        child: Row(children: [
          const Mitra(mood: MitraMood.chai, size: 72),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('This month with FieldOS'),
                  style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSecondaryContainer)),
              const SizedBox(height: 2),
              Text(trf('{hours} of paperwork saved', {'hours': hoursLabel(v.hoursSaved)}),
                  style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSecondaryContainer)),
              const SizedBox(height: 4),
              Text(facts, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSecondaryContainer)),
              Text(tr('An estimate from what your team recorded.'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSecondaryContainer.withValues(alpha: 0.7))),
            ]),
          ),
        ]),
      ),
    );
  }
}
