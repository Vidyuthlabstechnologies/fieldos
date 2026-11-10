/// The CRM screens on a phone: an owner adds an enquiry, logs a call,
/// makes a quote and sees the total, in English and in Telugu, on a small
/// phone without overflow.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/crm/crm_screen.dart';
import 'package:fieldos_mobile/features/crm/quote_editor_screen.dart';
import 'package:fieldos_mobile/features/money/billing_calc.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));

  Future<(ProviderContainer, AppDatabase, String, String)> setUpCompany(WidgetTester tester) async {
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    late String companyId;
    late String me;
    await tester.runAsync(() async {
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'meena', name: 'Meena Rao', password: '123456');
      companyId = (await session.createCompany('Sri Sai Constructions')).id;
      me = container.read(sessionProvider).user!.id;
    });
    return (container, db, companyId, me);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }
  }

  Future<void> pumpApp(WidgetTester tester, ProviderContainer container, Widget home, {Size size = const Size(412, 915)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: home),
    ));
    await settle(tester);
  }

  testWidgets('empty, then a new lead, then a logged call', (tester) async {
    final (container, db, companyId, _) = await setUpCompany(tester);
    await pumpApp(tester, container, LeadsScreen(companyId: companyId));
    expect(find.text('No leads yet'), findsOneWidget);

    await tester.tap(find.text('New lead').first);
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Ramesh Reddy');
    await tester.enterText(find.widgetWithText(TextField, 'Phone'), '9849012345');
    await tester.enterText(find.widgetWithText(TextField, 'Work'), 'G+2 house');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await settle(tester);

    // Saving opens the lead.
    expect(find.text('Ramesh Reddy'), findsWidgets);
    expect(find.text('Log a call or visit'), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);

    await tester.tap(find.text('Log a call or visit'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'What was said or agreed'), 'Visit on Thursday');
    await tester.tap(find.text('In a week'));
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('Visit on Thursday'), findsOneWidget);
    expect(find.text('Contacted'), findsWidgets);

    final lead = (await tester.runAsync(() => db.crmDao.leadsFor(companyId)))!.single;
    expect(lead.stage, 'contacted');
    expect(lead.nextFollowUp, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the quote editor adds up items, discount and GST', (tester) async {
    final (container, db, companyId, me) = await setUpCompany(tester);
    final lead = (await tester.runAsync(() => db.crmDao.addLead(companyId: companyId, name: 'Ramesh Reddy', by: me)))!;
    await pumpApp(tester, container, QuoteEditorScreen(companyId: companyId, lead: lead));
    await tester.enterText(find.widgetWithText(TextField, 'Item 1'), 'Compound wall');
    await tester.enterText(find.widgetWithText(TextField, 'Qty'), '100');
    await tester.enterText(find.widgetWithText(TextField, 'Rate'), '1000');
    await tester.pumpAndSettle();
    // 100,000 + 9% + 9% GST
    expect(find.text('₹1,18,000'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await settle(tester);
    final q = (await tester.runAsync(() => db.crmDao.quotesForLead(lead.id)))!.single;
    expect(q.total, 118000);
    expect(decodeLines(q.linesJson).single.description, 'Compound wall');
    expect(find.text(q.quoteNumber), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a lead with quotes in Telugu on a small phone', (tester) async {
    final (container, db, companyId, me) = await setUpCompany(tester);
    await tester.runAsync(() async {
      final lead = await db.crmDao.addLead(
          companyId: companyId,
          name: 'Green Valley Residents Welfare Association',
          by: me,
          phone: '9849012345',
          workType: 'Clubhouse renovation and compound wall',
          location: 'Plot 12-14, Survey No. 221, Kompally',
          estimatedValue: 2500000,
          nextFollowUp: DateTime.now().subtract(const Duration(days: 3)));
      await db.crmDao.saveQuote(
          leadId: lead.id,
          lines: const [BillLine(description: 'Clubhouse renovation', unit: 'sq.ft', rate: 1450, qty: 3200)],
          by: me);
    });
    setCurrentLanguage(AppLanguage.te);
    await pumpApp(tester, container, LeadsScreen(companyId: companyId), size: const Size(320, 640));
    expect(find.text('లీడ్‌లు, కొటేషన్లు'), findsOneWidget);
    expect(find.textContaining('ఫాలో అప్ 3 రోజులు ఆలస్యం'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Green Valley Residents Welfare Association'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Green Valley Residents Welfare Association'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('గెలిచాం'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('కొటేషన్లు'), findsOneWidget);
    expect(find.text('గెలిచాం'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
