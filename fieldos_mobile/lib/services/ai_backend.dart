/// The FieldOS server's AI: the assistant's replies (Claude) and speech to
/// text for languages a phone can't recognise itself (Sarvam).
///
/// Both run in the `ai-assistant` Supabase edge function, which holds the
/// one shared Anthropic key and the one shared Sarvam key. Nobody ever types
/// a key into the app, and no key ships inside it. The function checks the
/// person's FieldOS sign-in and plan, and caps what each account's use may cost
/// in a month.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:supabase/supabase.dart';

class AiException implements Exception {
  AiException(this.message, {this.code = 'error'});
  final String message;

  /// The server's reason: signed_out, no_plan, daily_limit, monthly_limit, too_large,
  /// not_configured, upstream, offline, ...
  final String code;

  @override
  String toString() => message;
}

/// One assistant message, exactly as the API returned it. [content] goes back
/// to the server unchanged on the next call: the API needs its own blocks
/// (thinking included) to carry on the conversation.
class AiReply {
  const AiReply({required this.content, required this.stopReason, this.allowanceLeft});
  final List<Map<String, dynamic>> content;
  final String? stopReason;
  /// Share of this month's assistant allowance still left, 0-100.
  final int? allowanceLeft;

  String get text => [
        for (final b in content)
          if (b['type'] == 'text') (b['text'] as String? ?? '').trim()
      ].where((t) => t.isNotEmpty).join('\n\n');

  List<Map<String, dynamic>> get toolUses => [for (final b in content) if (b['type'] == 'tool_use') b];
}

/// What the app needs from the server; a fake stands in for it in tests.
abstract class AiBackend {
  /// Signed in to a FieldOS account (Team & sync), which the server needs.
  bool get signedIn;

  Future<AiReply> chat(List<Map<String, dynamic>> messages);

  /// Text of one WAV piece of at most 25 seconds.
  Future<String> transcribe(Uint8List wav, {String languageCode = 'unknown'});
}

class SupabaseAiBackend implements AiBackend {
  SupabaseAiBackend({required this.client, required this.subscriberId, this.timeout = const Duration(seconds: 100)});

  final SupabaseClient? client;

  /// This phone's RevenueCat customer, so the server can see the plan.
  final Future<String?> Function() subscriberId;
  final Duration timeout;

  static const functionName = 'ai-assistant';

  @override
  bool get signedIn => client?.auth.currentSession != null;

  @override
  Future<AiReply> chat(List<Map<String, dynamic>> messages) async {
    final data = await _call({'action': 'chat', 'messages': messages});
    return AiReply(
      content: [for (final b in (data['content'] as List? ?? const [])) Map<String, dynamic>.from(b as Map)],
      stopReason: data['stop_reason'] as String?,
      allowanceLeft: (data['allowance_left'] as num?)?.toInt(),
    );
  }

  @override
  Future<String> transcribe(Uint8List wav, {String languageCode = 'unknown'}) async {
    final data = await _call({'action': 'transcribe', 'audio_base64': base64Encode(wav), 'language_code': languageCode});
    return ((data['transcript'] as String?) ?? '').trim();
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body, {bool retried = false}) async {
    final c = client;
    if (c == null || c.auth.currentSession == null) {
      throw AiException('Sign in to Team & sync once to use the assistant.', code: 'signed_out');
    }
    final payload = {...body, 'subscriber_id': await subscriberId()};
    try {
      final res = await c.functions.invoke(functionName, body: payload).timeout(timeout);
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      if (data is String) return Map<String, dynamic>.from(jsonDecode(data) as Map);
      throw AiException('The assistant sent an answer the app could not read. Please try again.');
    } on FunctionException catch (e) {
      // An access token that ran out while the app sat idle: refresh once.
      if (e.status == 401 && !retried) {
        try {
          await c.auth.refreshSession();
          return _call(body, retried: true);
        } catch (_) {
          // Fall through to the server's own message.
        }
      }
      throw _fromServer(e);
    } on TimeoutException {
      throw AiException('The assistant took too long. Check your internet and try again.', code: 'timeout');
    } on SocketException {
      throw AiException('No internet. The assistant needs internet; everything else in FieldOS works offline.',
          code: 'offline');
    } on AiException {
      rethrow;
    } catch (e) {
      final s = e.toString();
      if (s.contains('SocketException') || s.contains('ClientException') || s.contains('Failed host lookup')) {
        throw AiException('No internet. The assistant needs internet; everything else in FieldOS works offline.',
            code: 'offline');
      }
      rethrow;
    }
  }

  static AiException _fromServer(FunctionException e) {
    var details = e.details;
    if (details is String) {
      try {
        details = jsonDecode(details);
      } catch (_) {}
    }
    if (details is Map && details['message'] is String) {
      return AiException(details['message'] as String, code: (details['error'] as String?) ?? 'error');
    }
    if (e.status == 404) {
      return AiException('The assistant is not switched on yet. Please try again later.', code: 'not_configured');
    }
    return AiException('The assistant could not answer just now (error ${e.status}). Please try again.');
  }
}
