/// The pilot scorecard: week 1 against days 8 to 30, from the site's own
/// records (reports, cash counts, bills, challans, fences, payments).
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/reports/pilot_scorecard.dart';

late AppDatabase db;
late Project site;
late File photo;

// Monday 2 Nov 2026. Week 1 runs to Sunday 8 Nov; days 8 to 30 are 9 Nov to 1 Dec.
final _start = DateTime(2026, 11, 2);
DateTime _d(int day, [int hour = 18]) => DateTime(2026, 11, day, hour);
String _day(int day) => '2026-11-${day.toString().padLeft(2, '0')}';

ScoreRow _row(PilotScorecard c, String m) => c.rows.singleWhere((r) => r.measure == m);

void main() {
  setUp(() async {
    db = AppDatabase.memory();
    final c = await db.companyDao.create('Sai Constructions');
    site = await db.projectDao.create(ProjectsCompanion.insert(id: 'site-1', companyId: c.id, name: 'Kompally Villas'));
    final dir = await Directory.systemTemp.createTemp('fieldos_pilot');
    addTearDown(() => dir.delete(recursive: true));
    photo = File('${dir.path}/slip.jpg')..writeAsBytesSync([1, 2, 3]);
  });
  tearDown(() => db.close());

  test('periods: week 1, days 8 to 30, days 31 to 60, cut off at today', () {
    final ps = pilotPeriods(_start, DateTime(2026, 11, 20));
    expect(ps.map((p) => p.label), ['Week 1 (baseline)', 'Days 8 to 30', 'Days 31 to 60']);
    expect(ps[0].fromDay, '2026-11-02');
    expect(ps[0].toDay, '2026-11-08');
    expect(ps[1].fromDay, '2026-11-09');
    expect(ps[1].toDay, '2026-11-20');
    expect(ps[2].started, isFalse);
  });

  test('reports, cash, bills, challans and fences: week 1 against what came after', () async {
    // Week 1: reports on 3 of 6 working days, one of them a day late.
    for (final (day, late) in [(2, false), (3, false), (4, true)]) {
      await db.dprDao.create(DprEntriesCompanion.insert(
        id: 'dpr-$day',
        projectId: site.id,
        createdBy: 'sup',
        entryDate: _d(day),
        workSummary: 'Work',
        createdAt: Value(late ? _d(day + 1, 9) : _d(day)),
      ));
    }
    // Days 9-14: every working day reported on time.
    for (var day = 9; day <= 14; day++) {
      await db.dprDao.create(DprEntriesCompanion.insert(
          id: 'dpr-$day', projectId: site.id, createdBy: 'sup', entryDate: _d(day), workSummary: 'Work', createdAt: Value(_d(day))));
    }
    // Cash: ₹800 short at the week 1 count, nothing short later.
    await db.cashBookDao.record(projectId: site.id, holderId: 'sup', kind: 'given', amount: 10000, movedOn: _day(2), by: 'o');
    await db.expenseDao.create(SiteExpensesCompanion.insert(
        id: 'e1', projectId: site.id, category: 'Petty cash', amount: 2000, incurredOn: _day(3), recordedBy: 'sup',
        createdAt: Value(_d(3, 12))));
    await db.cashBookDao.record(
        projectId: site.id, holderId: 'sup', kind: 'counted', amount: 7200, movedOn: _day(7), by: 'o', now: _d(7, 19));
    final billed = await db.expenseDao.create(SiteExpensesCompanion.insert(
        id: 'e2', projectId: site.id, category: 'Petty cash', amount: 1000, incurredOn: _day(10), recordedBy: 'sup',
        createdAt: Value(_d(10, 12))));
    await db.expenseDao.attach(billed.id, photo.path);
    await db.cashBookDao.record(
        projectId: site.id, holderId: 'sup', kind: 'counted', amount: 6200, movedOn: _day(14), by: 'o', now: _d(14, 19));
    // Challans: none in week 1, one of one later.
    await db.materialDao.createReceipt(MaterialReceiptsCompanion.insert(
        id: 'r1', projectId: site.id, materialName: 'Cement', quantity: 50, amount: 20000, receivedBy: 'sup', receivedOn: _d(4, 10)));
    final r2 = await db.materialDao.createReceipt(MaterialReceiptsCompanion.insert(
        id: 'r2', projectId: site.id, materialName: 'Cement', quantity: 50, amount: 20000, receivedBy: 'sup', receivedOn: _d(11, 10)));
    await db.materialDao.attachSlip(r2.id, photo.path);
    // Fence: 1 of 2 punches inside in week 1, 2 of 2 later.
    for (final (id, day, inside) in [('a1', 3, true), ('a2', 3, false), ('a3', 10, true), ('a4', 10, true)]) {
      await db.attendanceDao.punchIn(LabourAttendanceCompanion.insert(
          id: id, projectId: site.id, workerName: 'Mason $id', recordedBy: 'sup', punchIn: _d(day, 9),
          withinGeofence: Value(inside)));
    }

    final card = await buildPilotScorecard(db, site, _start, now: DateTime(2026, 11, 14, 20));

    final reported = _row(card, 'Days with a daily report');
    expect(reported.values[0], 50); // 3 of 6 working days (Sunday 8 left out)
    expect(reported.values[1], 100); // 9-14: 6 of 6
    expect(reported.values[2], isNull);
    expect(reported.change, 'better');
    expect(_row(card, 'Daily reports sent the same day').values[0], closeTo(33.3, 0.1));

    final short = _row(card, 'Cash short at counts');
    expect(short.values[0], 800);
    expect(short.values[1], 0);
    expect(short.change, 'better');
    expect(_row(card, 'Cash spent with no bill').values[0], 2000);
    expect(_row(card, 'Cash spent with no bill').values[1], 0);
    expect(_row(card, 'Expenses with a bill attached').values[1], 100);

    expect(_row(card, 'Deliveries with a challan photo').values, [0, 100, null]);
    expect(_row(card, 'Labour marked inside the site fence').values, [50, 100, null]);
    expect(_row(card, 'Office time saved (estimate)').values[0], greaterThan(0));
  });

  test('days from bill to payment, from payments put against bills', () async {
    await db.billDao.create(ClientBillsCompanion.insert(
        id: 'b1', projectId: site.id, kind: 'ra', billNumber: 'RA-1', billDate: _d(1, 10), clientName: 'Client',
        linesJson: '[]', gross: 100000, netPayable: 100000, recordedBy: 'o'));
    await db.paymentDao.create(PaymentsReceivedCompanion.insert(
        id: 'p1', projectId: site.id, amount: 100000, receivedOn: _d(11, 10), fromParty: 'Client', mode: 'bank', recordedBy: 'o'));
    await db.billingRecordsDao.allocate(paymentId: 'p1', billId: 'b1', amount: 100000, by: 'o');

    final card = await buildPilotScorecard(db, site, _start, now: DateTime(2026, 11, 14, 20));
    final row = _row(card, 'Days from bill to payment');
    expect(row.values[0], isNull);
    expect(row.values[1], 10);
  });

  test('the start date is kept per site, and the PDF is made', () async {
    expect(await loadPilotStart(db, site.id), isNull);
    await savePilotStart(db, site.id, _start);
    expect(await loadPilotStart(db, site.id), DateTime(2026, 11, 2));
    final card = await buildPilotScorecard(db, site, _start, now: DateTime(2026, 11, 14));
    final pdf = await buildPilotScorecardPdf(card, companyName: 'Sai Constructions', now: DateTime(2026, 11, 14));
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
  });
}
