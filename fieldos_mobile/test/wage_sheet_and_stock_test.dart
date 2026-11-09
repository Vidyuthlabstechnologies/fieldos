import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet.dart';
import 'package:fieldos_mobile/features/procurement/site_stock.dart';

Worker _worker(String id, String name, double? wage, {String status = 'active'}) => Worker(
    id: id, projectId: 'p', name: name, dailyWage: wage, status: status, createdAt: DateTime(2026, 1, 1));

LabourAttendanceData _punch(String? workerId, String name, DateTime inAt, double? hours) => LabourAttendanceData(
      id: '${name}_$inAt',
      projectId: 'p',
      workerName: name,
      workerId: workerId,
      recordedBy: 'u',
      punchIn: inAt,
      punchOut: hours == null ? null : inAt.add(Duration(minutes: (hours * 60).round())),
      createdAt: inAt,
    );

SiteExpense _paid(String workerId, String on, double amount) => SiteExpense(
    id: '$workerId$on$amount', projectId: 'p', category: 'Labour', amount: amount, incurredOn: on,
    recordedBy: 'u', createdAt: DateTime(2026, 1, 1), workerId: workerId, gstInterState: false, voided: false);

void main() {
  test('day credit: full, half, nothing, and a forgotten punch-out counts half', () {
    expect(dayCredit(8, hasOpenPunch: false), 1);
    expect(dayCredit(7, hasOpenPunch: false), 1);
    expect(dayCredit(4, hasOpenPunch: false), 0.5);
    expect(dayCredit(2, hasOpenPunch: false), 0);
    expect(dayCredit(0, hasOpenPunch: true), 0.5);
    expect(dayCredit(8, hasOpenPunch: true), 1);
  });

  test('a punch closed days later counts like a forgotten punch-out, not as days of overtime', () {
    final sheet = buildWageSheet(
      workers: [_worker('r', 'Ramesh', 800)],
      punches: [_punch('r', 'Ramesh', DateTime(2026, 11, 2, 9), 50)], // punched out two days late
      expenses: const [],
      from: DateTime(2026, 11, 2),
      to: DateTime(2026, 11, 9),
    );
    final r = sheet.lines.single;
    expect(r.days, 0.5);
    expect(r.overtimeHours, 0);
    expect(r.missingPunchOuts, 1);
  });

  test('weekStart is the Monday', () {
    expect(weekStart(DateTime(2026, 11, 5, 15)), DateTime(2026, 11, 2)); // Thu -> Mon
    expect(weekStart(DateTime(2026, 11, 8)), DateTime(2026, 11, 2)); // Sun -> Mon
  });

  test('wage sheet: days x wage, overtime, payments in and before the week, balance owed', () {
    final from = DateTime(2026, 11, 2), to = DateTime(2026, 11, 9);
    final sheet = buildWageSheet(
      workers: [_worker('r', 'Ramesh', 800), _worker('s', 'Suresh', 700), _worker('x', 'Left site', 600, status: 'inactive')],
      punches: [
        _punch('r', 'Ramesh', DateTime(2026, 10, 30, 9), 8), // last week: earned before
        _punch('r', 'Ramesh', DateTime(2026, 11, 2, 9), 10), // full day, 2h OT
        _punch('r', 'Ramesh', DateTime(2026, 11, 3, 9), 4), // half
        _punch('r', 'Ramesh', DateTime(2026, 11, 4, 9), null), // forgot punch-out: half, flagged
        _punch('s', 'Suresh', DateTime(2026, 11, 2, 8), 3.5), // split shift same day
        _punch('s', 'Suresh', DateTime(2026, 11, 2, 13), 4),
        _punch(null, 'Day helper', DateTime(2026, 11, 3, 9), 8), // not in the directory
      ],
      expenses: [_paid('r', '2026-10-31', 1000), _paid('r', '2026-11-04', 500)],
      from: from,
      to: to,
    );
    final r = sheet.lines.firstWhere((l) => l.name == 'Ramesh');
    expect(r.days, 2);
    expect(r.earned, 1600);
    expect(r.overtimeHours, 2);
    expect(r.missingPunchOuts, 1);
    expect(r.paidInPeriod, 500);
    // earned 800 before + 1600 now - 1000 advance before - 500 this week
    expect(r.balanceDue, 900);

    final s = sheet.lines.firstWhere((l) => l.name == 'Suresh');
    expect(s.days, 1, reason: '7.5 h across two punches is a full day');

    final helper = sheet.lines.firstWhere((l) => l.name == 'Day helper');
    expect(helper.days, 1);
    expect(helper.dailyWage, isNull);
    expect(helper.earned, 0);

    expect(sheet.lines.any((l) => l.name == 'Left site'), isFalse, reason: 'inactive with no punches is hidden');
    expect(sheet.totalEarned, 1600 + 700);
    expect(sheet.totalPaid, 500);
    expect(sheet.totalDue, 900 + 700);
  });

  test('site stock: received minus used, merged by name, units kept apart, problems first', () {
    MaterialReceipt rec(String name, double q, String? unit) => MaterialReceipt(
        id: '$name$q', projectId: 'p', materialName: name, quantity: q, unit: unit, amount: 0, receivedBy: 'u',
        receivedOn: DateTime(2026, 11, 1), createdAt: DateTime(2026, 11, 1));
    MaterialUsageData use(String name, double q, String? unit) => MaterialUsageData(
        id: '$name$q', projectId: 'p', materialName: name, quantity: q, unit: unit, recordedBy: 'u',
        usedOn: DateTime(2026, 11, 2), createdAt: DateTime(2026, 11, 2));

    final stock = buildSiteStock(
      [rec('Cement', 100, 'bags'), rec('cement ', 50, 'Bags'), rec('Steel 12mm', 2, 'tonnes'), rec('Sand', 10, 'cum'),
       rec('Bricks', 5000, 'nos')],
      [use('Cement', 140, 'bags'), use('Steel 12mm', 2, 'tonnes'), use('Sand', 12, 'cum'), use('Bricks', 1000, 'nos')],
    );
    final byName = {for (final l in stock) l.name.toLowerCase(): l};
    expect(byName['cement']!.received, 150);
    expect(byName['cement']!.balance, 10);
    expect(byName['cement']!.status, StockStatus.low);
    expect(byName['steel 12mm']!.status, StockStatus.out);
    expect(byName['sand']!.status, StockStatus.overused);
    expect(byName['bricks']!.status, StockStatus.ok);
    expect(stock.first.name, 'Sand', reason: 'used more than received is the first thing to look at');
  });
}
