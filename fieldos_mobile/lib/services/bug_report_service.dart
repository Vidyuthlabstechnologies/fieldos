/// In-app bug reports. A report goes straight to the cloud's bug_reports
/// table (anyone may insert, nobody may read back), and the report-to-github
/// edge function turns each one into an issue for the team to fix. If the phone
/// is offline the report waits on the phone and is sent on the next try.
library;

import 'dart:collection';
import 'dart:convert';

import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/services/report_filing.dart';

/// The last few errors the app hit, attached to a bug report so a fix
/// doesn't depend on the reporter describing a stack trace.
class RecentErrors {
  RecentErrors._();
  static final _items = ListQueue<String>();

  static void record(Object error, StackTrace? stack) {
    final firstFrames = (stack?.toString() ?? '').split('\n').take(6).join('\n');
    _items.addLast('${DateTime.now().toUtc().toIso8601String()} $error\n$firstFrames');
    while (_items.length > 10) {
      _items.removeFirst();
    }
  }

  static String? dump() => _items.isEmpty ? null : _items.join('\n---\n');

  static void clearForTest() => _items.clear();
}

class BugReport {
  const BugReport({required this.message, this.contactEmail, required this.appVersion, required this.platform, this.recentErrors});

  final String message;
  final String? contactEmail;
  final String appVersion;
  final String platform;
  final String? recentErrors;

  Map<String, dynamic> toJson() => {
        'message': message,
        'contact_email': (contactEmail == null || contactEmail!.isEmpty) ? null : contactEmail,
        'app_version': appVersion,
        'platform': platform.length > 200 ? platform.substring(0, 200) : platform,
        'recent_errors': recentErrors == null || recentErrors!.length <= 8000 ? recentErrors : recentErrors!.substring(0, 8000),
      };

  static BugReport fromJson(Map<String, dynamic> j) => BugReport(
        message: j['message'] as String,
        contactEmail: j['contact_email'] as String?,
        appVersion: j['app_version'] as String,
        platform: j['platform'] as String,
        recentErrors: j['recent_errors'] as String?,
      );
}

enum BugReportOutcome { sent, queued }

class BugReportService {
  BugReportService({required this.db, required this.client});

  final AppDatabase db;
  final SupabaseClient? client;
  static const _queueKey = 'pending_bug_reports';

  Future<List<BugReport>> _queue() async {
    final raw = await db.settingsDao.get(_queueKey);
    if (raw == null || raw.isEmpty) return [];
    return [for (final j in jsonDecode(raw) as List) BugReport.fromJson(Map<String, dynamic>.from(j as Map))];
  }

  Future<void> _save(List<BugReport> q) =>
      db.settingsDao.set(_queueKey, q.isEmpty ? '' : jsonEncode([for (final r in q) r.toJson()]));

  Future<int> pendingCount() async => (await _queue()).length;

  Future<void> _send(BugReport r) async {
    final c = client;
    if (c == null) throw StateError('no cloud configured');
    await c.from('bug_reports').insert(r.toJson());
    nudgeReportFiling(c);
  }

  /// Sends now if possible, otherwise keeps it for [flush].
  Future<BugReportOutcome> submit(BugReport r) async {
    try {
      await _send(r);
      return BugReportOutcome.sent;
    } catch (_) {
      await _save([...await _queue(), r]);
      return BugReportOutcome.queued;
    }
  }

  /// Sends reports that were written offline. Call on app start / resume.
  Future<int> flush() async {
    final q = await _queue();
    if (q.isEmpty) return 0;
    final left = <BugReport>[];
    var sent = 0;
    for (final r in q) {
      try {
        await _send(r);
        sent++;
      } catch (_) {
        left.add(r);
      }
    }
    await _save(left);
    return sent;
  }
}
