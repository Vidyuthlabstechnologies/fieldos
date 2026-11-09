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
    this.maxSteps = 10,
  });

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

  /// Calls left today, as the server last said.
  int? leftToday;

  bool get waitingForConfirm => items.any((i) => i is ConfirmAction && i.state == ConfirmState.waiting);

  Future<void> send(String text) async {
    final words = text.trim();
    if (words.isEmpty || busy) return;
    busy = true;
    lastReply = null;
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
    notifyListeners();
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
      leftToday = reply.leftToday ?? leftToday;
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
