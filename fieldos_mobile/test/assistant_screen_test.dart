/// Ask FieldOS on screen: the way in from Home, the sign-in it needs, the
/// welcome ideas, and a change going from a confirm card to a saved record.
library;

import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/assistant/assistant_screen.dart';
import 'package:fieldos_mobile/features/home/home_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/ai_backend.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

class _FakeAi implements AiBackend {
  _FakeAi({this.signedIn = true, List<AiReply>? replies}) : replies = replies ?? [];
  @override
  final bool signedIn;
  final List<AiReply> replies;
  int calls = 0;

  @override
  Future<AiReply> chat(List<Map<String, dynamic>> messages) async {
    calls++;
    return replies.removeAt(0);
  }

  @override
  Future<String> transcribe(Uint8List wav, {String languageCode = 'unknown'}) async => '';
}

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));

  Future<(ProviderContainer, AppDatabase, String)> setUp(WidgetTester tester, AiBackend ai) async {
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      aiBackendProvider.overrideWithValue(ai),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    late String companyId;
    await tester.runAsync(() async {
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'ravi', name: 'Ravi Kumar', password: '123456');
      companyId = (await session.createCompany('Sri Sai Constructions')).id;
      await db.projectDao.create(
          ProjectsCompanion.insert(id: 'p1', companyId: companyId, name: 'Narapally Villa', status: const Value('active')));
    });
    return (container, db, companyId);
  }

  Future<void> pump(WidgetTester tester, ProviderContainer container, Widget home) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: home),
    ));
    await settle(tester);
  }

  testWidgets('Home has Ask FieldOS at the top, and it opens the assistant', (tester) async {
    final (container, _, _) = await setUp(tester, _FakeAi());
    await pump(tester, container, const HomeScreen());
    expect(find.text('Ask FieldOS'), findsOneWidget);
    await tester.tap(find.text('Ask FieldOS'));
    await settle(tester);
    expect(find.byType(AssistantScreen), findsOneWidget);
    expect(find.text('Namaste, Ravi! What should I do?'), findsOneWidget);
    expect(find.text('Which tasks are late?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a FieldOS sign-in it explains and offers Team & sync', (tester) async {
    final (container, _, _) = await setUp(tester, _FakeAi(signedIn: false));
    await pump(tester, container, const AssistantScreen());
    expect(find.text('Sign in once to use the assistant'), findsOneWidget);
    expect(find.text('Sign in to Team & sync'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('an idea chip asks, and a change is saved only after Save', (tester) async {
    final ai = _FakeAi(replies: [
      const AiReply(content: [
        {'type': 'text', 'text': 'I will add it.'},
        {
          'type': 'tool_use',
          'id': 't1',
          'name': 'add_expense',
          'input': {'project_id': 'p1', 'amount': 5000, 'category': 'Material', 'note': 'cement'}
        },
      ], stopReason: 'tool_use'),
      const AiReply(content: [
        {'type': 'text', 'text': 'Saved ₹5,000 for cement at Narapally Villa.'}
      ], stopReason: 'end_turn'),
    ]);
    final (container, db, _) = await setUp(tester, ai);
    await pump(tester, container, const AssistantScreen());

    await tester.tap(find.text('Add ₹5,000 spent on cement'));
    await settle(tester);
    expect(find.text('Add ₹5,000 spent on cement'), findsOneWidget, reason: 'shown as what the person said');
    expect(find.text('Expense ₹5,000 for Material at Narapally Villa · cement'), findsOneWidget);
    expect(find.text('Save this?'), findsOneWidget);
    expect(await tester.runAsync(() => db.expenseDao.forProject('p1')), isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Saved ₹5,000 for cement at Narapally Villa.'), findsOneWidget);
    final rows = await tester.runAsync(() => db.expenseDao.forProject('p1'));
    expect(rows!.single.amount, 5000);
    expect(ai.calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a low monthly allowance is shown under the chat', (tester) async {
    final ai = _FakeAi(replies: [
      const AiReply(content: [
        {'type': 'text', 'text': 'You have one site.'}
      ], stopReason: 'end_turn', allowanceLeft: 15),
    ]);
    final (container, _, _) = await setUp(tester, ai);
    await pump(tester, container, const AssistantScreen());
    expect(find.textContaining('assistant use is left'), findsNothing);
    await tester.tap(find.text('Which tasks are late?'));
    await settle(tester);
    expect(find.text("15% of this month's assistant use is left"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the assistant speaks Hindi in a Hindi app', (tester) async {
    setCurrentLanguage(AppLanguage.hi);
    final (container, _, _) = await setUp(tester, _FakeAi());
    await pump(tester, container, const AssistantScreen());
    expect(find.text('FieldOS से पूछें'), findsOneWidget);
    expect(find.text('नमस्ते, Ravi! मैं क्या करूँ?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the chat is still there when the assistant is opened again, with follow-ups under the answer',
      (tester) async {
    final ai = _FakeAi(replies: [
      const AiReply(content: [
        {'type': 'text', 'text': 'You have one site, Narapally Villa.'}
      ], stopReason: 'end_turn'),
    ]);
    final (container, _, _) = await setUp(tester, ai);
    await pump(tester, container, const AssistantScreen());

    await tester.tap(find.text('Which tasks are late?'));
    await settle(tester);
    expect(find.text('You have one site, Narapally Villa.'), findsOneWidget);
    expect(find.text('You might ask next'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'What happened on my sites today?'), findsOneWidget);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));

    // Leave and come back: the same chat opens.
    await pump(tester, container, const SizedBox());
    await pump(tester, container, const AssistantScreen());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await settle(tester);
    expect(find.text('You have one site, Narapally Villa.'), findsOneWidget);
    expect(find.text('Which tasks are late?'), findsOneWidget, reason: 'the question, not a welcome idea');

    // Past chats lists it; New chat starts fresh.
    await tester.tap(find.byTooltip('Past chats'));
    await settle(tester);
    expect(find.text('Past chats'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Which tasks are late?'), findsOneWidget);
    await tester.tapAt(const Offset(200, 40));
    await settle(tester);
    await tester.tap(find.byTooltip('New chat'));
    await settle(tester);
    expect(find.text('Namaste, Ravi! What should I do?'), findsOneWidget);
    expect(ai.calls, 1);
    expect(tester.takeException(), isNull);
  });
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 300));
  }
}
