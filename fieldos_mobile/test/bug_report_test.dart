/// Bug reports: offline queueing on the phone, and the cloud rules (anyone
/// can send, nobody but the service role can read them back or pre-mark
/// them as filed). The cloud half skips itself if the local stack is down.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/services/bug_report_service.dart';
import 'package:fieldos_mobile/sync/sync_config.dart';

Future<bool> _localStackReachable() async {
  try {
    final res = await http.get(Uri.parse('${SyncConfig.local.url}/rest/v1/')).timeout(const Duration(seconds: 2));
    return res.statusCode < 500;
  } catch (_) {
    return false;
  }
}

BugReport _report(String msg) =>
    BugReport(message: msg, appVersion: '1.3.0+5', platform: 'android test', recentErrors: RecentErrors.dump());

void main() {
  test('RecentErrors keeps only the last 10', () {
    RecentErrors.clearForTest();
    expect(RecentErrors.dump(), isNull);
    for (var i = 0; i < 15; i++) {
      RecentErrors.record('boom $i', StackTrace.current);
    }
    final dump = RecentErrors.dump()!;
    expect(dump.split('\n---\n'), hasLength(10));
    expect(dump, contains('boom 14'));
    expect(dump, isNot(contains('boom 4\n')));
  });

  test('a report with no cloud is queued, kept across restarts and sent by flush', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final offline = BugReportService(db: db, client: null);
    expect(await offline.submit(_report('The DPR share button does nothing')), BugReportOutcome.queued);
    expect(await offline.submit(_report('Map is blank on my phone')), BugReportOutcome.queued);
    expect(await offline.pendingCount(), 2);
    expect(await offline.flush(), 0);
    expect(await offline.pendingCount(), 2, reason: 'still offline, nothing lost');
  });

  group('cloud', () {
    late bool stackUp;
    setUpAll(() async => stackUp = await _localStackReachable());

    test('anyone can send; nobody but the service role can read or pre-file', () async {
      if (!stackUp) {
        markTestSkipped('local Supabase stack not running');
        return;
      }
      final marker = 'bug-${const Uuid().v4()}';
      final anon = SyncConfig.local.createClient();
      addTearDown(anon.dispose);
      final db = AppDatabase.memory();
      addTearDown(db.close);

      // queued while offline, then flushed once a cloud is there
      final offline = BugReportService(db: db, client: null);
      await offline.submit(_report('$marker queued while offline'));
      final online = BugReportService(db: db, client: anon);
      expect(await online.flush(), 1);
      expect(await online.pendingCount(), 0);
      expect(await online.submit(_report('$marker sent directly')), BugReportOutcome.sent);

      // anon reads nothing back
      final seen = await anon.from('bug_reports').select().like('message', '$marker%');
      expect(seen, isEmpty);

      // a client can't mark its own report as already filed (would hide it)
      await expectLater(
        anon.from('bug_reports').insert({'message': '$marker sneaky', 'github_issue': 1}),
        throwsA(isA<PostgrestException>()),
      );
      // or attribute it to someone else
      await expectLater(
        anon.from('bug_reports').insert({'message': '$marker spoofed', 'user_id': const Uuid().v4()}),
        throwsA(isA<PostgrestException>()),
      );

      final admin = SupabaseClient(SyncConfig.local.url, localServiceRoleKey);
      addTearDown(admin.dispose);
      final rows = await admin.from('bug_reports').select()
          .like('message', '$marker%');
      expect([for (final r in rows) r['message']], unorderedEquals(['$marker queued while offline', '$marker sent directly']));
      expect(rows.first['app_version'], '1.3.0+5');
      expect(rows.first['github_issue'], isNull);
      await admin.from('bug_reports').delete().like('message', '$marker%');
    });
  });
}
