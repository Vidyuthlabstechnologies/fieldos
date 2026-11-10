/// Supplier quotes for a purchase request: compared on the landed cost at
/// site, the cheapest marked, and the order given from the chosen quote.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/procurement/quote_compare.dart';

const _uuid = Uuid();

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  final now = DateTime(2026, 11, 10, 9);

  Future<PurchaseRequest> request({double qty = 100, double? estimate}) =>
      db.purchaseDao.createRequest(PurchaseRequestsCompanion.insert(
          id: _uuid.v4(),
          projectId: 'p',
          raisedBy: 'u',
          materialName: 'Cement OPC 53',
          unit: const Value('bag'),
          quantity: Value(qty),
          estimatedAmount: Value(estimate)));

  test('landed cost adds GST and transport; cheapest landed wins, not cheapest rate', () async {
    final r = await request(estimate: 45000);
    // A: lower rate but heavy transport. B: higher rate, free delivery.
    final a = await db.supplierQuoteDao.addQuote(
        requestId: r.id, supplierId: 'A', rate: 360, transport: 3000, deliveryDays: 2, by: 'u');
    final b = await db.supplierQuoteDao.addQuote(requestId: r.id, supplierId: 'B', rate: 370, deliveryDays: 5, by: 'u');
    final c = compareQuotes(r, await db.supplierQuoteDao.forRequest(r.id), now);

    final la = c.lines.firstWhere((l) => l.quote.id == a.id);
    expect(la.material, 36000);
    expect(la.gst, closeTo(6480, 0.001));
    expect(la.landed, closeTo(45480, 0.001));
    expect(c.best!.quote.id, b.id, reason: '370 x 100 + 18% = 43,660 beats 45,480');
    expect(c.best!.perUnit, closeTo(436.6, 0.001));
    expect(c.savingVsNext(now), closeTo(1820, 0.001));
    expect(c.savingVsEstimate(), closeTo(1340, 0.001));
    expect(c.fastestDays(now), 2, reason: 'the cheapest is slower than another quote');
  });

  test('expired and turned-down quotes sort after valid ones and never count as best', () async {
    final r = await request();
    final old = await db.supplierQuoteDao.addQuote(
        requestId: r.id, supplierId: 'A', rate: 300, validUntil: DateTime(2026, 11, 9), by: 'u');
    final no = await db.supplierQuoteDao.addQuote(requestId: r.id, supplierId: 'B', rate: 310, by: 'u');
    await db.supplierQuoteDao.reject(no.id);
    final ok = await db.supplierQuoteDao.addQuote(requestId: r.id, supplierId: 'C', rate: 400, by: 'u');

    final c = compareQuotes(r, await db.supplierQuoteDao.forRequest(r.id), now);
    expect([for (final l in c.lines) l.quote.id], [ok.id, old.id, no.id]);
    expect(c.best!.quote.id, ok.id);
    expect(c.lines[1].expired(now), isTrue);
    expect(c.savingVsNext(now), isNull, reason: 'only one valid quote');

    // Valid until today is still valid.
    final today = await db.supplierQuoteDao.addQuote(
        requestId: r.id, supplierId: 'D', rate: 390, validUntil: DateTime(2026, 11, 10), by: 'u');
    expect(QuoteLine(today, 1).expired(now), isFalse);
  });

  test('only turned-down quotes leave no best', () async {
    final r = await request();
    final q = await db.supplierQuoteDao.addQuote(requestId: r.id, supplierId: 'A', rate: 300, by: 'u');
    await db.supplierQuoteDao.reject(q.id);
    expect(compareQuotes(r, await db.supplierQuoteDao.forRequest(r.id), now).best, isNull);
  });

  test('a second price from the same supplier replaces their first', () async {
    final r = await request();
    final first = await db.supplierQuoteDao.addQuote(requestId: r.id, supplierId: 'A', rate: 380, by: 'u');
    final second = await db.supplierQuoteDao.addQuote(requestId: r.id, supplierId: 'A', rate: 365, gstPct: 28, by: 'u');
    expect(second.id, first.id);
    final all = await db.supplierQuoteDao.forRequest(r.id);
    expect(all, hasLength(1));
    expect(all.single.rate, 365);
    expect(all.single.gstPct, 28);
    final ops = [for (final o in await db.syncOutboxDao.pending()) if (o.targetTable == 'site_supplier_quotes') o.operation];
    expect(ops, ['insert', 'update']);
  });

  test('bad figures are refused', () async {
    final r = await request();
    Future<void> add({double rate = 100, double gst = 18, double transport = 0, int? days}) => db.supplierQuoteDao
        .addQuote(requestId: r.id, supplierId: 'A', rate: rate, gstPct: gst, transport: transport, deliveryDays: days, by: 'u');
    await expectLater(add(rate: 0), throwsArgumentError);
    await expectLater(add(gst: 40), throwsArgumentError);
    await expectLater(add(transport: -1), throwsArgumentError);
    await expectLater(add(days: -2), throwsArgumentError);
    await expectLater(
        db.supplierQuoteDao.addQuote(requestId: 'missing', supplierId: 'A', rate: 1, by: 'u'), throwsArgumentError);
    expect(await db.supplierQuoteDao.forRequest(r.id), isEmpty);
  });

  test('giving the order makes one PO at the landed total and closes the other quotes', () async {
    final r = await request();
    final a = await db.supplierQuoteDao.addQuote(
        requestId: r.id, supplierId: 'A', rate: 362.5, transport: 1500, deliveryDays: 3, paymentTerms: '30 days credit', by: 'u');
    final b = await db.supplierQuoteDao.addQuote(requestId: r.id, supplierId: 'B', rate: 380, by: 'u');

    final po = await db.supplierQuoteDao.award(a.id, by: 'pm');
    expect(po.requestId, r.id);
    expect(po.supplierId, 'A');
    expect(po.totalAmount, closeTo(36250 * 1.18 + 1500, 0.001));
    expect(po.notes, contains('GST 18%'));
    expect(po.notes, contains('30 days credit'));
    expect(po.deliveryDate, isNotNull);
    expect((await db.purchaseDao.requestsFor('p')).single.status, 'ordered');

    final quotes = {for (final q in await db.supplierQuoteDao.forRequest(r.id)) q.supplierId: q};
    expect(quotes['A']!.status, 'accepted');
    expect(quotes['A']!.poId, po.id);
    expect(quotes['B']!.status, 'rejected');

    // A second tap gives the same order back; the turned-down one can't be ordered.
    expect((await db.supplierQuoteDao.award(a.id, by: 'pm')).id, po.id);
    expect(await db.purchaseDao.ordersFor('p'), hasLength(1));
    await expectLater(db.supplierQuoteDao.award(b.id, by: 'pm'), throwsArgumentError);

    // Once ordered, no more quotes come in for the request.
    await expectLater(
        db.supplierQuoteDao.addQuote(requestId: r.id, supplierId: 'C', rate: 300, by: 'u'), throwsArgumentError);
  });

  test('the WhatsApp ask names the material, quantity, site and what to quote', () async {
    final r = await request(qty: 250);
    final msg = rfqMessage(
        request: r,
        siteName: 'Narsingi Villas',
        companyName: 'Sri Sai Builders',
        siteLocation: 'https://maps.google.com/?q=17.39,78.35',
        needBy: DateTime(2026, 11, 14));
    expect(msg, contains('Sri Sai Builders'));
    expect(msg, contains('Cement OPC 53: 250 bag'));
    expect(msg, contains('Delivery to: Narsingi Villas, https://maps.google.com/?q=17.39,78.35'));
    expect(msg, contains('Needed by:'));
    expect(msg, contains('GST, transport, delivery days and payment terms'));
  });
}
