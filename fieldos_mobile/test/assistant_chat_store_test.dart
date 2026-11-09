/// Ask FieldOS chats kept on the phone: newest first, kept apart per person
/// and company, trimmed to the newest [AssistantChatStore.keep], and gone
/// when deleted.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/agents/assistant_chat_store.dart';
import 'package:fieldos_mobile/data/app_database.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  Map<String, dynamic> chatSaying(String words) => {
        'v': 1,
        'items': [
          {'t': 'person', 'text': words}
        ],
        'history': <Object>[],
      };

  test('saved chats come back newest first, with their messages', () async {
    final store = AssistantChatStore(db: db, companyId: 'c1', userId: 'u1');
    expect(await store.list(), isEmpty);
    await store.save('a', title: 'First', chat: chatSaying('First'), at: DateTime(2026, 11, 1));
    await store.save('b', title: 'Second', chat: chatSaying('Second'), at: DateTime(2026, 11, 2));
    await store.save('a', title: 'First', chat: chatSaying('First again'), at: DateTime(2026, 11, 3));

    final chats = await store.list();
    expect([for (final c in chats) c.id], ['a', 'b']);
    expect(chats.first.updatedAt, DateTime(2026, 11, 3));
    expect((await store.load('a'))!['items'][0]['text'], 'First again');
  });

  test("another person's or another company's chats are not shown", () async {
    await AssistantChatStore(db: db, companyId: 'c1', userId: 'u1').save('a', title: 'Mine', chat: chatSaying('Mine'));
    expect(await AssistantChatStore(db: db, companyId: 'c1', userId: 'u2').list(), isEmpty);
    expect(await AssistantChatStore(db: db, companyId: 'c2', userId: 'u1').list(), isEmpty);
    expect(await AssistantChatStore(db: db, companyId: 'c1', userId: 'u2').load('a'), isNull);
  });

  test('only the newest chats are kept, and older ones are removed from the phone', () async {
    final store = AssistantChatStore(db: db, companyId: 'c1', userId: 'u1');
    for (var n = 0; n < AssistantChatStore.keep + 2; n++) {
      await store.save('chat$n', title: 'Chat $n', chat: chatSaying('Chat $n'), at: DateTime(2026, 11, 1, 0, n));
    }
    final chats = await store.list();
    expect(chats, hasLength(AssistantChatStore.keep));
    expect(chats.first.id, 'chat${AssistantChatStore.keep + 1}');
    expect(await store.load('chat0'), isNull);
    expect(await store.load('chat1'), isNull);
    expect(await store.load('chat2'), isNotNull);
  });

  test('keys fit the settings table, even with full-length ids', () async {
    const uuid = '46d783da-a5ca-4fdd-8d82-899c467650d7';
    final store = AssistantChatStore(db: db, companyId: uuid, userId: uuid);
    final id = AssistantChatStore.newId();
    await store.save(id, title: 'Long ids', chat: chatSaying('Long ids'));
    expect((await store.list()).single.id, id);
    expect(await store.load(id), isNotNull);
  });

  test('delete and delete all', () async {
    final store = AssistantChatStore(db: db, companyId: 'c1', userId: 'u1');
    await store.save('a', title: 'A', chat: chatSaying('A'));
    await store.save('b', title: 'B', chat: chatSaying('B'));
    await store.delete('a');
    expect([for (final c in await store.list()) c.id], ['b']);
    expect(await store.load('a'), isNull);
    await store.deleteAll();
    expect(await store.list(), isEmpty);
    expect(await store.load('b'), isNull);
  });
}
