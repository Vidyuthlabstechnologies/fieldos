/// Tax invoice numbers are one series per company (one GSTIN), not per
/// site: rule 46(b) of the CGST Rules wants each number used once.
library;

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/money/billing_calc.dart';
import 'package:fieldos_mobile/features/money/bills_view.dart';
import 'package:fieldos_mobile/providers.dart';

const _lines = [BillLine(description: 'Brick work', unit: 'cum', rate: 5200, qty: 2)];

ClientBillsCompanion _invoice(String id, String projectId, String number) => ClientBillsCompanion.insert(
      id: id,
      projectId: projectId,
      kind: 'tax_invoice',
      billNumber: number,
      billDate: DateTime(2026, 11, 6),
      clientName: 'Owner',
      linesJson: encodeLines(_lines),
      gross: 10400,
      netPayable: 10400,
      recordedBy: 'u',
    );

void main() {
  test('the company series takes in every site, and only tax invoices', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await db.projectDao.create(ProjectsCompanion.insert(id: 'p1', companyId: 'c', name: 'Kondapur'));
    await db.projectDao.create(ProjectsCompanion.insert(id: 'p2', companyId: 'c', name: 'Gachibowli'));
    await db.projectDao.create(ProjectsCompanion.insert(id: 'p3', companyId: 'other', name: 'Elsewhere'));
    await db.billDao.create(_invoice('b1', 'p1', 'INV-0001'));
    await db.billDao.create(_invoice('b2', 'p2', 'INV-0002'));
    await db.billDao.create(_invoice('b3', 'p3', 'INV-0009'));
    await db.billDao.create(_invoice('b4', 'p1', 'RA-01').copyWith(kind: const Value('ra')));
    expect((await db.billDao.invoiceNumbersForCompany('c'))..sort(), ['INV-0001', 'INV-0002']);
  });

  testWidgets('a second site does not issue the first site\'s invoice number again', (tester) async {
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    late Project second;
    late String userId;
    await tester.runAsync(() async {
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'ravi', name: 'Ravi Kumar', password: '123456');
      final companyId = (await session.createCompany('Sai Builders')).id;
      userId = container.read(sessionProvider).user!.id;
      await db.projectDao.create(ProjectsCompanion.insert(id: 'p1', companyId: companyId, name: 'Kondapur'));
      await db.projectDao.create(ProjectsCompanion.insert(id: 'p2', companyId: companyId, name: 'Gachibowli'));
      await db.billDao.create(_invoice('b1', 'p1', 'INV-0001'));
      second = (await db.projectDao.byId('p2'))!;
    });
    tester.view.physicalSize = const Size(412, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildFieldOsTheme(Brightness.light),
        home: NewBillScreen(project: second, userId: userId, initialLines: _lines),
      ),
    ));
    Future<void> settle() async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
      }
    }

    await settle();
    await tester.tap(find.text('Tax invoice'));
    await settle();
    expect(find.widgetWithText(TextField, 'INV-0002'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'INV-0001'), findsNothing);
  });
}
