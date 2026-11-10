import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/money/expense_bills.dart';
import 'package:fieldos_mobile/features/project/site_notes.dart';
import 'package:fieldos_mobile/features/project/site_notes_screen.dart';
import 'package:fieldos_mobile/features/shared/photo_capture.dart';
import 'package:fieldos_mobile/features/shared/photo_stamp.dart';
import 'package:fieldos_mobile/features/shared/photo_viewer.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/sync_mappers.dart';

/// Photos, bills and notes, from Onsite's Play reviews: "can't select
/// multiple photos", "attach bill with expense", "PDF not only photo",
/// "bill photo is blurry", "no option to delete photo", "notes section
/// for each project".
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('fieldos_r6'));
  tearDown(() => dir.deleteSync(recursive: true));

  String file(String name, [List<int>? bytes]) =>
      (File('${dir.path}/$name')..writeAsBytesSync(bytes ?? img.encodeJpg(img.Image(width: 8, height: 8)))).path;

  group('picking and keeping photos', () {
    test('a multi-pick keeps every file under its own name', () {
      expect(capturedFileName('dpr', 1700, 0, 'IMG_1.jpg'), 'dpr_1700_IMG_1.jpg');
      expect(capturedFileName('dpr', 1700, 1, 'IMG 1.jpg'), 'dpr_1700_1_IMG_1.jpg');
      expect(capturedFileName('bill', 1700, 0, 'a/b.pdf'), 'bill_1700_a_b.pdf');
      expect(billFileName('${dir.path}/bill_1700_2_invoice.pdf'), 'invoice.pdf');
      expect(billMaxSide, greaterThan(photoMaxSide));
      expect(billQuality, greaterThan(photoQuality));
    });

    test('a bill\'s stamp goes under the photo, so its total is never covered', () {
      final photo = img.Image(width: 400, height: 300);
      img.fill(photo, color: img.ColorRgb8(255, 255, 255));
      final bytes = Uint8List.fromList(img.encodeJpg(photo, quality: 100));
      final lines = stampLines(takenAt: DateTime(2026, 11, 9, 10), place: 'Tower B');

      final over = img.decodeJpg(stampJpeg(bytes, lines)!)!;
      expect(over.height, 300);
      expect(over.getPixel(5, 295).r, lessThan(200)); // darkened band on the photo

      final under = img.decodeJpg(stampJpeg(bytes, lines, below: true, quality: billQuality)!)!;
      expect(under.width, 400);
      expect(under.height, greaterThan(300));
      expect(under.getPixel(5, 295).r, greaterThan(240)); // the photo itself is untouched
    });

    test('a report photo can be deleted, file and all', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final path = file('dpr.jpg');
      await db.dprDao.addPhoto(DprPhotosCompanion.insert(id: 'x', dprEntryId: 'd1', photoPath: path));
      await db.dprDao.addPhoto(DprPhotosCompanion.insert(id: 'y', dprEntryId: 'd1', photoPath: file('keep.jpg')));
      final photos = await db.dprDao.photosFor('d1');
      await db.dprDao.deletePhoto(photos.firstWhere((p) => p.photoPath == path).id);
      expect((await db.dprDao.photosFor('d1')).map((p) => p.photoPath), [endsWith('keep.jpg')]);
      expect(File(path).existsSync(), isFalse);
      await db.dprDao.deletePhoto('gone'); // nothing to do
    });

    testWidgets('the viewer deletes a photo after asking, and closes on the last one', (tester) async {
      final paths = [file('a.jpg'), file('b.jpg')];
      final deleted = <String>[];
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: PhotoStrip(paths: paths, onDelete: (p) async => deleted.add(p)))));
      await tester.tap(find.bySemanticsLabel('Open photo').first);
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('delete-photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(deleted, isEmpty);

      await tester.tap(find.byKey(const Key('delete-photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(deleted, [paths[0]]);
      expect(find.text('Photo'), findsOneWidget); // one left

      await tester.tap(find.byKey(const Key('delete-photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(deleted, paths);
      expect(find.byType(PhotoViewerScreen), findsNothing);
    });

    testWidgets('without permission there is no delete button', (tester) async {
      await tester.pumpWidget(MaterialApp(home: PhotoViewerScreen(paths: [file('a.jpg')])));
      expect(find.byKey(const Key('delete-photo')), findsNothing);
    });
  });

  group('bills on expenses', () {
    test('kept with the expense, counted per site, and removed with the file', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      for (final (id, p) in [('e1', 'p'), ('e2', 'p'), ('e3', 'other')]) {
        await db.expenseDao.create(SiteExpensesCompanion.insert(
            id: id, projectId: p, category: 'Material', amount: 100, incurredOn: '2026-11-09', recordedBy: 'u'));
      }
      final photo = await db.expenseDao.attach('e1', file('bill.jpg'));
      final pdf = await db.expenseDao.attach('e1', file('bill.pdf', utf8.encode('%PDF-1.4')));
      await db.expenseDao.attach('e2', file('quote.png'));
      await db.expenseDao.attach('e3', file('elsewhere.jpg'));
      expect(photo.mimeType, 'image/jpeg');
      expect(pdf.mimeType, 'application/pdf');
      expect(attachmentMimeType('x.PNG'), 'image/png');
      expect(await db.expenseDao.attachmentCounts('p'), {'e1': 2, 'e2': 1});

      await db.expenseDao.removeAttachment(pdf.id);
      expect((await db.expenseDao.attachmentsFor('e1')).map((a) => a.id), [photo.id]);
      expect(File(pdf.filePath).existsSync(), isFalse);
      // Bills go to the team too (1.7.x): each add is queued, and taking
      // the PDF off is queued as a delete.
      final bills = (await db.syncOutboxDao.pending()).where((o) => o.targetTable == 'expense_attachments');
      expect(bills.where((o) => o.operation == 'insert'), hasLength(4));
      expect(bills.where((o) => o.operation == 'delete').map((o) => o.recordId), [pdf.id]);
    });

    testWidgets('the expense shows its photo and PDF bills, and says when one is on another phone', (tester) async {
      final db = AppDatabase.memory();
      final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      late SiteExpense e;
      await tester.runAsync(() async {
        e = await db.expenseDao.create(SiteExpensesCompanion.insert(
            id: 'e1', projectId: 'p', category: 'Material', amount: 100, incurredOn: '2026-11-09', recordedBy: 'u'));
        await db.expenseDao.attach('e1', file('bill.jpg'));
        await db.expenseDao.attach('e1', file('bill_1700_invoice.pdf', utf8.encode('%PDF-1.4')));
        await db.expenseDao.attach('e1', '/teammate/phone/bill.jpg');
      });
      Future<void> show(bool canChange) async {
        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              theme: buildFieldOsTheme(Brightness.light),
              home: Scaffold(body: ExpenseBills(expense: e, canChange: canChange))),
        ));
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
          await tester.pump();
        }
      }

      await show(true);
      expect(find.bySemanticsLabel('Open photo'), findsOneWidget);
      expect(find.text('invoice.pdf'), findsOneWidget);
      expect(find.text('1 bill is on the phone that added it.'), findsOneWidget);
      expect(find.byKey(const Key('expense-attach-bill')), findsOneWidget);
      expect(find.byTooltip('Remove bill'), findsOneWidget);

      await show(false);
      expect(find.byKey(const Key('expense-attach-bill')), findsNothing);
      expect(find.byTooltip('Remove bill'), findsNothing);
    });
  });

  group('site notes', () {
    ProjectNote note(String body, {String by = 'u', bool pinned = false}) => ProjectNote(
        id: body, projectId: 'p', body: body, pinned: pinned, deleted: false, createdBy: by,
        createdAt: DateTime(2026, 11, 9), updatedAt: DateTime(2026, 11, 9));

    test('title, rest, search and who may change one', () {
      expect(noteTitle('  Client visit\nWants 4 ft window\n\nand grey tiles'), 'Client visit');
      expect(noteRest('Client visit\nWants 4 ft window\n\nand grey tiles'), 'Wants 4 ft window and grey tiles');
      expect(noteRest('One line'), isNull);
      expect(noteTitle('x' * 100).length, 80);
      final notes = [note('Kitchen window 4 ft'), note('Call Ramesh plumber'), note('Window grills by Friday')];
      expect(searchNotes(notes, 'WINDOW').map((n) => n.id), ['Kitchen window 4 ft', 'Window grills by Friday']);
      expect(searchNotes(notes, 'window friday').single.id, 'Window grills by Friday');
      expect(searchNotes(notes, '  '), notes);
      expect(canChangeNote(note('a', by: 'me'), userId: 'me', isManager: false), isTrue);
      expect(canChangeNote(note('a', by: 'other'), userId: 'me', isManager: false), isFalse);
      expect(canChangeNote(note('a', by: 'other'), userId: 'me', isManager: true), isTrue);
      expect(noteShareText(note('Call Ramesh'), siteName: 'Tower B'), 'Tower B\nCall Ramesh');
    });

    test('saved, pinned first, removed without being lost, and synced', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final a = await db.noteDao.create(projectId: 'p', body: '  Old note  ', by: 'u', now: DateTime(2026, 11, 1));
      final b = await db.noteDao.create(projectId: 'p', body: 'Newer note', by: 'u', now: DateTime(2026, 11, 2));
      await db.noteDao.create(projectId: 'other', body: 'Another site', by: 'u');
      expect(a.body, 'Old note');
      expect((await db.noteDao.forProject('p')).map((n) => n.id), [b.id, a.id]);

      await db.noteDao.change(a.id, pinned: true, now: DateTime(2026, 11, 3));
      expect((await db.noteDao.forProject('p')).first.id, a.id);
      await db.noteDao.change(b.id, deleted: true);
      expect((await db.noteDao.forProject('p')).map((n) => n.id), [a.id]);
      expect(() => db.noteDao.create(projectId: 'p', body: '   ', by: 'u'), throwsArgumentError);

      final queued = await db.syncOutboxDao.pending();
      expect(queued.map((o) => (o.targetTable, o.operation)).toList(), [
        ('site_notes', 'insert'),
        ('site_notes', 'insert'),
        ('site_notes', 'insert'),
        ('site_notes', 'update'),
        ('site_notes', 'update'),
      ]);
      final sent = jsonDecode(queued.last.payload) as Map<String, dynamic>;
      expect(sent['deleted'], isTrue);
      expect(sent['created_by'], 'u');
      expect(sent['updated_at'], endsWith('Z'));
    });

    test('a teammate\'s copy wins only when it is newer', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final mine = await db.noteDao.create(projectId: 'p', body: 'Mine', by: 'u', now: DateTime(2026, 11, 9, 12));
      Map<String, dynamic> remote(String body, DateTime at) =>
          {...projectNoteToSupabaseJson(mine), 'body': body, 'updated_at': at.toUtc().toIso8601String()};
      await db.noteDao.upsertFromRemote(projectNoteFromSupabaseJson(remote('Older', DateTime(2026, 11, 9, 11))));
      expect((await db.noteDao.forProject('p')).single.body, 'Mine');
      await db.noteDao.upsertFromRemote(projectNoteFromSupabaseJson(remote('Theirs', DateTime(2026, 11, 9, 13))));
      expect((await db.noteDao.forProject('p')).single.body, 'Theirs');
      await db.noteDao.upsertFromRemote(projectNoteFromSupabaseJson(
          {'id': 'n2', 'project_id': 'p', 'body': 'From the cloud', 'created_by': 'v'}));
      expect((await db.noteDao.forProject('p')).map((n) => n.body), containsAll(['Theirs', 'From the cloud']));
    });

    testWidgets('write a note, pin it, remove it and undo', (tester) async {
      final db = AppDatabase.memory();
      final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      late String userId;
      await tester.runAsync(() async {
        final session = container.read(sessionProvider.notifier);
        await session.register(username: 'ravi', name: 'Ravi Kumar', password: '123456');
        await session.createCompany('Sri Sai Constructions');
        userId = container.read(sessionProvider).user!.id;
        await db.noteDao.create(projectId: 'p', body: 'Cement rate ₹380', by: userId, now: DateTime(2026, 11, 1));
      });
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: buildFieldOsTheme(Brightness.light), home: const SiteNotesScreen(projectId: 'p', siteName: 'Tower B')),
      ));
      Future<void> settle() async {
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pumpAndSettle();
        }
      }

      await settle();
      expect(find.text('Cement rate ₹380'), findsOneWidget);

      await tester.tap(find.byKey(const Key('note-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('note-body')), 'Client visit\nWants a 4 ft kitchen window');
      await tester.tap(find.byKey(const Key('note-save')));
      await settle();
      expect(find.text('Client visit'), findsOneWidget);
      expect(find.textContaining('Wants a 4 ft kitchen window'), findsOneWidget);
      // Newest first.
      expect(tester.getTopLeft(find.text('Client visit')).dy, lessThan(tester.getTopLeft(find.text('Cement rate ₹380')).dy));

      await tester.tap(find.text('Cement rate ₹380'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('note-pin')));
      await settle();
      expect(tester.getTopLeft(find.text('Cement rate ₹380')).dy, lessThan(tester.getTopLeft(find.text('Client visit')).dy));
      expect(find.byIcon(Icons.push_pin), findsOneWidget);

      await tester.tap(find.text('Client visit'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('note-remove')));
      await settle();
      expect(find.text('Client visit'), findsNothing);
      await tester.tap(find.text('Undo'));
      await settle();
      expect(find.text('Client visit'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
