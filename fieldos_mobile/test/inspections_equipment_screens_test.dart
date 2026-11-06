/// The inspection checklist and equipment log dialogs: they show a change
/// the moment it is made (both used to show the list as it was when the
/// dialog opened), and they speak in words, not stored codes or file paths.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/equipment/equipment_screen.dart';
import 'package:fieldos_mobile/features/inspections/inspections_screen.dart';
import 'package:fieldos_mobile/providers.dart';

void main() {
  Future<(ProviderContainer, AppDatabase)> setUpDb(WidgetTester tester) async {
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return (container, db);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pumpAndSettle();
    }
  }

  Future<void> pumpView(WidgetTester tester, ProviderContainer container, Widget view) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: Scaffold(body: view)),
    ));
    await settle(tester);
  }

  test('a checklist photo path is split from the note, never shown', () {
    expect(splitInspectionNotes(null), (photoPath: null, text: null));
    expect(splitInspectionNotes('Photo: /a/b.jpg'), (photoPath: '/a/b.jpg', text: null));
    expect(splitInspectionNotes('Photo: /a/b.jpg\nLoose clamp, fixed'), (photoPath: '/a/b.jpg', text: 'Loose clamp, fixed'));
    expect(splitInspectionNotes('Checked twice'), (photoPath: null, text: 'Checked twice'));
  });

  testWidgets('a checklist status picked in the dialog shows at once, and is sent to the team', (tester) async {
    final (container, db) = await setUpDb(tester);
    await tester.runAsync(() async {
      await db.inspectionDao.create(InspectionsCompanion.insert(
        id: 'i1',
        projectId: 'p1',
        title: 'Scaffold check',
        inspectionType: 'mep',
      ));
      await db.inspectionDao.addItem(InspectionItemsCompanion.insert(
        id: 'it1',
        inspectionId: 'i1',
        itemDescription: 'Guard rails fixed',
      ));
      await db.inspectionDao.addItem(InspectionItemsCompanion.insert(
        id: 'it2',
        inspectionId: 'i1',
        itemDescription: 'Toe boards in place',
        notes: const Value('Photo: /not/on/this/phone.jpg'),
      ));
    });
    await pumpView(tester, container, const InspectionsView(projectId: 'p1', userId: 'u1'));
    expect(find.text('MEP'), findsOneWidget);

    await tester.tap(find.text('Scaffold check'));
    await settle(tester);
    expect(find.text('Not checked'), findsNWidgets(2));
    expect(find.text('Photo is on the phone that took it'), findsOneWidget);
    expect(find.textContaining('/not/on'), findsNothing);
    expect(find.text('pending'), findsNothing);

    await tester.tap(find.text('Not checked').first);
    await settle(tester);
    await tester.tap(find.text('Pass').last);
    await settle(tester);
    expect(find.text('Pass'), findsOneWidget, reason: 'the new status shows without reopening the checklist');
    expect(find.text('Not checked'), findsOneWidget);

    late List<InspectionItem> items;
    late List<SyncOutboxData> outbox;
    await tester.runAsync(() async {
      items = await db.inspectionDao.itemsFor('i1');
      outbox = await db.syncOutboxDao.pending();
    });
    expect(items.first.status, 'pass');
    expect(
      outbox.where((o) => o.targetTable == 'inspection_items').map((o) => o.operation),
      ['insert', 'insert', 'update'],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a log added from the logs dialog appears in it, and silly hours are caught', (tester) async {
    final (container, db) = await setUpDb(tester);
    await tester.runAsync(() async {
      await db.equipmentDao.create(EquipmentCompanion.insert(id: 'e1', projectId: 'p1', name: 'Tower Crane'));
    });
    await pumpView(tester, container, const EquipmentView(projectId: 'p1', userId: 'u1'));

    await tester.tap(find.text('Tower Crane'));
    await settle(tester);
    expect(find.textContaining('No logs yet'), findsOneWidget);

    await tester.tap(find.text('Add log'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Hours (optional)'), '12000');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('Enter hours as a number below 10,000'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Hours (optional)'), '7.5');
    await tester.enterText(find.widgetWithText(TextField, 'Cost (optional)'), '1,500');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.textContaining('No logs yet'), findsNothing);
    expect(find.textContaining('Worked'), findsOneWidget);
    expect(find.text('7.5 h · ₹1,500'), findsOneWidget);

    late List<SyncOutboxData> outbox;
    await tester.runAsync(() async => outbox = await db.syncOutboxDao.pending());
    expect(outbox.map((o) => o.targetTable), ['equipment', 'equipment_logs']);
    expect(tester.takeException(), isNull);
  });
}
