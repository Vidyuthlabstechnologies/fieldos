/// Blocking a teammate in project chat (issue #152): their messages are
/// hidden on this phone, everyone else's stay, and unblocking brings them
/// back.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/chat/blocked_people_screen.dart';
import 'package:fieldos_mobile/features/chat/project_chat_view.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/chat_block_service.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

SupabaseClient _offlineClient() => SupabaseClient(
      'http://localhost:1',
      'anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false, authFlowType: AuthFlowType.implicit),
    );

void main() {
  test('blocking is remembered on this phone, and unblocking forgets it', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final s = ChatBlockService(db);
    expect(await s.blocked(), isEmpty);
    await s.block('u-ravi', 'Ravi');
    await s.block('u-kiran', 'Kiran');
    expect(await ChatBlockService(db).blocked(), {'u-ravi': 'Ravi', 'u-kiran': 'Kiran'});
    await s.unblock('u-ravi');
    expect(await s.blocked(), {'u-kiran': 'Kiran'});
  });

  Future<void> waitFor(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 20 && f.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }

  testWidgets('a blocked person\'s messages are hidden; others stay; Blocked people unblocks', (tester) async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await tester.runAsync(() async {
      for (final (id, sender, name, body) in [
        ('m1', 'u-ravi', 'Ravi', 'rude words'),
        ('m2', 'u-asha', 'Asha', 'Slab casting at 4'),
      ]) {
        await db.messageDao.upsertFromRemote(ProjectMessagesCompanion.insert(
            id: id,
            projectId: 'p1',
            senderId: sender,
            senderName: name,
            body: body,
            createdAt: Value(DateTime.utc(2026, 11, 11))));
      }
      await ChatBlockService(db).block('u-ravi', 'Ravi');
    });
    final overrides = [
      appDatabaseProvider.overrideWithValue(db),
      cloudSyncClientProvider.overrideWithValue(_offlineClient()),
    ];
    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: const MaterialApp(home: Scaffold(body: ProjectChatView(projectId: 'p1'))),
    ));
    await waitFor(tester, find.text('Slab casting at 4'));
    expect(find.text('Slab casting at 4'), findsOneWidget);
    expect(find.text('rude words'), findsNothing);

    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: const MaterialApp(home: BlockedPeopleScreen()),
    ));
    await waitFor(tester, find.text('Ravi'));
    expect(find.text('Ravi'), findsOneWidget);
    await tester.tap(find.text('Unblock'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    await waitFor(tester, find.textContaining('Nobody is blocked'));
    expect(find.textContaining('Nobody is blocked'), findsOneWidget);
    expect(await tester.runAsync(() => ChatBlockService(db).blocked()), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
