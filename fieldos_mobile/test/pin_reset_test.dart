/// Forgot PIN: the PIN can only be reset after signing in to the cloud
/// account again, and until then the wrong-PIN count and wait stand. A
/// phone with no cloud session may sign in to the account its data was
/// linked to (and to no other), or erase itself after the typed word.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Table;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/auth/apple_auth.dart';
import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/auth/google_auth.dart';
import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/data/erase_phone.dart';
import 'package:fieldos_mobile/features/reminders/reminders.dart' show PlannedReminder;
import 'package:fieldos_mobile/features/security/app_lock.dart';
import 'package:fieldos_mobile/features/security/pin_reset.dart';
import 'package:fieldos_mobile/features/tasks/team_roster.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/notification_service.dart';
import 'package:fieldos_mobile/sync/cloud_sync_bootstrap.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_service.dart';
import 'package:fieldos_mobile/sync/sync_engine.dart';

/// Signing in again, scripted: [account] null is a phone with no cloud
/// account it can reach and no data linked to one.
class FakeReauth implements AccountReauth {
  FakeReauth({this.account_, this.reply = ReauthOutcome.ok});
  ReauthAccount? account_;
  ReauthOutcome reply;
  final calls = <String>[];

  @override
  Future<ReauthAccount?> account() async => account_;
  @override
  Future<ReauthOutcome> password(String password) async {
    calls.add('password:$password');
    return password == 'right-password' ? ReauthOutcome.ok : reply;
  }

  @override
  Future<ReauthOutcome> sendEmailCode() async {
    calls.add('send');
    return ReauthOutcome.ok;
  }

  @override
  Future<ReauthOutcome> emailCode(String code) async {
    calls.add('code:$code');
    return code == '123456' ? ReauthOutcome.ok : reply;
  }

  @override
  Future<ReauthOutcome> google() async {
    calls.add('google');
    return reply;
  }

  @override
  Future<ReauthOutcome> apple() async {
    calls.add('apple');
    return reply;
  }
}

const _all = ReauthAccount(
  email: 'ravi@example.com',
  methods: [ReauthMethod.password, ReauthMethod.google, ReauthMethod.emailCode],
);

/// No session on the phone; its data was linked to this account.
const _linked = ReauthAccount(
  signedIn: false,
  email: 'ravi@example.com',
  methods: [ReauthMethod.password, ReauthMethod.emailCode],
);

/// A JWT with [claims] and a fake signature: gotrue only reads it.
String _jwt(Map<String, Object?> claims) {
  String part(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part(claims)}.c2ln';
}

Map<String, Object?> _session(String userId, String email, {List<String> providers = const ['email']}) {
  final exp = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
  return {
    'access_token': _jwt({'sub': userId, 'email': email, 'exp': exp}),
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': 'refresh-$userId',
    'user': {
      'id': userId,
      'aud': 'authenticated',
      'email': email,
      'created_at': '2026-11-01T00:00:00Z',
      'app_metadata': {'provider': providers.first, 'providers': providers},
      'user_metadata': <String, Object?>{},
    },
  };
}

class _MemoryStore implements SessionStore {
  String? saved;
  @override
  Future<String?> read() async => saved;
  @override
  Future<void> write(String? sessionJson) async => saved = sessionJson;
}

class _FakeNotifications extends NotificationService {
  List<Object>? cleared;
  @override
  Future<void> replaceScheduled(List<PlannedReminder> plan) async => cleared = plan;
}

void main() {
  final t0 = DateTime(2026, 11, 14, 10);

  group('PinReset steps', () {
    late AppDatabase db;
    late DateTime now;
    late AppLock lock;
    late int erased;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      now = t0;
      lock = AppLock(db, clock: () => now);
      erased = 0;
      await lock.setPin('2580');
      // Six wrong PINs: the 60 s wait started at t0.
      await db.settingsDao.set(appLockFailsKey, '6');
      await db.settingsDao.set(appLockLockedAtKey, '${t0.millisecondsSinceEpoch}');
    });
    tearDown(() async {
      setCurrentLanguage(AppLanguage.en);
      await db.close();
    });

    PinReset reset(AccountReauth reauth) => PinReset(lock: lock, reauth: reauth, erase: () async => erased++);

    Future<void> expectStillLocked() async {
      final s = await lock.lockout();
      expect(s.fails, 6, reason: 'the count stands');
      expect(s.lockedAt, t0, reason: 'and so does the wait');
      expect(s.remaining(now), const Duration(seconds: 60));
      expect(await lock.check('2580'), isTrue, reason: 'the old PIN is kept');
    }

    test('no session and data never linked: no sign-in, only erase; the wait stands', () async {
      final r = reset(FakeReauth());
      await r.start();
      expect(r.step, PinResetStep.noSession);
      expect(r.canSignIn, isFalse);
      r.signInToKeep();
      expect(r.step, PinResetStep.noSession, reason: 'no account the data could be proved by');
      await expectLater(r.setPin('1357'), throwsStateError);
      for (final m in ReauthMethod.values) {
        await r.choose(m);
      }
      expect(r.step, PinResetStep.noSession);
      await expectStillLocked();
      expect(erased, 0);
    });

    test('erasing needs the exact word; Cancel and wrong words erase nothing', () async {
      final r = reset(FakeReauth());
      await r.start();
      expect(await r.confirmErase('ERASE'), isFalse, reason: 'not before the warning');
      r.startErase();
      expect(r.step, PinResetStep.erase);
      for (final w in ['', ' ', 'ERAS', 'ERASED', 'ERASE NOW', 'DELETE', 'E R A S E', 'ERASE.']) {
        expect(await r.confirmErase(w), isFalse, reason: w);
      }
      r.back();
      expect(r.step, PinResetStep.noSession);
      expect(await r.confirmErase('ERASE'), isFalse, reason: 'Cancel leaves the erase screen');
      expect(erased, 0);
      await expectStillLocked();

      r.startErase();
      expect(await r.confirmErase('  Erase '), isTrue);
      expect(r.step, PinResetStep.erased);
      expect(erased, 1);
      await expectLater(r.setPin('1357'), throwsStateError);
    });

    test('a failed erase says so and stays on the erase screen', () async {
      final r = PinReset(lock: lock, reauth: FakeReauth(), erase: () async => throw const FileSystemException('busy'));
      await r.start();
      r.startErase();
      expect(await r.confirmErase('ERASE'), isFalse);
      expect(r.eraseFailed, isTrue);
      expect(r.step, PinResetStep.erase);
    });

    test('signed in to the cloud: erase is not offered', () async {
      final r = reset(FakeReauth(account_: _all));
      await r.start();
      expect(r.step, PinResetStep.choose);
      r.startErase();
      expect(r.step, PinResetStep.choose);
      expect(await r.confirmErase('ERASE'), isFalse);
      expect(erased, 0);
    });

    test('no session, data linked: sign in to that account to keep the data', () async {
      final r = reset(FakeReauth(account_: _linked, reply: ReauthOutcome.wrongAccount));
      await r.start();
      expect(r.step, PinResetStep.noSession);
      expect(r.canSignIn, isTrue);
      r.signInToKeep();
      expect(r.step, PinResetStep.choose);
      r.back();
      expect(r.step, PinResetStep.noSession, reason: 'back to the two choices');
      r.signInToKeep();
      await r.choose(ReauthMethod.password);
      await r.submitPassword('someone else');
      expect(r.error, ReauthOutcome.wrongAccount);
      await expectStillLocked();
      await r.submitPassword('right-password');
      expect(r.step, PinResetStep.newPin);
      await r.setPin('1357');
      expect(await lock.check('1357'), isTrue);
      expect(erased, 0);
    });

    test('a new PIN cannot be set before signing in again', () async {
      final r = reset(FakeReauth(account_: _all));
      await r.start();
      expect(r.step, PinResetStep.choose);
      await expectLater(r.setPin('1357'), throwsStateError);
      await r.choose(ReauthMethod.password);
      await expectLater(r.setPin('1357'), throwsStateError);
      await expectStillLocked();
    });

    test('a wrong password, or no internet, changes nothing', () async {
      final fake = FakeReauth(account_: _all, reply: ReauthOutcome.wrong);
      final r = reset(fake);
      await r.start();
      await r.choose(ReauthMethod.password);
      await r.submitPassword('guess');
      expect(r.step, PinResetStep.password);
      expect(r.error, ReauthOutcome.wrong);
      await expectStillLocked();

      fake.reply = ReauthOutcome.offline;
      await r.submitPassword('guess again');
      expect(r.error, ReauthOutcome.offline);
      expect(r.step, PinResetStep.password);
      await expectStillLocked();
    });

    test('the right password clears the count; then a new PIN is set', () async {
      final r = reset(FakeReauth(account_: _all));
      await r.start();
      await r.choose(ReauthMethod.password);
      await r.submitPassword('right-password');
      expect(r.step, PinResetStep.newPin);
      expect(await lock.lockout(), PinLockout.none);
      r.back();
      expect(r.step, PinResetStep.newPin, reason: 'no way back past the sign-in');
      await r.setPin('1357');
      expect(r.step, PinResetStep.done);
      expect(await lock.check('1357'), isTrue);
      expect(await lock.check('2580'), isFalse);
    });

    test('email code: sent on choosing it; a wrong code changes nothing; the right one lets a PIN be set', () async {
      final fake = FakeReauth(account_: _all, reply: ReauthOutcome.wrong);
      final r = reset(fake);
      await r.start();
      await r.choose(ReauthMethod.emailCode);
      expect(fake.calls, ['send']);
      expect(r.codeSent, isTrue);
      await r.submitCode('000000');
      expect(r.error, ReauthOutcome.wrong);
      await expectStillLocked();
      await r.submitCode('123456');
      expect(r.step, PinResetStep.newPin);
      expect(await lock.lockout(), PinLockout.none);
    });

    test('Google: closing the picker or picking another account changes nothing', () async {
      final fake = FakeReauth(account_: _all, reply: ReauthOutcome.cancelled);
      final r = reset(fake);
      await r.start();
      await r.choose(ReauthMethod.google);
      expect(r.step, PinResetStep.choose);
      expect(r.error, isNull);
      fake.reply = ReauthOutcome.wrongAccount;
      await r.choose(ReauthMethod.google);
      expect(r.error, ReauthOutcome.wrongAccount);
      await expectStillLocked();
      fake.reply = ReauthOutcome.ok;
      await r.choose(ReauthMethod.google);
      expect(r.step, PinResetStep.newPin);
      expect(await lock.lockout(), PinLockout.none);
    });

    test('Back from a method returns to the list, with the wait still on', () async {
      final r = reset(FakeReauth(account_: _all));
      await r.start();
      await r.choose(ReauthMethod.password);
      r.back();
      expect(r.step, PinResetStep.choose);
      await expectStillLocked();
    });
  });

  group('The confirmation word', () {
    tearDown(() => setCurrentLanguage(AppLanguage.en));

    test('English: ERASE, any capitals, spaces around it; nothing else', () {
      expect(eraseConfirmWord(), 'ERASE');
      for (final w in ['ERASE', 'erase', 'Erase', ' ERASE ', 'ERA​SE']) {
        expect(eraseWordMatches(w), isTrue, reason: w);
      }
      for (final w in ['', 'ERAS', 'ERASED', 'RASE', 'ERASE ERASE', 'DELETE', 'मिटाएं']) {
        expect(eraseWordMatches(w), isFalse, reason: w);
      }
    });

    test('every language has its own word, and ERASE always works too', () {
      for (final lang in AppLanguage.values) {
        setCurrentLanguage(lang);
        final word = eraseConfirmWord();
        expect(word.trim(), isNotEmpty, reason: lang.name);
        expect(word, isNot(contains(' ')), reason: '${lang.name}: one word');
        expect(eraseWordMatches(word), isTrue, reason: lang.name);
        expect(eraseWordMatches('ERASE'), isTrue, reason: lang.name);
        expect(eraseWordMatches(word.substring(0, word.length - 1)), isFalse, reason: lang.name);
      }
    });

    test('the same word from another keyboard counts; another language\'s word does not', () {
      setCurrentLanguage(AppLanguage.hi);
      expect(eraseConfirmWord(), 'मिटाएं');
      expect(eraseWordMatches('मिटाएँ'), isTrue, reason: 'candrabindu for anusvara');
      expect(eraseWordMatches('मिटा‍एं'), isTrue, reason: 'a joiner');
      expect(eraseWordMatches('తొలగించు'), isFalse, reason: 'the Telugu word');

      setCurrentLanguage(AppLanguage.ro);
      expect(eraseWordMatches('ȘTERGE'), isTrue);
      expect(eraseWordMatches('ştergE'), isTrue, reason: 's with cedilla');
      expect(eraseWordMatches('STERGE'), isFalse, reason: 'a different letter');

      setCurrentLanguage(AppLanguage.ur);
      expect(eraseWordMatches('مٹائیں'), isTrue);
      expect(eraseWordMatches('مٹائيں'), isTrue, reason: 'Arabic yeh from an Arabic keyboard');

      setCurrentLanguage(AppLanguage.pl);
      expect(eraseWordMatches('wymaż'), isTrue);
      expect(eraseWordMatches('WYMAZ'), isFalse);
    });
  });

  group('PhoneEraser', () {
    late Directory root;
    late Directory docs;
    late Directory tmp;
    late AppDatabase db;

    setUp(() {
      root = Directory.systemTemp.createTempSync('erase');
      docs = Directory(p.join(root.path, 'docs'))..createSync();
      tmp = Directory(p.join(root.path, 'tmp'))..createSync();
      db = AppDatabase(NativeDatabase.memory());
    });
    tearDown(() async {
      await db.close();
      root.deleteSync(recursive: true);
    });

    test('every record and setting, and every file but the open database, goes', () async {
      await AuthService(db).register(username: 'ravi', name: 'Ravi', password: 'pw123456');
      await AppLock(db).setPin('2580');
      await db.settingsDao.set('cloud_session', '{"refresh_token":"r"}');
      final dbPath = p.join(docs.path, 'fieldos.sqlite');
      for (final f in ['fieldos.sqlite', 'fieldos.sqlite-wal', 'fieldos.sqlite.before-restore', 'fieldos.sqlite.restore']) {
        File(p.join(docs.path, f)).writeAsStringSync('db');
      }
      File(p.join(docs.path, 'media', 'dpr', 'photo.jpg'))
        ..createSync(recursive: true)
        ..writeAsStringSync('jpg');
      File(p.join(docs.path, 'media', 'documents', 'drawing.pdf'))
        ..createSync(recursive: true)
        ..writeAsStringSync('pdf');
      File(p.join(tmp.path, 'FieldOS-backup.zip')).writeAsStringSync('zip');

      // Read-only mode refuses the person's changes, not the erase.
      db.writeGuard.reason = ReadOnlyReason.offlineTooLong;
      await PhoneEraser(db, databasePath: () async => dbPath, folders: () async => [docs, tmp]).erase();

      for (final t in db.allTables) {
        expect(await db.select(t).get(), isEmpty, reason: t.actualTableName);
      }
      expect(await AppLock(db).isOn(), isFalse);
      expect(docs.listSync().map((e) => p.basename(e.path)).toSet(), {'fieldos.sqlite', 'fieldos.sqlite-wal'});
      expect(tmp.listSync(), isEmpty);
    });
  });

  group('linked cloud account', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('only when a company on the phone was put on the cloud, with the account that synced it', () async {
      expect(await linkedCloudAccount(db), isNull);
      await saveRoster(db, 'c1', const [CloudMember(userId: 'u-ravi', email: 'ravi@example.com', role: 'owner')],
          myUserId: 'u-ravi');
      expect(await linkedCloudAccount(db), isNull, reason: 'no company linked');
      await CloudLinks(db).link('c1');
      expect(await linkedCloudAccount(db), (userId: 'u-ravi', email: 'ravi@example.com'));

      // A phone from before the email was kept finds it in the team list.
      await db.settingsDao.set(cloudUserEmailKey, '');
      expect(await linkedCloudAccount(db), (userId: 'u-ravi', email: 'ravi@example.com'));

      await recordLinkedAccount(db, userId: 'u-ravi', email: 'ravi@new.com');
      expect((await linkedCloudAccount(db))!.email, 'ravi@new.com');

      // Deleting the cloud account unlinks the companies.
      await CloudLinks(db).clear();
      expect(await linkedCloudAccount(db), isNull);
    });
  });

  group('CloudSyncService re-authentication', () {
    late AppDatabase db;
    late List<http.Request> sent;
    late http.Response Function(http.Request) server;

    CloudSyncService service({SessionStore? store}) {
      SupabaseClient make() {
        final client = SupabaseClient(
          'http://supabase.test',
          'anon',
          httpClient: MockClient((req) async {
            sent.add(req);
            return server(req);
          }),
          // As SyncConfig builds it.
          authOptions: const AuthClientOptions(autoRefreshToken: false, authFlowType: AuthFlowType.implicit),
        );
        return client;
      }

      final client = make();
      addTearDown(client.dispose);
      return CloudSyncService(
        client: client,
        engine: SyncEngine(db: db, client: client),
        sessionStore: store,
        freshClient: make,
      );
    }

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      sent = [];
      server = (_) => http.Response('{}', 500);
    });
    tearDown(() => db.close());

    Future<CloudSyncService> signedIn({List<String> providers = const ['email']}) async {
      final s = service();
      await s.client.auth.recoverSession(jsonEncode(_session('u-ravi', 'ravi@example.com', providers: providers)));
      expect(s.isSignedIn, isTrue);
      return s;
    }

    test('lists every way the account signs in', () async {
      final s = await signedIn(providers: ['email', 'google']);
      expect(s.signInProviders, ['email', 'google']);
      final reauth = CloudAccountReauth(cloud: s, googlePicker: _Google(true), applePicker: _Apple(false));
      final a = (await reauth.account())!;
      expect(a.email, 'ravi@example.com');
      expect(a.signedIn, isTrue);
      expect(a.methods, [ReauthMethod.password, ReauthMethod.google, ReauthMethod.emailCode]);
    });

    test('Google- or Apple-only accounts get their provider and the email code, not a password', () async {
      final s = await signedIn(providers: ['apple']);
      final reauth = CloudAccountReauth(cloud: s, googlePicker: _Google(true), applePicker: _Apple(true));
      expect((await reauth.account())!.methods, [ReauthMethod.apple, ReauthMethod.emailCode]);
    });

    test('no session and nothing linked: no account, nothing sent', () async {
      final s = service();
      final reauth = CloudAccountReauth(
          cloud: s, googlePicker: _Google(true), applePicker: _Apple(true), linked: () async => null);
      expect(await reauth.account(), isNull);
      expect(await s.reauthWithPassword('x'), ReauthOutcome.noSession);
      expect(await CloudAccountReauth(cloud: null, googlePicker: _Google(true), applePicker: _Apple(true)).account(),
          isNull);
      expect(sent, isEmpty);
    });

    test('password: the server refusing it is "wrong", no answer is "offline"', () async {
      final s = await signedIn();
      server = (_) => http.Response(jsonEncode({'code': 'invalid_credentials', 'msg': 'Invalid login credentials'}), 400);
      expect(await s.reauthWithPassword('guess'), ReauthOutcome.wrong);
      expect(sent.single.url.path, '/auth/v1/token');
      expect(jsonDecode(sent.single.body)['email'], 'ravi@example.com', reason: 'always the account on this phone');
      expect(s.userId, 'u-ravi', reason: 'still signed in');

      server = (_) => throw http.ClientException('no route to host');
      expect(await s.reauthWithPassword('right'), ReauthOutcome.offline);
      server = (_) => http.Response('bad gateway', 502);
      expect(await s.reauthWithPassword('right'), ReauthOutcome.offline);
    });

    test('password: the right one is ok', () async {
      final s = await signedIn();
      server = (_) => http.Response(jsonEncode(_session('u-ravi', 'ravi@example.com')), 200);
      expect(await s.reauthWithPassword('right'), ReauthOutcome.ok);
      expect(s.userId, 'u-ravi');
    });

    test('email code: a sign-in code that never makes an account, checked as an email OTP', () async {
      final s = await signedIn(providers: ['google']);
      server = (_) => http.Response('{}', 200);
      expect(await s.sendReauthCode(), ReauthOutcome.ok);
      expect(sent.last.url.path, '/auth/v1/otp', reason: 'the Magic Link email, not /recover');
      final asked = jsonDecode(sent.last.body);
      expect([asked['email'], asked['create_user']], ['ravi@example.com', false]);
      server = (_) => http.Response(jsonEncode({'code': 'otp_expired', 'msg': 'Token has expired or is invalid'}), 403);
      expect(await s.reauthWithCode('000000'), ReauthOutcome.wrong);
      server = (_) => http.Response(jsonEncode(_session('u-ravi', 'ravi@example.com')), 200);
      expect(await s.reauthWithCode(' 123456 '), ReauthOutcome.ok);
      final body = jsonDecode(sent.last.body);
      expect(sent.last.url.path, '/auth/v1/verify');
      expect([body['type'], body['token'], body['email']], ['email', '123456', 'ravi@example.com']);
      expect(sent.where((r) => r.url.path == '/auth/v1/recover'), isEmpty);
    });

    test('an email code that lands on another user is refused and the phone keeps its own session', () async {
      final s = await signedIn();
      server = (_) => http.Response(jsonEncode(_session('u-other', 'ravi@example.com')), 200);
      expect(await s.reauthWithCode('123456'), ReauthOutcome.wrongAccount);
      expect(s.userId, 'u-ravi');
    });

    test('a Google token for another email is refused without asking the server', () async {
      final s = await signedIn(providers: ['google']);
      final other = _jwt({'sub': 'g-1', 'email': 'someone@else.com'});
      expect(await s.reauthWithIdToken(provider: OAuthProvider.google, idToken: other), ReauthOutcome.wrongAccount);
      expect(sent, isEmpty);
    });

    test('a sign-in that lands on another user is refused and the phone keeps its own session', () async {
      final s = await signedIn(providers: ['google']);
      server = (_) => http.Response(jsonEncode(_session('u-other', 'ravi@example.com')), 200);
      final token = _jwt({'sub': 'g-1', 'email': 'Ravi@Example.com'});
      expect(await s.reauthWithIdToken(provider: OAuthProvider.google, idToken: token), ReauthOutcome.wrongAccount);
      expect(s.userId, 'u-ravi');
    });

    test('the same Google account is ok', () async {
      final s = await signedIn(providers: ['google']);
      server = (_) => http.Response(jsonEncode(_session('u-ravi', 'ravi@example.com', providers: ['google'])), 200);
      final token = _jwt({'sub': 'g-1', 'email': 'ravi@example.com'});
      expect(await s.reauthWithIdToken(provider: OAuthProvider.google, idToken: token), ReauthOutcome.ok);
      expect(sent.single.url.queryParameters['grant_type'], 'id_token');
    });

    test('idTokenEmail reads the email claim, and nothing from junk', () {
      expect(idTokenEmail(_jwt({'email': 'a@b.co'})), 'a@b.co');
      expect(idTokenEmail('not a token'), isNull);
      expect(idTokenEmail('a.b.c'), isNull);
    });

    group('no session, data linked to u-ravi', () {
      late _MemoryStore store;
      late CloudSyncService s;
      late CloudAccountReauth reauth;

      setUp(() {
        store = _MemoryStore();
        s = service(store: store);
        reauth = CloudAccountReauth(
          cloud: s,
          googlePicker: _Google(true),
          applePicker: _Apple(false),
          linked: () async => (userId: 'u-ravi', email: 'ravi@example.com'),
        );
      });

      test('offers every way in to that account', () async {
        final a = (await reauth.account())!;
        expect(a.signedIn, isFalse);
        expect(a.email, 'ravi@example.com');
        expect(a.methods, [ReauthMethod.password, ReauthMethod.google, ReauthMethod.emailCode]);
        expect(sent, isEmpty);
      });

      test('the right password signs this phone in to it', () async {
        await reauth.account();
        server = (_) => http.Response(jsonEncode(_session('u-ravi', 'ravi@example.com')), 200);
        expect(await reauth.password('right'), ReauthOutcome.ok);
        expect(jsonDecode(sent.single.body)['email'], 'ravi@example.com', reason: 'only the linked account is asked');
        expect(s.userId, 'u-ravi');
        expect(store.saved, contains('refresh-u-ravi'), reason: 'kept for the next launch, and for sync');
      });

      test('a session for another user never reaches the phone', () async {
        await reauth.account();
        server = (_) => http.Response(jsonEncode(_session('u-mallory', 'ravi@example.com')), 200);
        expect(await reauth.password('whatever'), ReauthOutcome.wrongAccount);
        expect(s.isSignedIn, isFalse);
        expect(store.saved, isNull);
        final direct = await s.signInAgainAs(
          userId: 'u-ravi',
          signIn: (auth) => auth.signInWithPassword(email: 'mallory@example.com', password: 'hers'),
        );
        expect(direct, ReauthOutcome.wrongAccount, reason: 'signing in to your own account opens nothing');
        expect(s.isSignedIn, isFalse);
        expect(store.saved, isNull);
      });

      test('a wrong password changes nothing', () async {
        await reauth.account();
        server = (_) => http.Response(jsonEncode({'code': 'invalid_credentials', 'msg': 'Invalid login credentials'}), 400);
        expect(await reauth.password('guess'), ReauthOutcome.wrong);
        expect(s.isSignedIn, isFalse);
      });

      test('email code: sent to the linked email with no new account; the right code signs in', () async {
        await reauth.account();
        server = (_) => http.Response('{}', 200);
        expect(await reauth.sendEmailCode(), ReauthOutcome.ok);
        final asked = jsonDecode(sent.single.body);
        expect([sent.single.url.path, asked['email'], asked['create_user']], ['/auth/v1/otp', 'ravi@example.com', false]);
        server = (_) => http.Response(jsonEncode(_session('u-ravi', 'ravi@example.com')), 200);
        expect(await reauth.emailCode('123456'), ReauthOutcome.ok);
        final body = jsonDecode(sent.last.body);
        expect([sent.last.url.path, body['type'], body['email']], ['/auth/v1/verify', 'email', 'ravi@example.com']);
        expect(s.userId, 'u-ravi');
      });

      test('Google: another person\'s Google account is refused before the server could make it an account', () async {
        final google = _Google(true)..token = _jwt({'sub': 'g-2', 'email': 'mallory@example.com'});
        final r = CloudAccountReauth(
          cloud: s,
          googlePicker: google,
          applePicker: _Apple(false),
          linked: () async => (userId: 'u-ravi', email: 'ravi@example.com'),
        );
        await r.account();
        expect(await r.google(), ReauthOutcome.wrongAccount);
        expect(sent, isEmpty);
        expect(s.isSignedIn, isFalse);

        google.token = _jwt({'sub': 'g-1', 'email': 'ravi@example.com'});
        server = (_) => http.Response(jsonEncode(_session('u-ravi', 'ravi@example.com', providers: ['google'])), 200);
        expect(await r.google(), ReauthOutcome.ok);
        expect(s.userId, 'u-ravi');
      });
    });
  });

  group('Forgot PIN on the lock screen', () {
    late AppDatabase db;
    late ProviderContainer container;
    late DateTime now;
    late FakeReauth fake;
    late Directory root;
    late Directory docs;
    late _FakeNotifications notifications;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      now = DateTime.now();
      fake = FakeReauth();
      notifications = _FakeNotifications();
      root = Directory.systemTemp.createTempSync('forgot-pin');
      docs = Directory(p.join(root.path, 'docs'))..createSync();
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          appLockProvider.overrideWith((ref) => AppLock(db, clock: () => now)),
          accountReauthProvider.overrideWithValue(fake),
          notificationServiceProvider.overrideWithValue(notifications),
          phoneEraserProvider.overrideWith((ref) => PhoneEraser(db,
              databasePath: () async => p.join(docs.path, 'fieldos.sqlite'), folders: () async => [docs])),
          cloudSyncClientProvider.overrideWith((ref) {
            final c = SupabaseClient(
              'http://localhost:1',
              'anon',
              authOptions: const AuthClientOptions(autoRefreshToken: false, authFlowType: AuthFlowType.implicit),
            );
            ref.onDispose(c.dispose);
            return c;
          }),
        ],
      );
    });
    tearDown(() async {
      setCurrentLanguage(AppLanguage.en);
      container.dispose();
      await db.close();
      root.deleteSync(recursive: true);
    });

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildFieldOsTheme(Brightness.light),
            builder: (context, child) => AppLockGate(child: child!),
            home: const Scaffold(body: Center(child: Text('Wages: secret'))),
          ),
        ),
      );
      await settle(tester);
    }

    Future<void> enterPin(WidgetTester tester, String pin) async {
      for (final d in pin.split('')) {
        await tester.tap(find.widgetWithText(TextButton, d), warnIfMissed: false);
        await tester.pump();
      }
      await settle(tester);
    }

    Future<void> seedLocked() async {
      await container.read(sessionProvider.notifier).register(username: 'ravi', name: 'Ravi', password: 'pw123456');
      await AppLock(db).setPin('2580');
      await db.settingsDao.set(appLockFailsKey, '6');
      await db.settingsDao.set(appLockLockedAtKey, '${now.millisecondsSinceEpoch}');
      File(p.join(docs.path, 'media', 'dpr', 'photo.jpg'))
        ..createSync(recursive: true)
        ..writeAsStringSync('jpg');
    }

    Future<PinLockout> lockout(WidgetTester tester) async =>
        (await tester.runAsync(() => container.read(appLockProvider).lockout()))!;

    Finder eraseButton() => find.widgetWithText(FilledButton, 'Erase everything');
    bool eraseEnabled(WidgetTester tester) => tester.widget<FilledButton>(eraseButton()).onPressed != null;

    Future<void> expectNothingErased(WidgetTester tester) async {
      expect(await tester.runAsync(() => db.userDao.any()), isTrue);
      expect(await tester.runAsync(() => container.read(appLockProvider).isOn()), isTrue);
      expect((await lockout(tester)).fails, 6);
      expect(container.read(sessionProvider).user, isNotNull);
      expect(File(p.join(docs.path, 'media', 'dpr', 'photo.jpg')).existsSync(), isTrue);
      expect(notifications.cleared, isNull);
    }

    testWidgets('no session and nothing linked: no sign-in offered; Back keeps the wait and the session',
        (tester) async {
      await tester.runAsync(seedLocked);
      await open(tester);
      expect(find.text('Too many wrong PINs. Wait 1:00.'), findsOneWidget);

      await tester.tap(find.text('Forgot PIN?'));
      await settle(tester);
      expect(find.text('This phone is not signed in to the cloud'), findsOneWidget);
      expect(find.textContaining('was never linked to a cloud account'), findsOneWidget);
      expect(find.text('Sign in to keep my data'), findsNothing);
      expect(find.text('Erase this phone and start over'), findsOneWidget);
      expect(find.text('Wages: secret').hitTestable(), findsNothing);
      await expectNothingErased(tester);

      await tester.tap(find.text('Back'));
      await settle(tester);
      expect(find.textContaining('Too many wrong PINs. Wait'), findsOneWidget, reason: 'the wait is still running');
      expect(find.text('Tries left before sign-out: 4'), findsOneWidget);
      expect(find.text('Wages: secret').hitTestable(), findsNothing);
      await expectNothingErased(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('erase: the button waits for the exact word; Cancel erases nothing; the word erases everything',
        (tester) async {
      await tester.runAsync(seedLocked);
      await open(tester);
      await tester.tap(find.text('Forgot PIN?'));
      await settle(tester);
      await tester.tap(find.text('Erase this phone and start over'));
      await settle(tester);

      expect(find.text('Erase this phone?'), findsOneWidget);
      expect(find.textContaining('is lost for good: sites, workers, attendance, bills, photos'), findsOneWidget);
      expect(find.text('To confirm, type ERASE below.'), findsOneWidget);
      expect(find.textContaining('You can also type'), findsNothing, reason: 'English already is ERASE');
      expect(eraseEnabled(tester), isFalse);
      for (final w in ['ERAS', 'ERASED', 'ERASE IT']) {
        await tester.enterText(find.byKey(const ValueKey('erase-word')), w);
        await tester.pump();
        expect(eraseEnabled(tester), isFalse, reason: w);
      }
      await tester.tap(eraseButton(), warnIfMissed: false);
      await settle(tester);
      await expectNothingErased(tester);

      await tester.enterText(find.byKey(const ValueKey('erase-word')), 'ERASE');
      await tester.pump();
      expect(eraseEnabled(tester), isTrue);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(find.text('This phone is not signed in to the cloud'), findsOneWidget);
      await expectNothingErased(tester);

      await tester.tap(find.text('Erase this phone and start over'));
      await settle(tester);
      expect(eraseEnabled(tester), isFalse, reason: 'the word typed before Cancel is gone');
      await tester.enterText(find.byKey(const ValueKey('erase-word')), 'erase');
      await tester.pump();
      await tester.tap(eraseButton());
      await settle(tester);
      await tester.pumpAndSettle();

      expect(await tester.runAsync(() => db.userDao.any()), isFalse);
      expect(await tester.runAsync(() => container.read(appLockProvider).isOn()), isFalse);
      expect(await tester.runAsync(() => db.settingsDao.get(appLockFailsKey)), isNull);
      expect(File(p.join(docs.path, 'media', 'dpr', 'photo.jpg')).existsSync(), isFalse);
      expect(notifications.cleared, isEmpty, reason: 'planned reminders cancelled');
      container.read(sessionProvider);
      await settle(tester);
      expect(container.read(sessionProvider).user, isNull, reason: 'back to first launch');
      expect(container.read(sessionProvider).restoring, isFalse);
      expect(find.text('Wages: secret').hitTestable(), findsOneWidget, reason: 'nothing left to lock');
      expect(tester.takeException(), isNull);
    });

    testWidgets('no session, data linked: sign in to that account, then a new PIN; nothing erased', (tester) async {
      fake.account_ = _linked;
      await tester.runAsync(seedLocked);
      await open(tester);
      await tester.tap(find.text('Forgot PIN?'));
      await settle(tester);
      expect(find.text('This phone is not signed in to the cloud'), findsOneWidget);
      expect(
          find.text('The data on this phone goes with the cloud account ravi@example.com. '
              'Sign in to it to keep the data and choose a new PIN.'),
          findsOneWidget);
      expect(find.text('Erase this phone and start over'), findsOneWidget);

      await tester.tap(find.text('Sign in to keep my data'));
      await settle(tester);
      expect(find.text('Confirm it is you'), findsOneWidget);
      await tester.tap(find.text('Use my password'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'right-password');
      await tester.tap(find.text('Next'));
      await settle(tester);
      expect(find.text('Choose a 4-digit PIN'), findsOneWidget);
      await enterPin(tester, '1357');
      await enterPin(tester, '1357');
      await tester.pumpAndSettle();
      expect(find.text('Wages: secret').hitTestable(), findsOneWidget);
      expect(await tester.runAsync(() => container.read(appLockProvider).check('1357')), isTrue);
      expect(await tester.runAsync(() => db.userDao.any()), isTrue);
      expect(notifications.cleared, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a wrong password keeps the lock; the right one lets a new PIN in', (tester) async {
      fake.account_ = _all;
      fake.reply = ReauthOutcome.wrong;
      await tester.runAsync(seedLocked);
      await open(tester);
      await tester.tap(find.text('Forgot PIN?'));
      await settle(tester);
      expect(find.text('Confirm it is you'), findsOneWidget);
      expect(find.text('To choose a new PIN, sign in again to ravi@example.com.'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Email me a code'), findsOneWidget);
      expect(find.text('Erase this phone and start over'), findsNothing, reason: 'signed in: no erase');

      await tester.tap(find.text('Use my password'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'guess');
      await tester.tap(find.text('Next'));
      await settle(tester);
      expect(find.text('That password is not right.'), findsOneWidget);
      expect((await lockout(tester)).fails, 6);
      expect(find.text('Wages: secret').hitTestable(), findsNothing);

      await tester.enterText(find.byType(TextField), 'right-password');
      await tester.tap(find.text('Next'));
      await settle(tester);
      expect(find.text('Choose a 4-digit PIN'), findsOneWidget);
      expect(await lockout(tester), PinLockout.none, reason: 'cleared by the sign-in');

      await enterPin(tester, '1357');
      expect(find.text('Enter the same PIN again'), findsOneWidget);
      await enterPin(tester, '1357');
      await tester.pumpAndSettle();
      expect(find.text('Wages: secret').hitTestable(), findsOneWidget);
      expect(await tester.runAsync(() => container.read(appLockProvider).check('1357')), isTrue);
      expect(container.read(sessionProvider).user, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the code email is a sign-in code, not a password reset', (tester) async {
      fake.account_ = _all;
      await tester.runAsync(seedLocked);
      await open(tester);
      await tester.tap(find.text('Forgot PIN?'));
      await settle(tester);
      await tester.tap(find.text('Email me a code'));
      await settle(tester);
      expect(find.text('We emailed a sign-in code to ravi@example.com.'), findsOneWidget);
      expect(find.textContaining('password'), findsNothing);
    });

    testWidgets('the Forgot PIN screens fit a 320 dp phone in Tamil', (tester) async {
      setCurrentLanguage(AppLanguage.ta);
      fake.account_ = _all;
      await tester.runAsync(seedLocked);
      await open(tester);
      tester.view.physicalSize = const Size(320, 640);
      await tester.pump();
      await tester.tap(find.text(tr('Forgot PIN?')));
      await settle(tester);
      expect(find.textContaining('{'), findsNothing);
      await tester.tap(find.text(tr('Email me a code')));
      await settle(tester);
      expect(find.textContaining('{'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no session, in Tamil: both choices and the erase screen fit, and the Tamil word erases',
        (tester) async {
      setCurrentLanguage(AppLanguage.ta);
      fake.account_ = _linked;
      await tester.runAsync(seedLocked);
      await open(tester);
      tester.view.physicalSize = const Size(320, 640);
      await tester.pump();
      await tester.tap(find.text(tr('Forgot PIN?')));
      await settle(tester);
      expect(find.textContaining('{'), findsNothing);
      expect(find.text(tr('Sign in to keep my data')), findsOneWidget);
      await tester.ensureVisible(find.text(tr('Erase this phone and start over')));
      await tester.tap(find.text(tr('Erase this phone and start over')));
      await settle(tester);
      expect(find.textContaining('{'), findsNothing);
      expect(find.text(trf('You can also type {word}.', {'word': 'ERASE'})), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('erase-word')), 'அழி');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, tr('Erase everything'))).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });
  });
}

class _Google implements GoogleAccountPicker {
  _Google(this.available);
  @override
  final bool available;
  String? token;
  @override
  Future<GoogleIdentityResult?> pick() async {
    final t = token;
    return t == null ? null : GoogleIdentityResult(idToken: t, email: idTokenEmail(t) ?? '', name: '');
  }

  @override
  Future<void> signOut() async {}
}

class _Apple implements AppleAccountPicker {
  _Apple(this.available);
  @override
  final bool available;
  @override
  Future<AppleIdentityResult?> pick() async => null;
}
