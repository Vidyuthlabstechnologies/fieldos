/// In-app bug reports. A report goes straight to the cloud's bug_reports
/// table (anyone may insert, nobody may read back), and the report-to-github
/// edge function turns each one into an issue for the team to fix. If the phone
/// is offline the report waits on the phone and is sent on the next try.
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

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

/// Uncaught errors go here as well as to [RecentErrors] (issue #153). The
/// app points [sink] at [BugReportService.reportCrash] once it starts, so a
/// crash is saved on the phone and sent as a bug report when online.
///
/// A crash before the app is up (the database that would hold a report cannot
/// open, a provider fails on start) used to be dropped, because there was no
/// [sink] yet, and so was one that killed the app before it could be sent.
/// Such crashes are now kept, in memory and in a small file ([keepIn]), and
/// handed to the sink as soon as it exists, this run or the next. Crashes that
/// end the process with no Dart error (a native crash, an ANR) still need a
/// native reporter and are not covered.
class CrashLog {
  CrashLog._();

  static void Function(Object error, StackTrace? stack)? _sink;
  static void Function(Object error, StackTrace? stack)? get sink => _sink;
  static set sink(void Function(Object error, StackTrace? stack)? s) {
    _sink = s;
    if (s != null) _replay();
  }

  static bool _busy = false;
  static final _waiting = <(Object, StackTrace?)>[];
  static File? _file;

  /// Most crashes kept for a sink that does not exist yet.
  static const maxWaiting = 5;

  /// Also keeps early crashes in [file], and picks up what a previous run left
  /// there. Call once, as early as the app's folder can be found.
  static void keepIn(File file) {
    _file = file;
    try {
      if (file.existsSync()) {
        for (final line in file.readAsLinesSync()) {
          try {
            final j = jsonDecode(line) as Map<String, dynamic>;
            if (_waiting.length < maxWaiting) {
              _waiting.add((SavedCrash(j['type'] as String? ?? 'Error', j['message'] as String? ?? ''),
                  StackTrace.fromString(j['stack'] as String? ?? '')));
            }
          } catch (_) {}
        }
        file.deleteSync();
      }
      // What happened before the file was known.
      for (final (error, stack) in _waiting) {
        _persist(error, stack);
      }
    } catch (_) {}
    if (_sink != null) _replay();
  }

  static void record(Object error, StackTrace? stack) {
    final s = _sink;
    if (s == null) {
      if (_waiting.length < maxWaiting) {
        _waiting.add((error, stack));
        _persist(error, stack);
      }
      return;
    }
    if (_busy) return; // never report a failure of the reporting itself
    _busy = true;
    try {
      s(error, stack);
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  static void _persist(Object error, StackTrace? stack) {
    final f = _file;
    if (f == null) return;
    try {
      final type = error is SavedCrash ? error.type : error.runtimeType.toString();
      final message = error.toString();
      f.writeAsStringSync(
        '${jsonEncode({
          'type': type,
          'message': message.length > 500 ? message.substring(0, 500) : message,
          'stack': (stack?.toString() ?? '').split('\n').take(12).join('\n'),
        })}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

  static void _replay() {
    if (_waiting.isEmpty) return;
    final early = [..._waiting];
    _waiting.clear();
    try {
      _file?.deleteSync();
    } catch (_) {}
    for (final (error, stack) in early) {
      record(error, stack);
    }
  }

  /// Back to a fresh start, for tests.
  static void resetForTest() {
    _sink = null;
    _busy = false;
    _file = null;
    _waiting.clear();
  }
}

/// A crash read back from the file a previous run left. Its [type] is what the
/// error was called then, so the report and its id read as the original's.
class SavedCrash implements Exception {
  const SavedCrash(this.type, this.message);
  final String type;
  final String message;
  @override
  String toString() => message;
}

/// A short, stable id for a crash: the error's type and its first three
/// stack frames, so the same crash on many phones is one issue.
String crashHash(Object error, StackTrace? stack) {
  final frames = (stack?.toString() ?? '')
      .split('\n')
      .map((l) => l.replaceFirst(RegExp(r'^#\d+\s+'), '').trim())
      .where((l) => l.isNotEmpty)
      .take(3)
      .join('|');
  var h = 0x811c9dc5;
  for (final c in '${error is SavedCrash ? error.type : error.runtimeType}|$frames'.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
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

  static const crashSettingKey = 'send_crash_details';
  static const _crashHashesKey = 'crash_hashes_sent';

  /// "Send crash details" in Settings; on unless turned off.
  Future<bool> crashReportsOn() async => (await db.settingsDao.get(crashSettingKey)) != '0';

  Future<void> setCrashReports(bool on) => db.settingsDao.set(crashSettingKey, on ? '1' : '0');

  /// Sends (or keeps for [flush]) one report for an uncaught error, once
  /// per kind of crash on this phone. No project data: only the error,
  /// where it happened, and the app and phone versions. Returns whether a
  /// report was made.
  Future<bool> reportCrash(Object error, StackTrace? stack,
      {required String appVersion, required String platform}) async {
    if (!await crashReportsOn()) return false;
    final hash = crashHash(error, stack);
    final raw = await db.settingsDao.get(_crashHashesKey);
    final sent = raw == null || raw.isEmpty ? <String>[] : [for (final v in jsonDecode(raw) as List) v as String];
    if (sent.contains(hash)) return false;
    sent.add(hash);
    await db.settingsDao.set(_crashHashesKey, jsonEncode(sent.length > 50 ? sent.sublist(sent.length - 50) : sent));
    final firstLine = error.toString().split('\n').first;
    final frames = (stack?.toString() ?? '').split('\n').take(12).join('\n');
    await submit(BugReport(
      message: '[crash $hash] ${error is SavedCrash ? error.type : error.runtimeType}: ${firstLine.length > 200 ? firstLine.substring(0, 200) : firstLine}',
      appVersion: appVersion,
      platform: platform,
      recentErrors: '$error\n$frames',
    ));
    return true;
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
