/// The daily site close: the Today checklist and its explicit "nothing"
/// marks, the WhatsApp report written from what is recorded, submitted vs
/// not received vs missed, late (backdated) entries, miss reasons, repeat
/// misses, the backup supervisor, what syncs, and partial verification in
/// the weekly close.
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/close/week_close.dart';
import 'package:fieldos_mobile/features/close/week_close_data.dart';
import 'package:fieldos_mobile/features/daily/day_close.dart';
import 'package:fieldos_mobile/features/daily/day_close_data.dart';

// Tuesday 10 Nov 2026; the week runs Monday 9 to Sunday 15.
final _tue = DateTime(2026, 11, 10);
final _mon = DateTime(2026, 11, 9);

late AppDatabase db;
late Project site;

Future<Worker> _worker(String name, double wage) => db.workerDao.create(
    WorkersCompanion.insert(id: 'w-${name.toLowerCase()}', projectId: site.id, name: name, dailyWage: Value(wage)));

Future<void> _punch(Worker w, DateTime day, {DateTime? enteredAt}) => db.attendanceDao.punchIn(LabourAttendanceCompanion.insert(
      id: '${w.id}-${day.toIso8601String()}',
      projectId: site.id,
      workerName: w.name,
      workerId: Value(w.id),
      recordedBy: 'sup',
      punchIn: day.add(const Duration(hours: 9)),
      punchOut: Value(day.add(const Duration(hours: 17))),
      createdAt: Value(enteredAt ?? day.add(const Duration(hours: 9))),
    ));

Future<void> _report(DateTime day, String work, {DateTime? enteredAt}) => db.dprDao.create(DprEntriesCompanion.insert(
      id: 'dpr-${day.day}',
      projectId: site.id,
      createdBy: 'sup',
      entryDate: day.add(const Duration(hours: 18)),
      workSummary: work,
      createdAt: Value(enteredAt ?? day.add(const Duration(hours: 18))),
    ));

Future<DayClose> _day(DateTime d) => loadDayClose(db, site, d);

void main() {
  late DayCloseActions supervisor;
  late DayCloseActions manager;

  setUp(() async {
    db = AppDatabase.memory();
    final c = await db.companyDao.create('Sai Constructions');
    site = await db.projectDao.create(
        ProjectsCompanion.insert(id: 'site-1', companyId: c.id, name: 'Kompally Villas', status: const Value('active')));
    supervisor = DayCloseActions(db, userId: 'sup', role: Roles.member);
    manager = DayCloseActions(db, userId: 'pm', role: Roles.manager);
  });
  tearDown(() => db.close());

  test('the checklist pulls in what is recorded and lists exactly what is missing', () async {
    final ramesh = await _worker('Ramesh', 800);
    await _punch(ramesh, _tue);
    var d = await _day(_tue);
    expect(missingItems(d.snapshot, const NothingMarks()), [CheckKind.deliveries, CheckKind.expenses, CheckKind.work]);

    await _report(_tue, 'Slab shuttering, level 2');
    d = await _day(_tue);
    // Quiet day: say "no deliveries" and "no expenses" and it can go.
    const quiet = NothingMarks(noDeliveries: true, noExpenses: true);
    expect(missingItems(d.snapshot, quiet), isEmpty);
    final items = checklist(d.snapshot, quiet);
    expect(items.map((i) => i.state), [CheckState.recorded, CheckState.nothing, CheckState.nothing, CheckState.recorded]);

    // Not allowed with something still missing.
    expect(() => supervisor.submit(d, const NothingMarks()), throwsStateError);
    final sent = await supervisor.submit(d, quiet, now: _tue.add(const Duration(hours: 18, minutes: 30)));
    expect(sent.noDeliveries, isTrue);
    expect(sent.noExpenses, isTrue);
    d = await _day(_tue);
    expect(d.status(_tue.add(const Duration(hours: 20))), DayStatus.submitted);
    expect(d.submittedLate, isFalse);
  });

  test('"Site closed" covers everything in one tap and the report says so', () async {
    final d = await _day(_tue);
    expect(missingItems(d.snapshot, const NothingMarks(siteClosed: true)), isEmpty);
    await supervisor.submit(d, const NothingMarks(siteClosed: true));
    final after = await _day(_tue);
    expect(after.status(_tue.add(const Duration(hours: 23))), DayStatus.siteClosed);
    expect(whatsAppReport(after.snapshot, after.marks), contains('Site closed today.'));
  });

  test('an empty register reads "not received", then "missed" the next morning, never zero activity', () async {
    final d = await _day(_tue);
    expect(d.status(_tue.add(const Duration(hours: 12))), DayStatus.open);
    expect(d.status(_tue.add(const Duration(hours: 19, minutes: 1))), DayStatus.notReceived);
    expect(d.status(_tue.add(const Duration(days: 1, hours: 9))), DayStatus.missed);

    // A later cutoff moves both.
    await manager.saveSetup(site.id, const CloseSetup(cutoffMinutes: 20 * 60));
    final later = await _day(_tue);
    expect(later.status(_tue.add(const Duration(hours: 19, minutes: 30))), DayStatus.open);
  });

  test('the WhatsApp report is written from the records, with nothing typed twice', () async {
    final ramesh = await _worker('Ramesh', 800);
    final suresh = await _worker('Suresh', 700);
    await _punch(ramesh, _tue);
    await _punch(suresh, _tue);
    await db.materialDao.createReceipt(MaterialReceiptsCompanion.insert(
        id: 'grn-1', projectId: site.id, materialName: 'Cement', quantity: 50, unit: const Value('bags'), amount: 20000,
        receivedBy: 'sup', receivedOn: _tue.add(const Duration(hours: 11))));
    await db.expenseDao.create(SiteExpensesCompanion.insert(
        id: 'e-1', projectId: site.id, category: 'Transport', amount: 1200, incurredOn: '2026-11-10', recordedBy: 'sup',
        paidTo: const Value('Tractor')));
    await _report(_tue, 'Column casting C4 to C9');
    final d = await _day(_tue);
    final text = whatsAppReport(d.snapshot, d.marks);
    expect(text, startsWith('*Kompally Villas*'));
    expect(text, contains('2 people (Ramesh, Suresh)'));
    expect(text, contains('- Cement 50 bags'));
    expect(text, contains('₹1,200'));
    expect(text, contains('(Tractor)'));
    expect(text, contains('Column casting C4 to C9'));
  });

  test('entries made the next day show both dates and who entered them', () async {
    final ramesh = await _worker('Ramesh', 800);
    final wedMorning = _tue.add(const Duration(days: 1, hours: 8));
    await _punch(ramesh, _tue, enteredAt: wedMorning);
    await _report(_tue, 'Plastering', enteredAt: wedMorning);
    final d = await _day(_tue);
    expect(d.snapshot.backdated.length, 2);
    final e = d.snapshot.backdated.first;
    expect(e.workDay, _tue);
    expect(e.enteredAt, wedMorning);
    expect(e.by, 'sup');

    await supervisor.submit(d, const NothingMarks(noDeliveries: true, noExpenses: true), now: wedMorning);
    final sent = await _day(_tue);
    expect(sent.submittedLate, isTrue);
    expect(sent.submittedAfterCutoff, isTrue);
  });

  test('a change after sending shows; reopening and sending again keeps both on record', () async {
    final ramesh = await _worker('Ramesh', 800);
    await _punch(ramesh, _tue);
    await _report(_tue, 'Brickwork');
    var d = await _day(_tue);
    await supervisor.submit(d, const NothingMarks(noDeliveries: true, noExpenses: true));
    await db.expenseDao.create(SiteExpensesCompanion.insert(
        id: 'e-late', projectId: site.id, category: 'Tea', amount: 150, incurredOn: '2026-11-10', recordedBy: 'sup'));
    d = await _day(_tue);
    expect(d.changedSinceSubmit, isTrue);
    await supervisor.reopen(d);
    d = await _day(_tue);
    expect(d.isSubmitted, isFalse);
    await supervisor.submit(d, const NothingMarks(noDeliveries: true));
    d = await _day(_tue);
    expect(d.changedSinceSubmit, isFalse);
    expect(d.events.map((e) => e.kind), ['submitted', 'reopened', 'submitted']);
  });

  test('miss reasons are recorded for the pilot, and repeat misses are found', () async {
    final first = DateTime(2026, 11, 1);
    // Sent on time on the 1st, then nothing on the 3rd, 5th and 6th.
    for (final day in [1, 2, 4, 7, 8, 9]) {
      final d = await _day(DateTime(2026, 11, day));
      await supervisor.submit(d, const NothingMarks(siteClosed: true), now: DateTime(2026, 11, day, 18));
    }
    final missed = (await SiteRecords.load(db, site)).missed(_tue.add(const Duration(hours: 10)));
    expect(missed, [DateTime(2026, 11, 3), DateTime(2026, 11, 5), DateTime(2026, 11, 6)]);
    expect(missed.every((m) => !m.isBefore(first)), isTrue);

    final d = await _day(DateTime(2026, 11, 5));
    await supervisor.recordMissReason(d, MissReason.poorSignal);
    expect(() => supervisor.recordMissReason(d, MissReason.other), throwsArgumentError);
    final again = await _day(DateTime(2026, 11, 5));
    expect(MissReasonKey.parse(again.missReasons.single.reason), MissReason.poorSignal);

    final board = await loadDayBoard(db, site.companyId, now: _tue.add(const Duration(hours: 10)));
    expect(board.single.isRepeat, isTrue);
  });

  test('the backup supervisor takes the reminder while covering, then it goes back', () async {
    await manager.saveSetup(site.id,
        CloseSetup(supervisorId: 'sup', backupId: 'backup', backupUntil: DateTime(2026, 11, 11)));
    final s = (await SiteRecords.load(db, site)).setup;
    expect(s.responsibleOn(_tue), 'backup');
    expect(s.remindsUser('sup', _tue, canRecord: true), isFalse);
    expect(s.remindsUser('backup', _tue, canRecord: true), isTrue);
    expect(s.responsibleOn(DateTime(2026, 11, 12)), 'sup');
    // Only a manager sets it.
    expect(() => supervisor.saveSetup(site.id, const CloseSetup()), throwsA(isA<DayCloseNotAllowed>()));
    // Nobody named: everyone who records gets it.
    expect(const CloseSetup().remindsUser('anyone', _tue, canRecord: true), isTrue);
  });

  test('submissions, reasons and the setup sync', () async {
    final d = await _day(_tue);
    await supervisor.submit(d, const NothingMarks(siteClosed: true));
    await supervisor.recordMissReason(d, MissReason.forgot);
    await manager.saveSetup(site.id, const CloseSetup(cutoffMinutes: 18 * 60, supervisorId: 'sup'));
    final outbox = await db.select(db.syncOutbox).get();
    final events = outbox.where((e) => e.targetTable == 'site_day_events').toList();
    expect(events.length, 2);
    final p = jsonDecode(events.first.payload) as Map<String, dynamic>;
    expect(p['work_date'], '2026-11-10');
    expect(p['kind'], 'submitted');
    expect(p['site_closed'], isTrue);
    expect(await db.dayCloseDao.isWaitingToSync(events.first.recordId), isTrue);
    final setup = outbox.singleWhere((e) => e.targetTable == 'site_close_settings');
    expect(setup.operation, 'upsert');
    expect((jsonDecode(setup.payload) as Map)['cutoff_minutes'], 18 * 60);
  });

  test('weekly wages: days without a submitted report are held; the rest can go, an override is recorded', () async {
    final ramesh = await _worker('Ramesh', 800);
    await _punch(ramesh, _mon);
    await _punch(ramesh, _tue);
    // Monday's report was sent; Tuesday's was not.
    await _report(_mon, 'Excavation');
    await supervisor.submit(await _day(_mon), const NothingMarks(noDeliveries: true, noExpenses: true));

    final w = await loadWeekClose(db, site, _tue, now: _tue.add(const Duration(hours: 20)));
    final wages = w.items.firstWhere((i) => i.kind == CloseKind.wages && i.id == ramesh.id);
    var v = await loadWeekVerification(db, w);
    final iv = v.of(wages)!;
    expect(iv.verified, 800);
    expect(iv.unverified, 800);
    expect(iv.unverifiedDays, [_tue]);

    expect(() => supervisor.releaseVerified(v, wages), throwsA(isA<DayCloseNotAllowed>()));
    final rel = await manager.releaseVerified(v, wages);
    expect(rel.amount, 800);
    expect(rel.recordedBy, 'pm');

    expect(() => manager.overrideAndApprove(v, wages, ' '), throwsArgumentError);
    final review = await manager.overrideAndApprove(v, wages, 'Saw him on site, phone was dead');
    expect(review.note, 'Override: Saw him on site, phone was dead');
    v = await loadWeekVerification(db, await loadWeekClose(db, site, _tue, now: _tue.add(const Duration(hours: 20))));
    final o = v.overrideFor(wages)!;
    expect(o.recordedBy, 'pm');
    expect(o.amount, 800);
    expect(v.releaseFor(wages)!.amount, 800);
  });
}
