/// The weekly site close: what gets flagged, how approvals, send-backs and
/// corrections move an item, who may do what, closing and reopening the
/// week, what syncs, and the pack for accounts.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/close/week_close.dart';
import 'package:fieldos_mobile/features/close/week_close_data.dart';
import 'package:fieldos_mobile/features/close/week_close_pack.dart';

// Monday 2 Nov 2026 to Sunday 8 Nov; "now" is the Saturday evening.
final _mon = DateTime(2026, 11, 2);
final _now = DateTime(2026, 11, 7, 19);

late AppDatabase db;
late Project site;

Future<Worker> _worker(String name, double? wage) => db.workerDao.create(WorkersCompanion.insert(
    id: 'w-${name.toLowerCase()}', projectId: site.id, name: name, dailyWage: Value(wage)));

Future<void> _day(Worker w, DateTime inAt, {double? hours = 8}) => db.attendanceDao.punchIn(LabourAttendanceCompanion.insert(
      id: '${w.id}-${inAt.toIso8601String()}',
      projectId: site.id,
      workerName: w.name,
      workerId: Value(w.id),
      recordedBy: 'sup',
      punchIn: inAt,
      punchOut: Value(hours == null ? null : inAt.add(Duration(minutes: (hours * 60).round()))),
    ));

Future<SiteExpense> _expense(String on, double amount, {String category = 'Material', String? workerId, String? paidTo}) =>
    db.expenseDao.create(SiteExpensesCompanion.insert(
      id: 'e-$on-$amount',
      projectId: site.id,
      category: category,
      amount: amount,
      incurredOn: on,
      recordedBy: 'sup',
      workerId: Value(workerId),
      paidTo: Value(paidTo),
    ));

/// A PO for [qty] bags of cement (through a request, which carries the qty).
Future<PurchaseOrder> _cementOrder(double qty) async {
  final s = await db.supplierDao.create(SuppliersCompanion.insert(id: 'sup-1', companyId: site.companyId, name: 'Sri Balaji Traders'));
  final r = await db.purchaseDao.createRequest(PurchaseRequestsCompanion.insert(
      id: 'req-1', projectId: site.id, raisedBy: 'sup', materialName: 'Cement', quantity: Value(qty), unit: const Value('bags')));
  return db.purchaseDao.createOrder(PurchaseOrdersCompanion.insert(
      id: 'po-1', projectId: site.id, supplierId: s.id, requestId: Value(r.id), raisedBy: 'pm', poNumber: const Value('PO-7'),
      totalAmount: Value(qty * 400), status: const Value('issued')));
}

Future<MaterialReceipt> _receive(PurchaseOrder o, double qty, DateTime on, {bool close = true, String? slip}) =>
    db.purchaseDao.receiveAgainstOrder(
      o.id,
      closeOrder: close,
      slipPath: slip,
      MaterialReceiptsCompanion.insert(
        id: 'grn-${on.day}-$qty',
        projectId: site.id,
        supplierId: Value(o.supplierId),
        materialName: 'Cement',
        quantity: qty,
        unit: const Value('bags'),
        amount: qty * 400,
        receivedBy: 'sup',
        receivedOn: on,
      ),
    );

Future<WeekClose> _week() => loadWeekClose(db, site, _mon, now: _now);

CloseItem _item(WeekClose w, CloseKind kind, [String? id]) =>
    w.items.firstWhere((i) => i.kind == kind && (id == null || i.id == id));

void main() {
  late CloseActions manager;
  late CloseActions supervisor;

  setUp(() async {
    db = AppDatabase.memory();
    final c = await db.companyDao.create('Sai Constructions');
    site = await db.projectDao.create(ProjectsCompanion.insert(id: 'site-1', companyId: c.id, name: 'Kompally Villas'));
    manager = CloseActions(db, userId: 'pm', role: Roles.manager);
    supervisor = CloseActions(db, userId: 'sup', role: Roles.member);
  });
  tearDown(() => db.close());

  test('flags missing punch-outs, advances, workers without a wage, and bills without a photo', () async {
    final ramesh = await _worker('Ramesh', 800);
    final helper = await _worker('Helper', null);
    for (var d = 0; d < 6; d++) {
      await _day(ramesh, _mon.add(Duration(days: d, hours: 9)), hours: d == 2 ? null : 8);
    }
    await _day(helper, _mon.add(const Duration(hours: 9)));
    await _expense('2026-11-03', 6000, category: 'Labour', workerId: ramesh.id); // more than he earned
    await _expense('2026-11-04', 1200, category: 'Transport', paidTo: 'Tractor');

    final w = await _week();
    final r = _item(w, CloseKind.wages, ramesh.id);
    expect(r.flags.map((f) => f.flag), containsAll([CloseFlag.missingPunchOut, CloseFlag.advance]));
    // 5.5 days x 800 = 4400 earned, 6000 paid: 1600 advance.
    expect(r.flags.firstWhere((f) => f.flag == CloseFlag.advance).amount, closeTo(1600, 0.01));
    expect(w.advancesOut, closeTo(1600, 0.01));
    expect(_item(w, CloseKind.wages, helper.id).flags.single.flag, CloseFlag.noWageRate);

    // The wage payment needs no bill (the wage sheet backs it); the tractor does.
    final labour = w.items.firstWhere((i) => i.kind == CloseKind.expense && i.expense!.workerId != null);
    final tractor = w.items.firstWhere((i) => i.kind == CloseKind.expense && i.expense!.workerId == null);
    expect(labour.flags, isEmpty);
    expect(tractor.flags.single.flag, CloseFlag.noBill);
    expect(w.expensesTotal, 7200);
  });

  test('a working day with no attendance is flagged, and a report with people but no attendance says so', () async {
    final ramesh = await _worker('Ramesh', 800);
    await _day(ramesh, _mon.add(const Duration(hours: 9)));
    await db.dprDao.create(DprEntriesCompanion.insert(
        id: 'dpr-wed', projectId: site.id, createdBy: 'sup', entryDate: DateTime(2026, 11, 4, 18), workSummary: 'Slab shuttering',
        manpowerCount: const Value(12)));
    final w = await _week();
    final days = w.items.where((i) => i.kind == CloseKind.attendance).toList();
    // Tue to Fri have none (Monday had Ramesh). Saturday is today and still
    // being recorded; Sunday is not a working day.
    expect(days.map((d) => d.id), ['2026-11-03', '2026-11-04', '2026-11-05', '2026-11-06']);
    final wed = days.firstWhere((d) => d.id == '2026-11-04');
    expect(wed.flags.single.flag, CloseFlag.reportWithoutAttendance);
    expect(wed.flags.single.n, 12);
  });

  test('deliveries: no PO, no slip, and an order closed short are flagged', () async {
    final o = await _cementOrder(100);
    await _receive(o, 95, DateTime(2026, 11, 4, 11)); // closed: 5 bags never came
    await db.materialDao.createReceipt(MaterialReceiptsCompanion.insert(
        id: 'grn-loose', projectId: site.id, materialName: 'Sand', quantity: 2, unit: const Value('brass'), amount: 0,
        receivedBy: 'sup', receivedOn: DateTime(2026, 11, 5, 10)));
    final w = await _week();
    final cement = _item(w, CloseKind.receipt, 'grn-4-95.0');
    expect(cement.orderedQty, 100);
    final short = cement.flags.firstWhere((f) => f.flag == CloseFlag.shortDelivery);
    expect(short.qty, 5);
    expect(cement.flags.map((f) => f.flag), contains(CloseFlag.noSlip));
    expect(_item(w, CloseKind.receipt, 'grn-loose').flags.map((f) => f.flag),
        containsAll([CloseFlag.noPo, CloseFlag.noSlip, CloseFlag.noInvoiceAmount]));
  });

  test('a part delivery on an order still open is not called short; more than ordered is', () async {
    final o = await _cementOrder(100);
    await _receive(o, 60, DateTime(2026, 11, 3, 11), close: false);
    var w = await _week();
    expect(_item(w, CloseKind.receipt).flags.map((f) => f.flag), isNot(contains(CloseFlag.shortDelivery)));
    await _receive(o, 50, DateTime(2026, 11, 5, 11));
    w = await _week();
    final second = _item(w, CloseKind.receipt, 'grn-5-50.0');
    expect(second.flags.firstWhere((f) => f.flag == CloseFlag.overDelivery).qty, 10);
  });

  test('approve, edit after approval, send back, correct, mark fixed: each lands in the right state', () async {
    final e = await _expense('2026-11-04', 1200, category: 'Transport', paidTo: 'Tractor');
    var w = await _week();
    expect(_item(w, CloseKind.expense).state, ItemState.waiting);

    await manager.approve(w, _item(w, CloseKind.expense));
    w = await _week();
    expect(_item(w, CloseKind.expense).state, ItemState.approved);

    // Edited after approval: back to the queue.
    await db.expenseDao.edit(e.id, const SiteExpensesCompanion(amount: Value(1500)), by: 'sup');
    w = await _week();
    expect(_item(w, CloseKind.expense).state, ItemState.changed);
    expect(w.waiting, hasLength(1));

    await manager.sendBack(w, _item(w, CloseKind.expense), 'Bill says 1,200. Which is right?');
    w = await _week();
    expect(_item(w, CloseKind.expense).state, ItemState.sentBack);
    expect(_item(w, CloseKind.expense).last!.note, contains('Which is right'));

    // The supervisor corrects it: it comes back to review by itself.
    await db.expenseDao.edit(e.id, const SiteExpensesCompanion(amount: Value(1200)), by: 'sup');
    w = await _week();
    expect(_item(w, CloseKind.expense).state, ItemState.fixed);

    // Or says it is sorted without changing anything.
    await manager.sendBack(w, _item(w, CloseKind.expense), 'Attach the bill');
    w = await _week();
    await supervisor.markFixed(w, _item(w, CloseKind.expense), note: 'Bill given to office');
    w = await _week();
    expect(_item(w, CloseKind.expense).state, ItemState.fixed);
    expect(_item(w, CloseKind.expense).history.map((r) => r.decision), ['approved', 'sent_back', 'sent_back', 'fixed']);
  });

  test('only the owner or a project manager approves, sends back, closes or reopens', () async {
    await _expense('2026-11-04', 500);
    final w = await _week();
    final i = _item(w, CloseKind.expense);
    expect(() => supervisor.approve(w, i), throwsA(isA<CloseNotAllowed>()));
    expect(() => supervisor.sendBack(w, i, 'no'), throwsA(isA<CloseNotAllowed>()));
    expect(() => supervisor.closeWeek(w), throwsA(isA<CloseNotAllowed>()));
    expect(() => supervisor.reopen(w, 'why'), throwsA(isA<CloseNotAllowed>()));
    final viewer = CloseActions(db, userId: 'v', role: Roles.viewer);
    expect(() => viewer.markFixed(w, i), throwsA(isA<CloseNotAllowed>()));
    expect(() => manager.sendBack(w, i, '  '), throwsArgumentError);
    expect(await db.closeDao.forWeek(site.id, '2026-11-02'), isEmpty);
  });

  test('approve the clean ones in one go; flagged ones wait for a person', () async {
    final ramesh = await _worker('Ramesh', 800);
    for (var d = 0; d < 6; d++) {
      await _day(ramesh, _mon.add(Duration(days: d, hours: 9)));
    }
    final bill = await _expense('2026-11-03', 900, paidTo: 'Hardware shop');
    await db.expenseDao.attach(bill.id, '/tmp/bill.jpg');
    await _expense('2026-11-04', 300, category: 'Food & tea'); // no bill: flagged
    var w = await _week();
    expect(await manager.approveClean(w, now: _now), 2); // Ramesh's wages and the billed expense
    w = await _week();
    expect(w.waiting.single.flags.single.flag, CloseFlag.noBill);
    expect(w.canClose, isFalse);
  });

  test('close the week; a late change shows as changed since close; reopen keeps the record', () async {
    final e = await _expense('2026-11-04', 1200, paidTo: 'Tractor');
    var w = await _week();
    await manager.approve(w, _item(w, CloseKind.expense), note: 'No bill, tractor owner known');
    w = await _week();
    expect(w.canClose, isTrue);
    await manager.closeWeek(w);
    w = await _week();
    expect(w.isClosed, isTrue);
    expect(w.changedSinceClose, isFalse);
    expect(w.weekDecision!.amount, 1200);
    expect(() => manager.closeWeek(w), throwsStateError);

    await db.expenseDao.edit(e.id, const SiteExpensesCompanion(amount: Value(1800)), by: 'sup');
    w = await _week();
    expect(w.changedSinceClose, isTrue);

    await manager.reopen(w, 'Tractor bill changed');
    w = await _week();
    expect(w.isClosed, isFalse);
    expect(w.history.map((r) => r.decision), ['approved', 'closed', 'reopened']);
  });

  test('decisions sync as insert-only rows; delivery slips sync with their file', () async {
    final o = await _cementOrder(100);
    final slip = File('${Directory.systemTemp.path}/slip-test.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
    final r = await _receive(o, 95, DateTime(2026, 11, 4, 11), slip: slip.path);
    var w = await _week();
    final item = _item(w, CloseKind.receipt);
    expect(item.evidence, 1);
    expect(item.flags.map((f) => f.flag), isNot(contains(CloseFlag.noSlip)));
    await manager.approve(w, item, acceptedQty: 93);
    w = await _week();
    expect(_item(w, CloseKind.receipt).acceptedQty, 93);

    final outbox = await db.select(db.syncOutbox).get();
    final slipRow = outbox.singleWhere((e) => e.targetTable == 'site_receipt_attachments');
    final slipJson = jsonDecode(slipRow.payload) as Map<String, dynamic>;
    expect(slipJson['receipt_id'], r.id);
    expect(slipJson['file_path'], startsWith('${site.id}/receipt-slips/'));
    expect(slipJson['_local_file_path'], slip.path);
    // The slip is queued after its receipt, so the server has the parent first.
    expect(outbox.indexWhere((e) => e.targetTable == 'site_material_receipts'), lessThan(outbox.indexOf(slipRow)));

    final review = outbox.singleWhere((e) => e.targetTable == 'site_close_reviews');
    expect(review.operation, 'insert');
    final json = jsonDecode(review.payload) as Map<String, dynamic>;
    expect(json['week_start'], '2026-11-02');
    expect(json['item_kind'], 'receipt');
    expect(json['decision'], 'approved');
    expect(json['accepted_qty'], 93);
    expect(json['decided_by'], 'pm');
  });

  test('the pack for accounts is a PDF, and the CSV has a line per item', () async {
    final ramesh = await _worker('Ramesh', 800);
    await _day(ramesh, _mon.add(const Duration(hours: 9)));
    final o = await _cementOrder(100);
    await _receive(o, 95, DateTime(2026, 11, 4, 11));
    await _expense('2026-11-04', 1200, paidTo: 'Tractor, Bhaskar');
    var w = await _week();
    await manager.approve(w, _item(w, CloseKind.receipt), acceptedQty: 95);
    await manager.sendBack(w, _item(w, CloseKind.expense), 'Attach the bill');
    w = await _week();
    final bytes = await buildWeekClosePack(
        week: w, companyName: 'Sai Constructions', names: const {'pm': 'Anil (PM)'}, now: _now);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(packStatusLine(w), startsWith('Open:'));

    final csv = weekCloseCsv(w).trim().split('\n');
    expect(csv.first, startsWith('site,week_start,kind'));
    expect(csv.length, 1 + w.items.length);
    expect(csv.where((l) => l.contains('"Tractor, Bhaskar"') || l.contains('Attach the bill')), isNotEmpty);
  });

  test('another site or another week does not mix in', () async {
    final other = await db.projectDao.create(ProjectsCompanion.insert(id: 'site-2', companyId: site.companyId, name: 'Other'));
    await db.expenseDao.create(SiteExpensesCompanion.insert(
        id: 'e-other',
        projectId: other.id, category: 'Material', amount: 99, incurredOn: '2026-11-04', recordedBy: 'sup'));
    await _expense('2026-11-10', 50); // next week
    final w = await _week();
    expect(w.items, isEmpty);
    expect(w.canClose, isTrue); // an empty week can be closed, but the screen hides the button
  });
}
