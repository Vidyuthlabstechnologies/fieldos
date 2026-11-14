/// Pins and markup on drawings: placed on the approved revision at page
/// fractions, linked to the defect or RFI raised there, removed only by
/// whoever placed them or a manager, queued for the cloud; and the viewer
/// on a small phone in Hindi places a defect pin, saves a markup and
/// removes a pin.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/execution/drawing_sheet_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';
import 'package:fieldos_mobile/sync/site_execution_sync.dart';

/// A small grey PNG, so Image.file has something real to decode.
Uint8List _png() => img.encodePng(img.Image(width: 8, height: 6));

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));

  Future<(DrawingRevision, AppDatabase)> drawingIn(AppDatabase db, String projectId, String by, String path) async {
    final x = db.siteExecutionDao;
    final dr = await x.addDrawing(projectId: projectId, number: 'A-101', title: 'Ground floor plan', discipline: 'architectural', by: by);
    final rev = await x.addRevision(drawingId: dr.id, rev: 'R1', filePath: path, by: by);
    return (rev, db);
  }

  test('a pin is kept in page fractions, linked, queued, and removed only by its owner or a manager', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final (rev, _) = await drawingIn(db, 'p1', 'u1', '/nowhere/a101.png');
    final x = db.siteExecutionDao;
    final defect = await x.raiseDefect(projectId: 'p1', description: 'Door frame out of plumb', by: 'u1');
    final pin = await x.addPin(
        projectId: 'p1', revisionId: rev.id, kind: 'defect', label: ' Door frame out of plumb ', x: 1.4, y: 0.25, by: 'u1', linkId: defect.id);
    expect(pin.drawingId, rev.drawingId);
    expect(pin.x, 1.0, reason: 'kept on the page');
    expect(pin.label, 'Door frame out of plumb');
    await expectLater(x.addPin(projectId: 'p1', revisionId: rev.id, kind: 'note', label: '  ', x: 0.5, y: 0.5, by: 'u1'),
        throwsA(isA<ExecutionRefused>()));
    await expectLater(x.addPin(projectId: 'other', revisionId: rev.id, kind: 'note', label: 'x', x: 0.5, y: 0.5, by: 'u1'),
        throwsA(isA<ExecutionRefused>()));

    await expectLater(x.removePin(pin.id, by: 'u2', manager: false), throwsA(isA<ExecutionRefused>()));
    final removed = await x.removePin(pin.id, by: 'u2', manager: true);
    expect(removed.removedBy, 'u2');
    expect(removed.removedAt, isNotNull);

    final queued = [for (final e in await db.select(db.syncOutbox).get()) if (e.targetTable == 'site_drawing_pins') e.operation];
    expect(queued, ['insert', 'update']);
    expect(siteExecutionProjectScoped, contains('site_drawing_pins'));
    expect(siteExecutionUserColumns, contains('removed_by'));
    final remote = executionToRemote('site_drawing_pins', removed);
    expect(remote.keys, containsAll(['drawing_id', 'revision_id', 'link_id', 'removed_at', 'removed_by', 'created_by', 'page']));
    expect(executionFromRemote('site_drawing_pins', {...remote, 'synced_at': 'x'}), isNotNull);
  });

  test('markup strokes survive a round trip and bad JSON is skipped', () {
    expect(decodeStrokes('[[0.1,0.2,0.3,0.4],[0.5,0.5]]'), [
      [const Offset(0.1, 0.2), const Offset(0.3, 0.4)],
      [const Offset(0.5, 0.5)],
    ]);
    expect(decodeStrokes('not json'), isEmpty);
    expect(decodeStrokes('{"a":1}'), isEmpty);
    expect(decodeStrokes(null), isEmpty);
  });

  testWidgets('the viewer places a defect pin, saves a markup and removes a pin (Hindi, small phone)', (tester) async {
    final db = AppDatabase.memory();
    final dir = Directory.systemTemp.createTempSync('pins');
    final image = File('${dir.path}/a101.png')..writeAsBytesSync(_png());
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      cloudSyncClientProvider.overrideWith((ref) {
        final c = SupabaseClient('http://localhost:1', 'anon',
            authOptions: const AuthClientOptions(autoRefreshToken: false, authFlowType: AuthFlowType.implicit));
        ref.onDispose(c.dispose);
        return c;
      }),
      sheetPageLoaderProvider.overrideWithValue((r, page) async => SheetPage(image, const Size(800, 600), 1)),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
      dir.deleteSync(recursive: true);
    });
    late Project site;
    late DrawingRevision rev;
    await tester.runAsync(() async {
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'ravi', name: 'Ravi Kumar', password: '123456');
      await session.createCompany('Sri Sai Constructions');
      final me = container.read(sessionProvider).user!.id;
      site = await db.projectDao.create(ProjectsCompanion.insert(
          id: const Uuid().v4(), companyId: container.read(sessionProvider).activeCompany!.id, name: 'Kompally Villas',
          status: const Value('active')));
      (rev, _) = await drawingIn(db, site.id, me, image.path);
      await db.siteExecutionDao.decideRevision(rev.id, approve: true, by: me);
      await container.read(appDatabaseProvider).settingsDao.set(languageSettingKey, AppLanguage.hi.code);
      await container.read(appDatabaseProvider).settingsDao.set(screensInLanguageKey, '1');
    });
    setCurrentLanguage(AppLanguage.hi);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildFieldOsTheme(Brightness.light),
        locale: AppLanguage.hi.locale,
        supportedLocales: [for (final l in AppLanguage.offered) l.locale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: DrawingSheetScreen(project: site, drawingId: rev.drawingId),
      ),
    ));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('A-101 R1'), findsOneWidget);

    // Pin mode, tap the middle of the drawing, raise a defect.
    await tester.tap(find.byKey(const Key('sheet-mode-pin')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('sheet-canvas')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('pin-kind-defect')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('pin-defect-text')), 'Skirting tile cracked');
    await tester.tap(find.byKey(const Key('pin-defect-save')));
    await settle(tester);
    expect(tester.takeException(), isNull);
    var pins = (await tester.runAsync(() => db.siteExecutionDao.pinsFor(site.id)))!;
    expect(pins.single.kind, 'defect');
    expect(pins.single.x, closeTo(0.5, 0.05));
    final defects = (await tester.runAsync(() => db.siteExecutionDao.defectsFor(site.id)))!;
    expect(defects.single.id, pins.single.linkId);
    expect(find.byKey(Key('pin-${pins.single.id}')), findsOneWidget);

    // Let the "raised" message go so the toolbar is reachable.
    await tester.pump(const Duration(seconds: 6));
    await settle(tester);

    // Draw a line and save it as a markup.
    await tester.tap(find.byKey(const Key('sheet-mode-draw')));
    await settle(tester);
    final canvas = tester.getRect(find.byKey(const Key('sheet-canvas')));
    await tester.dragFrom(canvas.topLeft + const Offset(20, 20), const Offset(80, 40));
    await settle(tester);
    await tester.tap(find.byKey(const Key('sheet-save-markup')));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'Move this wall 100 mm');
    await tester.tap(find.text(tr('Save')).last);
    await settle(tester);
    pins = (await tester.runAsync(() => db.siteExecutionDao.pinsFor(site.id)))!;
    final markup = pins.firstWhere((p) => p.kind == 'markup');
    expect(decodeStrokes(markup.strokes).single.length, greaterThan(1));
    expect(markup.label, 'Move this wall 100 mm');

    // Open the defect pin and remove it.
    await tester.tap(find.byKey(const Key('sheet-mode-pin')).first);
    await settle(tester);
    final defectPin = pins.firstWhere((p) => p.kind == 'defect');
    // Back to look mode so the tap reaches the pin, not the canvas.
    await tester.tap(find.text(tr('Look')));
    await settle(tester);
    await tester.tap(find.byKey(Key('pin-${defectPin.id}')));
    await settle(tester);
    expect(find.text('Skirting tile cracked'), findsWidgets);
    await tester.tap(find.byKey(const Key('pin-remove')));
    await settle(tester);
    expect(find.byKey(Key('pin-${defectPin.id}')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
  await tester.pumpAndSettle();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
  await tester.pumpAndSettle();
}
