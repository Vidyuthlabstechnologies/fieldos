/// US build: things the US app got wrong that the other market tests did
/// not catch. The daylight-saving tests only bite in a US time zone; run
/// them with `TZ=America/New_York flutter test test/market_us_test.dart`
/// (in UTC there is no clock change and they pass either way).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/close/week_close.dart';
import 'package:fieldos_mobile/features/export/audit_trail.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';

Worker _worker(String id, String name, double? rate) =>
    Worker(id: id, projectId: 'p', name: name, dailyWage: rate, status: 'active', createdAt: DateTime(2026, 1, 1));

LabourAttendanceData _punch(String id, DateTime inAt, double hours) => LabourAttendanceData(
      id: '${id}_$inAt',
      projectId: 'p',
      workerName: id,
      workerId: id,
      recordedBy: 'u',
      punchIn: inAt,
      punchOut: inAt.add(Duration(minutes: (hours * 60).round())),
      createdAt: inAt,
    );

void main() {
  tearDown(() {
    debugSetMarket(Market.india);
    setCurrentLanguage(AppLanguage.en);
  });

  group('weeks across a daylight saving change', () {
    test('a week is seven calendar days, from midnight to midnight', () {
      // US clocks go forward on Sun 8 Mar 2026 and back on Sun 1 Nov 2026.
      expect(addDays(DateTime(2026, 3, 2), 7), DateTime(2026, 3, 9));
      expect(addDays(DateTime(2026, 11, 2), -7), DateTime(2026, 10, 26));
      expect(addDays(DateTime(2026, 10, 26), 7), DateTime(2026, 11, 2));
      expect(weekStart(DateTime(2026, 3, 8, 12)), DateTime(2026, 3, 2));
    });

    test('US week close: the Monday after the clocks go forward is next week', () {
      debugSetMarket(Market.us);
      final w = buildWeekClose(
        project: Project(id: 'p', companyId: 'c', name: 'Job', status: 'active', createdAt: DateTime(2026)),
        weekOf: DateTime(2026, 3, 4),
        workers: [_worker('mike', 'Mike', 20)],
        punches: [_punch('mike', DateTime(2026, 3, 9, 7), 8)],
        marks: const [],
        expenses: const [],
        receipts: const [],
        orders: const [],
        requests: const [],
        reports: const [],
        reviews: const [],
        now: DateTime(2026, 3, 20),
      );
      expect(w.to, DateTime(2026, 3, 9));
      expect(w.sheet.lines.single.hours, 0);
      expect(w.sheet.lines.single.earned, 0);
    });
  });

  test('US wage sheet share text: hours at the hourly rate, not days', () {
    debugSetMarket(Market.us);
    final mon = DateTime(2026, 11, 2);
    final sheet = buildWageSheet(
      workers: [_worker('mike', 'Mike', 30)],
      punches: [for (var i = 0; i < 5; i++) _punch('mike', mon.add(Duration(days: i, hours: 7)), 9)],
      expenses: const [],
      from: mon,
      to: addDays(mon, 7),
    );
    final text = wageSheetShareText(sheet, projectName: 'Job', range: 'Nov 2 to Nov 8');
    expect(text, contains(r'Mike: 45 h (5 h overtime) × $30/hr = $1,425, due $1,425'));
    expect(text, isNot(contains('days')));
  });

  test('India wage sheet share text: days at the day wage, plus overtime pay', () {
    final mon = DateTime(2026, 11, 2);
    final sheet = buildWageSheet(
      workers: [_worker('r', 'Ramesh', 800)],
      punches: [_punch('r', mon.add(const Duration(hours: 9)), 10)],
      expenses: const [],
      from: mon,
      to: addDays(mon, 7),
    );
    expect(wageSheetShareText(sheet, projectName: 'Job', range: 'r'),
        contains('Ramesh: 1 days × ₹800 + 2 h overtime ₹400 = ₹1,200, due ₹1,200'));
  });

  test('US: a 10-digit phone opens WhatsApp with +1, not +91', () {
    debugSetMarket(Market.us);
    expect(whatsAppNumber('(512) 555-0134'), '15125550134');
    expect(whatsAppNumber('+1 512 555 0134'), '15125550134');
    expect(whatsAppNumber('1-512-555-0134'), '15125550134');
    debugSetMarket(Market.india);
    expect(whatsAppNumber('98480 12345'), '919848012345');
    expect(whatsAppNumber('+91 98480 12345'), '919848012345');
  });

  test('US Spanish: the rate is per hour and payment is by bank app, not UPI', () {
    debugSetMarket(Market.us);
    setCurrentLanguage(AppLanguage.es);
    expect(tr('Daily wage'), isNot(contains('día')));
    expect(tr('{amount}/day'), '{amount}/hora');
    expect(tr('Daily wage (₹)'), contains(r'$'));
    expect(
        tr('A day counts as full at 7 hours on site and half at 3.5 hours, unless it was marked by hand on the day register. Tap a worker to pay wages or an advance.'),
        contains('40 horas'));
    expect(tr('Approve it in your UPI or bank app. FieldOS opens by itself once {store} confirms the payment, usually within a few minutes.'),
        isNot(contains('UPI')));
    expect(tr('Your payment is waiting for approval, for example in your UPI app. FieldOS opens by itself once {store} confirms it.'),
        isNot(contains('UPI')));
  });

  test('US: a forgotten clock-out is not a half day where pay is by the hour', () {
    debugSetMarket(Market.us);
    for (final l in [AppLanguage.en, AppLanguage.es]) {
      setCurrentLanguage(l);
      expect(tr('1 missing punch-out (half day)'), isNot(anyOf(contains('half'), contains('medio'))));
      expect(tr('{n} missing punch-outs (half days)'), isNot(anyOf(contains('half'), contains('medio'))));
    }
  });

  test('US audit trail CSV heads the amount in dollars', () {
    debugSetMarket(Market.us);
    final csv = auditCsv(const [], nameOf: (id) => id, siteName: const {});
    expect(csv, startsWith(r'When,Site,Who,What,Item,Amount ($),Note,Record'));
    debugSetMarket(Market.india);
    expect(auditCsv(const [], nameOf: (id) => id, siteName: const {}), startsWith('When,Site,Who,What,Item,Amount (₹),'));
  });
}
