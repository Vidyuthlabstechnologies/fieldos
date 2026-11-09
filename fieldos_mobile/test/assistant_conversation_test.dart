/// The assistant's conversation loop, with a scripted server: reads run at
/// once, changes wait for a tap, results go back in one message, the API
/// history is only ever appended to, and a failure leaves it ready for the
/// next message.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/agents/assistant_conversation.dart';
import 'package:fieldos_mobile/agents/assistant_tools.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/services/ai_backend.dart';

class _ScriptedBackend implements AiBackend {
  _ScriptedBackend(this.replies);
  final List<Object> replies; // AiReply or AiException
  final sent = <List<Map<String, dynamic>>>[];

  @override
  bool get signedIn => true;

  @override
  Future<AiReply> chat(List<Map<String, dynamic>> messages) async {
    sent.add(jsonDecode(jsonEncode(messages)).cast<Map<String, dynamic>>());
    final next = replies.removeAt(0);
    if (next is AiException) throw next;
    return next as AiReply;
  }

  @override
  Future<String> transcribe(Uint8List wav, {String languageCode = 'unknown'}) async => '';
}

AiReply _text(String t) => AiReply(content: [
      {'type': 'text', 'text': t}
    ], stopReason: 'end_turn', allowanceLeft: 99);

AiReply _tools(List<(String id, String name, Map<String, dynamic> input)> uses, {String? say}) => AiReply(content: [
      {'type': 'thinking', 'thinking': '', 'signature': 'sig'},
      if (say != null) {'type': 'text', 'text': say},
      for (final (id, name, input) in uses) {'type': 'tool_use', 'id': id, 'name': name, 'input': input},
    ], stopReason: 'tool_use');

void main() {
  late AppDatabase db;
  late AssistantTools tools;

  setUp(() async {
    db = AppDatabase.memory();
    tools = AssistantTools(db: db, companyId: 'c1', userId: 'u1', role: 'owner');
    await db.projectDao.create(ProjectsCompanion.insert(id: 'p1', companyId: 'c1', name: 'Villa', status: const Value('active')));
  });
  tearDown(() => db.close());

  AssistantConversation chat(_ScriptedBackend backend, {List<String?>? changed}) => AssistantConversation(
        backend: backend,
        tools: tools,
        appState: () async => '<app_state>{}</app_state>',
        onDataChanged: (p) => changed?.add(p),
      );

  test('a question that needs data: the read runs and the answer shows', () async {
    final backend = _ScriptedBackend([
      _tools([('t1', 'list_projects', {})]),
      _text('You have one site, Villa.'),
    ]);
    final c = chat(backend);
    await c.send('How many sites?');

    expect(c.items.whereType<AssistantSaid>().single.text, 'You have one site, Villa.');
    expect(c.lastReply, 'You have one site, Villa.');
    expect(c.allowanceLeft, 99);
    // Second call carries the first reply unchanged (thinking included) and the result.
    final second = backend.sent[1];
    expect(second, hasLength(3));
    expect(second[1]['content'][0]['type'], 'thinking');
    final result = second[2]['content'][0];
    expect(result['type'], 'tool_result');
    expect(result['tool_use_id'], 't1');
    expect(jsonDecode(result['content'] as String), [
      {'id': 'p1', 'name': 'Villa', 'client': null, 'status': 'active'}
    ]);
    // The person's words go with the app state.
    expect(second[0]['content'][1]['text'], 'How many sites?');
    expect(c.history, hasLength(4));
  });

  test('a change waits for Save, then is saved and reported back', () async {
    final changed = <String?>[];
    final backend = _ScriptedBackend([
      _tools([('t1', 'add_expense', {'project_id': 'p1', 'amount': 5000, 'category': 'Material'})]),
      _text('Saved ₹5,000 for cement.'),
    ]);
    final c = chat(backend, changed: changed);
    final done = c.send('Add 5000 for cement');
    await pumpEventQueue();

    final card = c.items.whereType<ConfirmAction>().single;
    expect(card.summary, 'Expense ₹5,000 for Material at Villa');
    expect(c.waitingForConfirm, isTrue);
    expect(await db.expenseDao.forProject('p1'), isEmpty, reason: 'nothing saved before the tap');

    c.decide(card, true);
    await done;
    expect(card.state, ConfirmState.saved);
    expect((await db.expenseDao.forProject('p1')).single.amount, 5000);
    expect(changed, ['p1']);
    expect(jsonDecode(backend.sent[1].last['content'][0]['content'] as String)['saved'], isTrue);
  });

  test('Cancel saves nothing and tells the assistant', () async {
    final backend = _ScriptedBackend([
      _tools([('t1', 'add_task', {'project_id': 'p1', 'title': 'Curing'})]),
      _text('OK, not added.'),
    ]);
    final c = chat(backend);
    final done = c.send('Add a curing task');
    await pumpEventQueue();
    c.decide(c.items.whereType<ConfirmAction>().single, false);
    await done;
    expect(await db.taskDao.forProject('p1'), isEmpty);
    expect(backend.sent[1].last['content'][0]['content'], contains('Cancel'));
  });

  test('several actions in one turn come back together, in order', () async {
    final backend = _ScriptedBackend([
      _tools([
        ('a', 'list_projects', {}),
        ('b', 'report_issue', {'project_id': 'p1', 'description': 'Cement short'}),
        ('c', 'add_expense', {'project_id': 'nope', 'amount': 10, 'category': 'Fuel'}),
      ]),
      _text('Done.'),
    ]);
    final c = chat(backend);
    final done = c.send('...');
    await pumpEventQueue();
    // The broken one never reaches a card; it goes back as an error.
    final cards = c.items.whereType<ConfirmAction>().toList();
    expect(cards, hasLength(1));
    c.decide(cards.single, true);
    await done;
    final results = backend.sent[1].last['content'] as List;
    expect(results.map((r) => r['tool_use_id']), ['a', 'b', 'c']);
    expect(results[2]['is_error'], isTrue);
    expect((await db.issueDao.forProject('p1')).single.description, 'Cement short');
  });

  test('a screen button is offered for things done by hand', () async {
    final backend = _ScriptedBackend([
      _tools([('t1', 'open_screen', {'screen': 'money', 'project_id': 'p1'})], say: 'Tap below to make the bill.'),
      _text('There you can make an RA bill.'),
    ]);
    final c = chat(backend);
    await c.send('How do I bill my client?');
    expect(c.items.whereType<ScreenButton>().single.link.screen, 'money');
  });

  test('a server refusal shows its message and leaves history ready for the next try', () async {
    final backend = _ScriptedBackend([
      _tools([('t1', 'list_projects', {})]),
      AiException('No internet.', code: 'offline'),
      _text('Hello again.'),
    ]);
    final c = chat(backend);
    await c.send('Hi');
    expect(c.items.whereType<ChatNotice>().single.code, 'offline');
    expect(c.history, isEmpty);
    await c.send('Hi again');
    expect(backend.sent.last.first['role'], 'user');
    expect(backend.sent.last, hasLength(1));
    expect(c.history, hasLength(2));
  });

  test('history only grows: each call starts with everything sent before', () async {
    final backend = _ScriptedBackend([_text('One.'), _tools([('t', 'pending_approvals', {})]), _text('Two.')]);
    final c = chat(backend);
    await c.send('first');
    await c.send('second');
    final a = jsonEncode(backend.sent[0]);
    final b = jsonEncode(backend.sent[1]);
    final d = jsonEncode(backend.sent[2]);
    expect(b.startsWith(a.substring(0, a.length - 1)), isTrue);
    expect(d.startsWith(b.substring(0, b.length - 1)), isTrue);
  });

  test('a loop that never ends is stopped', () async {
    final backend = _ScriptedBackend([for (var i = 0; i < 10; i++) _tools([('t$i', 'list_projects', {})])]);
    final c = chat(backend);
    await c.send('loop');
    expect(backend.sent, hasLength(10));
    expect(c.items.whereType<ChatNotice>().single.text, contains('too many steps'));
  });

  test('a refusal is explained', () async {
    final c = chat(_ScriptedBackend([const AiReply(content: [], stopReason: 'refusal')]));
    await c.send('something odd');
    expect(c.items.whereType<ChatNotice>(), hasLength(1));
  });

  test('busy: a second message while one is running is ignored', () async {
    final gate = Completer<void>();
    final backend = _ScriptedBackend([_text('ok')]);
    final c = AssistantConversation(
      backend: backend,
      tools: tools,
      appState: () async {
        await gate.future;
        return '';
      },
    );
    final first = c.send('one');
    await c.send('two');
    gate.complete();
    await first;
    expect(c.items.whereType<PersonSaid>().map((p) => p.text), ['one']);
  });

  test('a chat saved as JSON comes back the same; a card still waiting comes back cancelled', () async {
    final backend = _ScriptedBackend([
      _tools([('t1', 'list_projects', {})]),
      _text('You have one site, Villa.'),
    ]);
    final c = chat(backend);
    await c.send('How many sites?');
    c.items.add(ConfirmAction(toolName: 'add_task', summary: 'Task Curing at Villa'));
    c.items.add(ScreenButton(const ScreenLink('money', projectId: 'p1')));
    c.items.add(ChatNotice('No plan', code: 'no_plan'));

    final saved = jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>;
    final back = chat(_ScriptedBackend([]))..restore(saved);
    expect(back.history, c.history);
    expect(back.followUps, c.followUps);
    expect(back.items.whereType<PersonSaid>().single.text, 'How many sites?');
    expect(back.items.whereType<AssistantSaid>().single.text, 'You have one site, Villa.');
    final card = back.items.whereType<ConfirmAction>().single;
    expect((card.summary, card.state), ('Task Curing at Villa', ConfirmState.cancelled));
    expect(back.waitingForConfirm, isFalse);
    final link = back.items.whereType<ScreenButton>().single.link;
    expect((link.screen, link.projectId), ('money', 'p1'));
    expect(back.items.whereType<ChatNotice>().single.code, 'no_plan');

    // And the restored chat carries on from the same API history.
    final next = _ScriptedBackend([_text('Still one.')]);
    final more = chat(next)..restore(saved);
    await more.send('And now?');
    expect(next.sent.single.take(c.history.length).toList(), c.history);
  });

  test('a damaged saved chat starts fresh instead of failing', () {
    final c = chat(_ScriptedBackend([]))..restore({'items': 'nonsense', 'history': 3});
    expect(c.items, isEmpty);
    expect(c.history, isEmpty);
  });

  test('follow-up questions fit what was just done and never repeat the question', () async {
    final backend = _ScriptedBackend([
      _tools([('t1', 'add_expense', {'project_id': 'p1', 'amount': 500, 'category': 'Material'})]),
      _text('Saved.'),
    ]);
    final c = chat(backend);
    final done = c.send("Show this week's expenses");
    await pumpEventQueue();
    c.decide(c.items.whereType<ConfirmAction>().single, true);
    await done;
    expect(c.followUps, ['How much did I spend this month?', 'What needs my approval?', 'What happened on my sites today?']);

    expect(suggestFollowUps({}), ['What happened on my sites today?', 'Which tasks are late?', "Write today's daily report"]);
    expect(suggestFollowUps({'pending_approvals'}, canApprove: false).contains('What needs my approval?'), isFalse);
    expect(suggestFollowUps({'mark_attendance'}).take(2), ['Who was absent today?', 'How much did labour cost this week?']);
  });

  test('a failed message offers no follow-ups', () async {
    final c = chat(_ScriptedBackend([AiException('Server is busy', code: 'busy')]));
    await c.send('How many sites?');
    expect(c.followUps, isEmpty);
  });
}
