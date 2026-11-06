/// The daily report filling itself from the site's records, and a
/// purchase order as a message for the supplier.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/procurement/po_share.dart';
import 'package:fieldos_mobile/features/project/site_day.dart';

LabourAttendanceData punch(String name, DateTime at, {String? workerId}) => LabourAttendanceData(
      id: '$name$at',
      projectId: 'p',
      workerName: name,
      workerId: workerId,
      recordedBy: 'u',
      punchIn: at,
      createdAt: at,
    );

MaterialReceipt receipt(String name, double qty, String? unit, DateTime on) => MaterialReceipt(
      id: '$name$on$qty',
      projectId: 'p',
      materialName: name,
      quantity: qty,
      unit: unit,
      amount: 0,
      receivedBy: 'u',
      receivedOn: on,
      createdAt: on,
    );

DprEntry report(String id, DateTime on) => DprEntry(
      id: id,
      projectId: 'p',
      createdBy: 'u',
      entryDate: on,
      workSummary: 'Summary $id',
      manpowerCount: 0,
      status: 'confirmed',
      source: 'manual',
      createdAt: on,
    );

void main() {
  final day = DateTime(2026, 11, 10);

  test('workers on a day count each person once', () {
    final punches = [
      punch('Ramesh', DateTime(2026, 11, 10, 9)),
      punch('ramesh ', DateTime(2026, 11, 10, 14)),
      punch('Suresh', DateTime(2026, 11, 10, 9), workerId: 'w2'),
      punch('Suresh K', DateTime(2026, 11, 10, 15), workerId: 'w2'),
      punch('Mahesh', DateTime(2026, 11, 9, 9)),
    ];
    expect(workersOnDay(punches, day), 2);
  });

  test('material received on a day adds up by material and unit', () {
    final receipts = [
      receipt('Cement', 20, 'bags', DateTime(2026, 11, 10, 8)),
      receipt('Sand', 2, 'brass', DateTime(2026, 11, 10, 9)),
      receipt('cement', 20, 'bags', DateTime(2026, 11, 10, 11)),
      receipt('Cement', 1, 't', DateTime(2026, 11, 10, 12)),
      receipt('Steel', 3, 't', DateTime(2026, 11, 9, 12)),
    ];
    final items = materialsOnDay(receipts, day);
    expect(items, ['Cement 40 bags', 'Sand 2 brass', 'Cement 1 t']);
    expect(materialsLine(items), 'Material received: Cement 40 bags, Sand 2 brass, Cement 1 t.');
    expect(materialsLine(const []), '');
  });

  test('the last report is the newest one before the day', () {
    final reports = [
      report('old', DateTime(2026, 11, 1)),
      report('yesterday', DateTime(2026, 11, 9, 18)),
      report('today', DateTime(2026, 11, 10, 9)),
    ];
    expect(lastReportBefore(reports, DateTime(2026, 11, 10, 17))?.id, 'yesterday');
    expect(lastReportBefore(const [], day), isNull);
  });

  test('a purchase order reads as a message for the supplier', () {
    final order = PurchaseOrder(
      id: 'o',
      projectId: 'p',
      supplierId: 's',
      requestId: 'r',
      raisedBy: 'u',
      poNumber: 'PO-0012',
      totalAmount: 38500,
      deliveryDate: DateTime(2026, 11, 12),
      status: 'issued',
      notes: 'Unload at gate 2',
      createdAt: DateTime(2026, 11, 10),
    );
    final request = PurchaseRequest(
      id: 'r',
      projectId: 'p',
      raisedBy: 'u',
      materialName: 'Cement OPC 53',
      quantity: 100,
      unit: 'bags',
      urgency: 'normal',
      status: 'approved',
      createdAt: DateTime(2026, 11, 9),
    );
    final text = poShareText(
      order: order,
      companyName: 'Sai Builders',
      projectName: 'Kondapur villa',
      supplierName: 'Sri Balaji Traders',
      request: request,
    );
    expect(text, contains('Purchase order PO-0012'));
    expect(text, contains('To: Sri Balaji Traders'));
    expect(text, contains('Site: Kondapur villa'));
    expect(text, contains('Material: Cement OPC 53 100 bags'));
    expect(text, contains('Amount: ₹38,500'));
    expect(text, contains('Notes: Unload at gate 2'));

    final bare = poShareText(order: order, companyName: '');
    expect(bare, isNot(contains('To:')));
    expect(bare, isNot(contains('From:')));
  });
}
