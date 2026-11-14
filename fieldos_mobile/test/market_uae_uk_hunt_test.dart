/// UAE and UK builds: bugs found in the market hunt, each pinned here.
///
/// Two tests turn on the phone's time zone (UK clocks change in March and
/// October); run them with `TZ=Europe/London flutter test ...` to see the
/// daylight-saving case. In UTC they pass either way.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/money/billing_calc.dart';
import 'package:fieldos_mobile/features/reminders/reminders.dart';
import 'package:fieldos_mobile/features/workers/worker_permits.dart';
import 'package:fieldos_mobile/features/workers/worker_tools.dart';
import 'package:fieldos_mobile/l10n/language.dart';

WorkerPermit _permit(DateTime expiresOn) => WorkerPermit(
      id: 'wp1',
      projectId: 'p1',
      workerId: 'w1',
      kind: 'cscs',
      expiresOn: expiresOn,
      createdBy: 'u1',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  tearDown(() {
    debugSetMarket(Market.india);
    setCurrentLanguage(AppLanguage.en);
  });

  test('only a VAT-registered business heads its bill TAX INVOICE / VAT INVOICE', () {
    debugSetMarket(Market.uae);
    expect(invoiceTitle(ourGstin: '', gstRate: 0), 'INVOICE');
    expect(invoiceTitle(ourGstin: '100123456700003', gstRate: 5), 'TAX INVOICE');
    expect(invoiceTitle(ourGstin: '100123456700003', gstRate: 0), 'TAX INVOICE');
    debugSetMarket(Market.uk);
    expect(invoiceTitle(ourGstin: '', gstRate: 0), 'INVOICE');
    expect(invoiceTitle(ourGstin: 'GB123456789', gstRate: 20), 'VAT INVOICE');
    debugSetMarket(Market.us);
    expect(invoiceTitle(ourGstin: '', gstRate: 0), 'INVOICE');
    debugSetMarket(Market.india);
    expect(invoiceTitle(ourGstin: '', gstRate: 0), 'INVOICE');
    expect(invoiceTitle(ourGstin: '36ABCDE1234F1Z5', gstRate: 0), 'BILL OF SUPPLY');
  });

  test('WhatsApp numbers get this market\'s country code, not India\'s', () {
    debugSetMarket(Market.uae);
    expect(whatsAppNumber('050 123 4567'), '971501234567');
    expect(whatsAppNumber('+971 50 123 4567'), '971501234567');
    expect(whatsAppNumber('00971501234567'), '971501234567');
    expect(whatsAppNumber('50 123 4567'), '971501234567');
    debugSetMarket(Market.uk);
    expect(whatsAppNumber('07700 900123'), '447700900123');
    expect(whatsAppNumber('+44 7700 900123'), '447700900123');
    debugSetMarket(Market.india);
    expect(whatsAppNumber('98480 12345'), '919848012345');
    expect(whatsAppNumber('+91 98480 12345'), '919848012345');
    expect(whatsAppNumber('098480 12345'), '919848012345');
  });

  test('a UAE worker added twice, once with +971 and once with 0, is caught', () {
    debugSetMarket(Market.uae);
    expect(normalizePhone('+971 50 123 4567'), normalizePhone('050 123 4567'));
    final existing = [
      Worker(
          id: 'w1',
          projectId: 'p1',
          name: 'Rajan',
          phone: '+971 50 123 4567',
          status: 'active',
          createdAt: DateTime(2026)),
    ];
    expect(findDuplicate(existing, name: 'R. Kumar', phone: '0501234567')?.id, 'w1');
    debugSetMarket(Market.india);
    expect(normalizePhone('+91 98480 12345'), '9848012345');
    expect(normalizePhone('098480-12345'), '9848012345');
  });

  test('a UK card expiring on the day the clocks go forward is expired the next day', () {
    debugSetMarket(Market.uk);
    final p = _permit(DateTime(2027, 3, 28));
    expect(daysLeft(p, DateTime(2027, 3, 29)), -1);
    expect(permitStatus(p, DateTime(2027, 3, 29)), PermitStatus.expired);
    expect(daysLeft(_permit(DateTime(2027, 4, 4)), DateTime(2027, 3, 28)), 7);
  });

  test('UK permit reminders and task reminders keep their day across the clock change', () {
    debugSetMarket(Market.uk);
    final now = DateTime(2027, 3, 27, 8);
    final planned = planReminders(
      now: now,
      settings: const ReminderSettings(reportOn: false, tasksOn: false, briefOn: false),
      runningSites: 0,
      reportedToday: true,
      openTasks: const [],
      isOwner: true,
      permits: [(worker: 'Tom', permit: 'CSCS card', expiresOn: DateTime(2027, 4, 5))],
    );
    final permit = planned.where((r) => r.payload == 'permits').toList();
    expect(permit, hasLength(1));
    // 7 days before 5 April is 29 March, at 9 in the morning local time.
    expect(permit.single.at, DateTime(2027, 3, 29, 9));
  });

  test('the UK app pays by the hour, so its labels ask for an hourly rate', () {
    debugSetMarket(Market.uk);
    expect(market.payHourly, isTrue);
    expect(tr('Daily wage'), 'Hourly rate');
    expect(tr('Daily wage (₹)'), 'Hourly rate (£)');
    expect(trf('{amount}/day', {'amount': money(15)}), '£15/hr');
    expect(trf('{amount} a day', {'amount': money(15)}), '£15 an hour');
    expect(tr('no daily wage set'), isNot(contains('daily')));
    expect(tr('GST'), 'VAT');
    expect(tr('DPR'), isNot('DPR'));
  });
}
