/// One chat with the FieldOS assistant: the person's words go to the server,
/// the actions the assistant picks run on the phone ([AssistantTools]), and
/// their results go back, until the assistant has a plain answer.
///
/// Changing actions wait on a confirm card for the person's tap; nothing is
/// saved without it. The API's own history ([history]) is kept exactly as it
/// came back and only ever appended to, because the API requires its earlier
/// messages unchanged on every call.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:fieldos_mobile/agents/assistant_tools.dart';
import 'package:fieldos_mobile/auth/auth_service.dart' show Roles;
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/services/ai_backend.dart';

sealed class ChatItem {}

class PersonSaid extends ChatItem {
  PersonSaid(this.text);
  final String text;
}

class AssistantSaid extends ChatItem {
  AssistantSaid(this.text);
  final String text;
}

enum ConfirmState { waiting, saved, cancelled, failed }

/// A change the assistant wants to make, waiting for the person's yes.
class ConfirmAction extends ChatItem {
  ConfirmAction({required this.toolName, required this.summary});
  final String toolName;
  final String summary;
  ConfirmState state = ConfirmState.waiting;
  final _decision = Completer<bool>();
}

class ScreenButton extends ChatItem {
  ScreenButton(this.link);
  final ScreenLink link;
}

class ChatNotice extends ChatItem {
  ChatNotice(this.text, {this.code});
  final String text;

  /// The server's reason when it refused (signed_out, no_plan, ...), so the
  /// screen can offer the right button.
  final String? code;
}

class AssistantConversation extends ChangeNotifier {
  AssistantConversation({
    required this.backend,
    required this.tools,
    required this.appState,
    this.onDataChanged,
    this.onSettled,
    this.maxSteps = 10,
  });

  /// Called whenever the chat comes to rest (an answer finished, or the chat
  /// was cleared), so the screen can save it.
  final void Function()? onSettled;

  final AiBackend backend;
  final AssistantTools tools;

  /// What the assistant should know about the app right now (today, the
  /// language, the projects), sent with each thing the person says.
  final Future<String> Function() appState;

  /// A project's data changed (null: the project list itself changed), so
  /// the screens showing it can refresh.
  final void Function(String? projectId)? onDataChanged;

  /// Model calls allowed for one thing the person says.
  final int maxSteps;

  final items = <ChatItem>[];
  final history = <Map<String, dynamic>>[];
  bool busy = false;

  /// The newest assistant text, for reading aloud.
  String? lastReply;

  /// Share of this month's allowance left (0-100), as the server last said.
  int? allowanceLeft;

  /// Questions the person might ask next, shown under the last answer.
  /// Picked on the phone from what this turn did, so they cost nothing.
  List<String> followUps = const [];

  final _usedTools = <String>{};

  bool get waitingForConfirm => items.any((i) => i is ConfirmAction && i.state == ConfirmState.waiting);

  Future<void> send(String text) async {
    final words = text.trim();
    if (words.isEmpty || busy) return;
    busy = true;
    lastReply = null;
    followUps = const [];
    _usedTools.clear();
    items.add(PersonSaid(words));
    notifyListeners();
    final before = history.length;
    try {
      history.add({
        'role': 'user',
        'content': [
          {'type': 'text', 'text': await appState()},
          {'type': 'text', 'text': words},
        ],
      });
      await _run();
      followUps = suggestFollowUps(_usedTools, asked: words, canApprove: Roles.canApprove(tools.role));
    } on AiException catch (e) {
      // Back to the last complete exchange, so the next message is accepted.
      history.removeRange(before, history.length);
      _cancelWaiting();
      items.add(ChatNotice(e.message, code: e.code));
    } catch (e) {
      history.removeRange(before, history.length);
      _cancelWaiting();
      items.add(ChatNotice(trf('Something went wrong: {error}', {'error': e})));
    } finally {
      busy = false;
      notifyListeners();
      onSettled?.call();
    }
  }

  /// The person's tap on a confirm card.
  void decide(ConfirmAction action, bool yes) {
    if (action.state != ConfirmState.waiting || action._decision.isCompleted) return;
    action._decision.complete(yes);
  }

  /// Starts a fresh chat (a long one costs more with every message).
  void clear() {
    if (busy) return;
    items.clear();
    history.clear();
    lastReply = null;
    followUps = const [];
    notifyListeners();
    onSettled?.call();
  }

  /// The chat as JSON, to keep on the phone. A card still waiting for a tap
  /// can't be resumed later, so it is kept as cancelled.
  Map<String, dynamic> toJson() => {
        'v': 1,
        'items': [for (final i in items) _itemJson(i)],
        'history': history,
        'follow_ups': followUps,
      };

  /// Puts back a chat saved with [toJson]. Anything unreadable starts fresh.
  void restore(Map<String, dynamic> json) {
    if (busy) return;
    try {
      final restored = [for (final i in (json['items'] as List? ?? const [])) _itemFrom(Map<String, dynamic>.from(i as Map))];
      final hist = [for (final h in (json['history'] as List? ?? const [])) Map<String, dynamic>.from(h as Map)];
      items
        ..clear()
        ..addAll(restored.whereType<ChatItem>());
      history
        ..clear()
        ..addAll(hist);
      followUps = [for (final f in (json['follow_ups'] as List? ?? const [])) '$f'];
      lastReply = null;
    } catch (_) {
      items.clear();
      history.clear();
      followUps = const [];
    }
    notifyListeners();
  }

  static Map<String, dynamic> _itemJson(ChatItem i) => switch (i) {
        PersonSaid(:final text) => {'t': 'person', 'text': text},
        AssistantSaid(:final text) => {'t': 'assistant', 'text': text},
        final ConfirmAction a => {
            't': 'confirm',
            'tool': a.toolName,
            'summary': a.summary,
            'state': (a.state == ConfirmState.waiting ? ConfirmState.cancelled : a.state).name,
          },
        ScreenButton(:final link) => {'t': 'screen', 'screen': link.screen, 'project_id': link.projectId},
        ChatNotice(:final text, :final code) => {'t': 'notice', 'text': text, 'code': code},
      };

  static ChatItem? _itemFrom(Map<String, dynamic> j) {
    switch (j['t']) {
      case 'person':
        return PersonSaid('${j['text']}');
      case 'assistant':
        return AssistantSaid('${j['text']}');
      case 'confirm':
        return ConfirmAction(toolName: '${j['tool']}', summary: '${j['summary']}')
          ..state = ConfirmState.values.asNameMap()[j['state']] ?? ConfirmState.cancelled;
      case 'screen':
        return ScreenButton(ScreenLink('${j['screen']}', projectId: j['project_id'] as String?));
      case 'notice':
        return ChatNotice('${j['text']}', code: j['code'] as String?);
    }
    return null;
  }

  void _cancelWaiting() {
    for (final i in items) {
      if (i is ConfirmAction && i.state == ConfirmState.waiting) {
        i.state = ConfirmState.cancelled;
        if (!i._decision.isCompleted) i._decision.complete(false);
      }
    }
  }

  Future<void> _run() async {
    for (var step = 0; step < maxSteps; step++) {
      final reply = await backend.chat(history);
      allowanceLeft = reply.allowanceLeft ?? allowanceLeft;
      history.add({'role': 'assistant', 'content': reply.content});
      final text = reply.text;
      if (text.isNotEmpty) {
        items.add(AssistantSaid(text));
        lastReply = text;
        notifyListeners();
      }
      if (reply.stopReason == 'refusal') {
        items.add(ChatNotice(tr("The assistant can't help with that one. Try asking another way.")));
        return;
      }
      final uses = reply.toolUses;
      if (reply.stopReason != 'tool_use' || uses.isEmpty) {
        if (reply.stopReason == 'max_tokens' && text.isEmpty) {
          items.add(ChatNotice(tr('The answer was cut short. Please ask again in fewer words.')));
        }
        return;
      }
      history.add({'role': 'user', 'content': await _runTools(uses)});
    }
    items.add(ChatNotice(tr('That took too many steps. Try asking for one thing at a time.')));
  }

  /// Runs every action of one assistant turn and returns all their results
  /// in one message, in order: reads at once, changes after a confirm tap.
  Future<List<Map<String, dynamic>>> _runTools(List<Map<String, dynamic>> uses) async {
    final pending = <int, ConfirmAction>{};
    final results = List<Map<String, dynamic>?>.filled(uses.length, null);
    for (var n = 0; n < uses.length; n++) {
      final u = uses[n];
      final name = u['name'] as String? ?? '';
      _usedTools.add(name);
      final input = Map<String, dynamic>.from((u['input'] as Map?) ?? const {});
      if (writeTools.contains(name)) {
        try {
          final card = ConfirmAction(toolName: name, summary: await tools.describe(name, input));
          pending[n] = card;
          items.add(card);
        } on ToolInputError catch (e) {
          results[n] = _result(u, jsonEncode({'error': e.message}), isError: true);
        }
        continue;
      }
      final out = await tools.run(name, input);
      if (out.link != null) items.add(ScreenButton(out.link!));
      results[n] = _result(u, out.result, isError: out.isError);
    }
    if (pending.isNotEmpty) notifyListeners();
    for (final MapEntry(key: n, value: card) in pending.entries) {
      final u = uses[n];
      final yes = await card._decision.future;
      if (!yes) {
        card.state = ConfirmState.cancelled;
        results[n] = _result(u, '{"cancelled": "The person tapped Cancel. Nothing was saved."}');
      } else {
        final out = await tools.run(card.toolName, Map<String, dynamic>.from((u['input'] as Map?) ?? const {}));
        card.state = out.isError ? ConfirmState.failed : ConfirmState.saved;
        if (!out.isError) onDataChanged?.call(out.changedProjects ? null : out.changedProjectId);
        results[n] = _result(u, out.result, isError: out.isError);
      }
      notifyListeners();
    }
    return [for (final r in results) r!];
  }

  static Map<String, dynamic> _result(Map<String, dynamic> use, String content, {bool isError = false}) => {
        'type': 'tool_result',
        'tool_use_id': use['id'],
        'content': content.length > 15000 ? '${content.substring(0, 15000)}…' : content,
        if (isError) 'is_error': true,
      };
}

/// Up to three questions that follow naturally from what the assistant just
/// did ([used] are the tool names of the turn), in the app's language and
/// never the one just [asked].
List<String> suggestFollowUps(Set<String> used, {String asked = '', bool canApprove = true}) {
  final siteToday = tr('What happened on my sites today?');
  final spend = tr('How much did I spend this month?');
  final weekSpend = tr("Show this week's expenses");
  final late = tr('Which tasks are late?');
  final dueWeek = tr('What is due this week?');
  final absent = tr('Who was absent today?');
  final labour = tr('How much did labour cost this week?');
  final report = tr("Write today's daily report");
  final issues = tr('Any open issues on site?');
  final stock = tr('Which materials are running low?');
  final approvals = canApprove ? tr('What needs my approval?') : late;
  final cement = tr('Add ₹5,000 spent on cement');

  bool any(Iterable<String> names) => names.any(used.contains);
  final out = <String>[
    if (any(['add_expense', 'list_money', 'record_payment_received'])) ...[weekSpend, spend, approvals],
    if (any(['mark_attendance', 'add_worker', 'list_workers'])) ...[absent, labour],
    if (any(['add_task', 'update_task', 'list_tasks'])) ...[late, dueWeek],
    if (any(['add_daily_report'])) ...[issues, siteToday],
    if (any(['report_issue', 'list_issues'])) ...[issues, report],
    if (any(['record_material_received', 'record_material_used', 'stock_summary'])) ...[stock, cement],
    if (any(['pending_approvals'])) ...[approvals, spend],
    ...[siteToday, late, report, spend],
  ];
  final said = asked.trim().toLowerCase();
  final picked = <String>[];
  for (final q in out) {
    if (picked.length == 3) break;
    if (q.toLowerCase() == said || picked.contains(q)) continue;
    picked.add(q);
  }
  return picked;
}
