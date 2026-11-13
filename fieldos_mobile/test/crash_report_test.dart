/// Crash reports (issue #153): an uncaught error becomes one bug report per
/// kind of crash, kept on the phone while offline, and nothing is sent when
/// "Send crash details" is off.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/services/bug_report_service.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  StackTrace stackAt(String where) => StackTrace.fromString(
      '#0      $where (package:fieldos_mobile/x.dart:10:5)\n#1      caller (package:fieldos_mobile/y.dart:3:1)\n#2      root (dart:async)');

  test('the same crash has the same id; a different place has another', () {
    final a = crashHash(StateError('no element'), stackAt('Dpr.save'));
    expect(crashHash(StateError('other text'), stackAt('Dpr.save')), a, reason: 'the message may vary');
    expect(crashHash(StateError('no element'), stackAt('Wages.total')), isNot(a));
    expect(crashHash(ArgumentError('x'), stackAt('Dpr.save')), isNot(a));
    expect(a, matches(RegExp(r'^[0-9a-f]{8}$')));
  });

  test('a crash is kept as a bug report while offline, once per kind of crash', () async {
    final s = BugReportService(db: db, client: null);
    expect(await s.crashReportsOn(), isTrue, reason: 'on unless turned off');
    final made = await s.reportCrash(StateError('Bad state: no element'), stackAt('Dpr.save'),
        appVersion: '1.7.5+20', platform: 'android 14');
    expect(made, isTrue);
    expect(await s.reportCrash(StateError('Bad state: no element'), stackAt('Dpr.save'),
        appVersion: '1.7.5+20', platform: 'android 14'), isFalse);
    expect(await s.pendingCount(), 1);
  });

  test('nothing is sent when Send crash details is off', () async {
    final s = BugReportService(db: db, client: null);
    await s.setCrashReports(false);
    expect(await s.reportCrash(StateError('x'), stackAt('a'), appVersion: '1', platform: 'p'), isFalse);
    expect(await s.pendingCount(), 0);
  });

  test('a crash while reporting a crash is not reported again', () {
    var calls = 0;
    CrashLog.sink = (e, s) {
      calls++;
      CrashLog.record(StateError('inside'), null);
    };
    addTearDown(() => CrashLog.sink = null);
    CrashLog.record(StateError('first'), null);
    expect(calls, 1);
  });
}
