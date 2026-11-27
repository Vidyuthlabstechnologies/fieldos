/// A crash before the app is up, or one that ends the app, is kept until it can
/// be reported (customer review: the worst moment to be blind is a start-up
/// failure, and the reporter needed the network and the app already running).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/services/bug_report_service.dart';

void main() {
  late Directory dir;
  late File file;
  final seen = <(Object, StackTrace?)>[];

  setUp(() {
    CrashLog.resetForTest();
    seen.clear();
    dir = Directory.systemTemp.createTempSync('crashes');
    file = File(p.join(dir.path, 'early_crashes.jsonl'));
  });
  tearDown(() {
    CrashLog.resetForTest();
    dir.deleteSync(recursive: true);
  });

  StackTrace stackAt(String where) => StackTrace.fromString(
      '#0      $where (package:fieldos_mobile/x.dart:10:5)\n#1      caller (package:fieldos_mobile/y.dart:3:1)\n#2      root (dart:async)');

  void attach() => CrashLog.sink = (e, s) => seen.add((e, s));

  test('a crash before the reporter exists is handed to it when it attaches, once and in order', () {
    CrashLog.record(StateError('first'), stackAt('Db.open'));
    CrashLog.record(ArgumentError('second'), stackAt('Providers.init'));
    expect(seen, isEmpty, reason: 'nothing to send it to yet');
    attach();
    expect(seen.map((c) => c.$1.toString()), ['Bad state: first', 'Invalid argument(s): second']);
    attach();
    expect(seen, hasLength(2), reason: 'attaching again does not replay them');
  });

  test('once attached, crashes go straight through', () {
    attach();
    CrashLog.record(StateError('live'), null);
    expect(seen, hasLength(1));
  });

  test('a crash while reporting a crash is still not reported again', () {
    CrashLog.sink = (e, s) {
      seen.add((e, s));
      CrashLog.record(StateError('inside'), null);
    };
    CrashLog.record(StateError('first'), null);
    expect(seen, hasLength(1));
  });

  test('only a few are kept for a reporter that never comes', () {
    for (var i = 0; i < 20; i++) {
      CrashLog.record(StateError('crash $i'), null);
    }
    attach();
    expect(seen, hasLength(CrashLog.maxWaiting));
    expect(seen.first.$1.toString(), contains('crash 0'), reason: 'the first ones, the cause, not the cascade');
  });

  test('a crash is written to the file at once, so one that kills the app is not lost', () {
    CrashLog.keepIn(file);
    CrashLog.record(StateError('before the first screen'), stackAt('Db.migrate'));
    expect(file.existsSync(), isTrue);
    final text = file.readAsStringSync();
    expect(text, contains('StateError'));
    expect(text, contains('before the first screen'));
    expect(text, contains('Db.migrate'));
  });

  test('the next start picks up what the last one left, and hands it to the reporter', () {
    CrashLog.keepIn(file);
    CrashLog.record(StateError('migration failed'), stackAt('Db.migrate'));
    // The app died here. Next launch, with nothing in memory:
    CrashLog.resetForTest();
    CrashLog.keepIn(file);
    attach();
    expect(seen, hasLength(1));
    expect(seen.single.$1, isA<SavedCrash>());
    expect((seen.single.$1 as SavedCrash).type, 'StateError');
    expect(seen.single.$1.toString(), 'Bad state: migration failed');
    expect(seen.single.$2.toString(), contains('Db.migrate'));
    expect(file.existsSync(), isFalse, reason: 'and the file is cleared so it is sent once');
  });

  test('crashes recorded before the file was known are written to it too', () {
    CrashLog.record(StateError('very early'), stackAt('main'));
    CrashLog.keepIn(file);
    expect(file.readAsStringSync(), contains('very early'));
  });

  test('a replayed crash has the same id and the same report text as the original', () {
    final original = StateError('no element');
    final st = stackAt('Dpr.save');
    final saved = SavedCrash('StateError', 'Bad state: no element');
    expect(crashHash(saved, st), crashHash(original, st), reason: 'one issue, however many phones and restarts');
    expect(crashHash(SavedCrash('ArgumentError', 'x'), st), isNot(crashHash(saved, st)));
  });

  test('a replayed crash becomes a bug report that names the original error type', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final s = BugReportService(db: db, client: null);
    final made = await s.reportCrash(const SavedCrash('StateError', 'Bad state: no element'), stackAt('Dpr.save'),
        appVersion: '1.8.2+27', platform: 'android 14');
    expect(made, isTrue);
    expect(await s.pendingCount(), 1);
    final queued = (await db.settingsDao.get('pending_bug_reports'))!;
    expect(queued, contains('StateError: Bad state: no element'));
    expect(queued, isNot(contains('SavedCrash')));
  });

  test('a file that cannot be written or read never throws into the crash handler', () {
    CrashLog.keepIn(File(p.join(dir.path, 'no', 'such', 'folder', 'early.jsonl')));
    expect(() => CrashLog.record(StateError('x'), null), returnsNormally);
    file.writeAsStringSync('this is not json\n{"type":"StateError","message":"kept","stack":""}\n');
    CrashLog.resetForTest();
    CrashLog.keepIn(file);
    attach();
    expect(seen.map((c) => c.$1.toString()), ['kept'], reason: 'the damaged line is skipped, the good one survives');
  });
}
