import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/company/branding.dart';
import 'package:fieldos_mobile/features/money/voucher_pdf.dart';
import 'package:fieldos_mobile/features/procurement/purchase_tools.dart';
import 'package:fieldos_mobile/features/procurement/site_stock.dart' show openingStockNote;
import 'package:fieldos_mobile/features/procurement/supplier_statement.dart';
import 'package:fieldos_mobile/sync/sync_mappers.dart';

/// Party balances and the company's own PDFs, from Onsite's Play reviews:
/// "opening balance of party", "advance to supplier", "send ledger to
/// party", "our logo on the bill", "remove the app name from the PDF".
Supplier _s({double? opening}) => Supplier(
    id: 's1', companyId: 'c', name: 'Sri Balaji Hardware', createdAt: DateTime(2026, 10), openingBalance: opening);

MaterialReceipt _grn(String id, DateTime on, double amount, {String? supplierId = 's1', String? poId, String? notes, String project = 'p1'}) =>
    MaterialReceipt(
        id: id, projectId: project, poId: poId, supplierId: supplierId, materialName: 'Cement', quantity: 50,
        unit: 'bags', amount: amount, receivedBy: 'u', receivedOn: on, createdAt: on, notes: notes);

SiteExpense _paid(String id, String day, double amount, {String paidTo = 'Sri Balaji Hardware', bool voided = false, int? voucher}) =>
    SiteExpense(
        id: id, projectId: 'p1', category: 'Material', amount: amount, incurredOn: day, recordedBy: 'u', paidTo: paidTo,
        gstInterState: false, voided: voided, voucherNo: voucher, createdAt: DateTime(2026, 11, 1));

void main() {
  group('supplier balance', () {
    final receipts = [
      _grn('g1', DateTime(2026, 11, 2), 19000),
      _grn('g2', DateTime(2026, 11, 6), 9500, supplierId: null, poId: 'po1'), // through a PO
      _grn('g3', DateTime(2026, 11, 1), 0, notes: openingStockNote), // opening stock: not a delivery
      _grn('other', DateTime(2026, 11, 3), 7000, supplierId: 's2'),
    ];
    final orders = [
      PurchaseOrder(
          id: 'po1', projectId: 'p1', supplierId: 's1', status: 'delivered', totalAmount: 9500,
          raisedBy: 'u', createdAt: DateTime(2026, 11, 4)),
    ];
    final expenses = [
      _paid('x1', '2026-11-03', 15000, voucher: 4),
      _paid('x2', '2026-11-07', 5000, paidTo: '  sri balaji   HARDWARE '),
      _paid('x3', '2026-11-07', 999, voided: true),
      _paid('x4', '2026-11-07', 800, paidTo: 'Someone else'),
    ];

    test('opening + delivered − paid; cancelled payments and other parties left out', () {
      final l = supplierLedgers(orders, receipts, DateTime(2026, 11, 9), suppliers: [_s(opening: 2000)], expenses: expenses)['s1']!;
      expect(l.opening, 2000);
      expect(l.received, 28500);
      expect(l.paid, 20000);
      expect(l.balance, 10500);
    });

    test('a supplier with only an opening advance still has a ledger, negative', () {
      final l = supplierLedgers(const [], const [], DateTime(2026, 11, 9), suppliers: [_s(opening: -5000)])['s1']!;
      expect(l.balance, -5000);
      expect(supplierLedgers(const [], const [], DateTime(2026, 11, 9), suppliers: [_s()]), isEmpty);
    });

    test('the statement runs in date order with the balance after each line', () {
      final lines = supplierStatement(
          supplier: _s(opening: 2000), receipts: receipts, orders: orders, expenses: expenses, siteName: {'p1': 'Tower B'});
      expect(lines.map((l) => (l.kind, l.amount, l.balance)), [
        (StatementKind.opening, 2000.0, 2000.0),
        (StatementKind.delivery, 19000.0, 21000.0),
        (StatementKind.payment, -15000.0, 6000.0),
        (StatementKind.delivery, 9500.0, 15500.0),
        (StatementKind.payment, -5000.0, 10500.0),
      ]);
      expect(lines[2].reference, 'V-4');
      expect(lines[1].site, 'Tower B');
      expect(lines[1].label, 'Cement 50 bags');

      final text = statementText(_s(opening: 2000), lines, companyName: 'Sri Sai Constructions');
      expect(text, startsWith('Statement: Sri Balaji Hardware\nFrom Sri Sai Constructions'));
      expect(text, contains('(V-4): -₹15,000 = ₹6,000'));
      expect(text, endsWith('Balance due to you: ₹10,500'));
    });

    test('opening balance is saved, synced only when set, and kept when an older cloud leaves it out', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final s = await db.supplierDao.create(SuppliersCompanion.insert(id: 's1', companyId: 'c', name: 'Balaji'));
      expect(supplierToSupabaseJson(s).containsKey('opening_balance'), isFalse);
      final edited = await db.supplierDao.edit('s1', const SuppliersCompanion(openingBalance: Value(-2500), companyId: Value('x')));
      expect(edited.openingBalance, -2500);
      expect(edited.companyId, 'c');
      final queued = await db.syncOutboxDao.pending();
      expect(queued.map((o) => o.operation), ['insert', 'update']);
      expect((jsonDecode(queued.last.payload) as Map)['opening_balance'], -2500);

      await db.supplierDao.upsertFromRemote(supplierFromSupabaseJson({'id': 's1', 'company_id': 'c', 'name': 'Balaji & Sons'}));
      final row = (await db.supplierDao.forCompany('c')).single;
      expect(row.name, 'Balaji & Sons');
      expect(row.openingBalance, -2500);
    });
  });

  group('company logo and footer', () {
    Uint8List picture(int w, int h) => Uint8List.fromList(img.encodeJpg(img.Image(width: w, height: h)));

    test('a big photo is shrunk to a small PNG; a non-picture is refused', () {
      final png = shrinkLogo(picture(1600, 800))!;
      final back = img.decodePng(png)!;
      expect(back.width, logoMaxSide);
      expect(back.height, logoMaxSide ~/ 2);
      expect(img.decodePng(shrinkLogo(picture(100, 300))!)!.height, 300); // small ones stay as they are
      expect(shrinkLogo(Uint8List.fromList(utf8.encode('not an image'))), isNull);
    });

    test('saved per company, removable, and the footer can be switched off', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      expect((await loadBranding(db, 'c')).logo, isNull);
      expect((await loadBranding(db, 'c')).showFooter, isTrue);
      expect(await saveLogo(db, 'c', picture(800, 400)), isTrue);
      expect(await saveLogo(db, 'c', Uint8List.fromList([1, 2, 3])), isFalse);
      expect((await loadBranding(db, 'c')).logo, isNotNull);
      expect((await loadBranding(db, 'other')).logo, isNull);
      await setShowFooter(db, 'c', false);
      expect((await loadBranding(db, 'c')).showFooter, isFalse);
      await removeLogo(db, 'c');
      expect((await loadBranding(db, 'c')).logo, isNull);
      expect((await loadBranding(db, null)).showFooter, isTrue);
    });

    test('the voucher PDF carries the logo, and drops the FieldOS line when asked', () async {
      final e = _paid('v', '2026-11-08', 1180, voucher: 9);
      final plain = await buildVoucherPdf(expense: e, companyName: 'Sri Sai', siteName: 'Tower B');
      final logo = shrinkLogo(picture(300, 120))!;
      final branded = await buildVoucherPdf(
          expense: e, companyName: 'Sri Sai', siteName: 'Tower B', branding: PdfBranding(logo: logo, showFooter: false));
      expect(String.fromCharCodes(branded.take(5)), '%PDF-');
      // The logo is embedded as an image object.
      expect(latin1.decode(branded, allowInvalid: true), matches(RegExp(r'/Subtype\s*/Image')));
      expect(latin1.decode(plain, allowInvalid: true), isNot(matches(RegExp(r'/Subtype\s*/Image'))));
    });
  });
}
