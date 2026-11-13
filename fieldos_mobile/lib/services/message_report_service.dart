/// "Report this message" in project chat. The report goes to the cloud's
/// message_reports table (members may insert, nobody may read back) and the
/// FieldOS team reviews it. The phone remembers what it reported, so the
/// message stays hidden for the reporter.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/services/report_filing.dart';

enum ReportReason { abuse, spam, inappropriate, other }

class MessageReportException implements Exception {
  MessageReportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class MessageReportService {
  MessageReportService({required this.db, required this.client});

  final AppDatabase db;
  final SupabaseClient? client;
  static const _reportedKey = 'reported_messages';

  Future<Set<String>> reportedIds() async {
    final raw = await db.settingsDao.get(_reportedKey);
    if (raw == null || raw.isEmpty) return {};
    return {for (final v in jsonDecode(raw) as List) v as String};
  }

  Future<void> _remember(String messageId) async {
    final ids = await reportedIds()
      ..add(messageId);
    await db.settingsDao.set(_reportedKey, jsonEncode(ids.toList()));
  }

  /// Sends the report. Throws [MessageReportException] with a message for
  /// the screen when it can't be sent.
  Future<void> report({required String messageId, required ReportReason reason, String? details}) async {
    final c = client;
    if (c == null || c.auth.currentUser == null) {
      throw MessageReportException('Sign in under Team & sync to report a message.');
    }
    final text = details?.trim();
    try {
      await c.from('message_reports').insert({
        'message_id': messageId,
        'reason': reason.name,
        'details': text == null || text.isEmpty ? null : (text.length > 1000 ? text.substring(0, 1000) : text),
      });
    } on PostgrestException catch (e) {
      // Already reported by this person: that's a success for them.
      if (e.code != '23505') {
        throw MessageReportException(
            'The report did not go through. Please try again in a minute, or write to info@mldynamic.com.');
      }
    } catch (e) {
      final offline = e is SocketException || e is TimeoutException || e.toString().contains('ClientException');
      throw MessageReportException(offline
          ? 'No internet connection. Connect and try again.'
          : 'The report did not go through. Please try again in a minute, or write to info@mldynamic.com.');
    }
    nudgeReportFiling(c);
    await _remember(messageId);
  }
}
