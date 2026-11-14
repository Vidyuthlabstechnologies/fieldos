/// Forgot PIN: the PIN can only be reset after signing in to the cloud
/// account again, and until then the wrong-PIN count and wait stand.
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Table;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/auth/apple_auth.dart';
import 'package:fieldos_mobile/auth/google_auth.dart';
import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/security/app_lock.dart';
import 'package:fieldos_mobile/features/security/pin_reset.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_service.dart';
import 'package:fieldos_mobile/sync/sync_engine.dart';

/// Signing in again, scripted: [account] null is a phone with no cloud
/// account it can reach.
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

void main() {
  final t0 = DateTime(2026, 11, 14, 10);

  group('PinReset steps', () {
    late AppDatabase db;
    late DateTime now;
    late AppLock lock;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      now = t0;
      lock = AppLock(db, clock: () => now);
      await lock.setPin('2580');
      // Six wrong PINs: the 60 s wait started at t0.
      await db.settingsDao.set(appLockFailsKey, '6');
      await db.settingsDao.set(appLockLockedAtKey, '${t0.millisecondsSinceEpoch}');
    });
    tearDown(() => db.close());

    Future<void> expectStillLocked() async {
      final s = await lock.lockout();
      expect(s.fails, 6, reason: 'the count stands');
      expect(s.lockedAt, t0, reason: 'and so does the wait');
      expect(s.remaining(now), const Duration(seconds: 60));
      expect(await lock.check('2580'), isTrue, reason: 'the old PIN is kept');
    }

    test('no cloud account (or offline): the PIN cannot be reset and the wait stands', () async {
      final r = PinReset(lock: lock, reauth: FakeReauth());
      await r.start();
      expect(r.step, PinResetStep.unavailable);
      await expectLater(r.setPin('1357'), throwsStateError);
      for (final m in ReauthMethod.values) {
        await r.choose(m);
      }
      expect(r.step, PinResetStep.unavailable);
      await expectStillLocked();
    });

    test('a new PIN cannot be set before signing in again', () async {
      final r = PinReset(lock: lock, reauth: FakeReauth(account_: _all));
      await r.start();
      expect(r.step, PinResetStep.choose);
      await expectLater(r.setPin('1357'), throwsStateError);
      await r.choose(ReauthMethod.password);
      await expectLater(r.setPin('1357'), throwsStateError);
      await expectStillLocked();
    });

    test('a wrong password, or no internet, changes nothing', () async {
      final fake = FakeReauth(account_: _all, reply: ReauthOutcome.wrong);
      final r = PinReset(lock: lock, reauth: fake);
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
      final r = PinReset(lock: lock, reauth: FakeReauth(account_: _all));
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
      final r = PinReset(lock: lock, reauth: fake);
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
      final r = PinReset(lock: lock, reauth: fake);
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
      final r = PinReset(lock: lock, reauth: FakeReauth(account_: _all));
      await r.start();
      await r.choose(ReauthMethod.password);
      r.back();
      expect(r.step, PinResetStep.choose);
      await expectStillLocked();
    });
  });

  group('CloudSyncService re-authentication', () {
    late AppDatabase db;
    late List<http.Request> sent;
    late http.Response Function(http.Request) server;

    CloudSyncService service() {
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
      addTearDown(client.dispose);
      return CloudSyncService(client: client, engine: SyncEngine(db: db, client: client));
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
      expect(a.methods, [ReauthMethod.password, ReauthMethod.google, ReauthMethod.emailCode]);
    });

    test('Google- or Apple-only accounts get their provider and the email code, not a password', () async {
      final s = await signedIn(providers: ['apple']);
      final reauth = CloudAccountReauth(cloud: s, googlePicker: _Google(true), applePicker: _Apple(true));
      expect((await reauth.account())!.methods, [ReauthMethod.apple, ReauthMethod.emailCode]);
    });

    test('no session on the phone: no account, nothing sent', () async {
      final s = service();
      final reauth = CloudAccountReauth(cloud: s, googlePicker: _Google(true), applePicker: _Apple(true));
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

    test('email code: sends the recovery code, then checks it as a recovery OTP', () async {
      final s = await signedIn(providers: ['google']);
      server = (_) => http.Response('{}', 200);
      expect(await s.sendReauthCode(), ReauthOutcome.ok);
      expect(sent.last.url.path, '/auth/v1/recover');
      server = (_) => http.Response(jsonEncode({'code': 'otp_expired', 'msg': 'Token has expired or is invalid'}), 403);
      expect(await s.reauthWithCode('000000'), ReauthOutcome.wrong);
      server = (_) => http.Response(jsonEncode(_session('u-ravi', 'ravi@example.com')), 200);
      expect(await s.reauthWithCode(' 123456 '), ReauthOutcome.ok);
      final body = jsonDecode(sent.last.body);
      expect(sent.last.url.path, '/auth/v1/verify');
      expect([body['type'], body['token'], body['email']], ['recovery', '123456', 'ravi@example.com']);
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
  });

  group('Forgot PIN on the lock screen', () {
    late AppDatabase db;
    late ProviderContainer container;
    late DateTime now;
    late FakeReauth fake;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      now = DateTime.now();
      fake = FakeReauth();
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          appLockProvider.overrideWith((ref) => AppLock(db, clock: () => now)),
          accountReauthProvider.overrideWithValue(fake),
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
    }

    Future<PinLockout> lockout(WidgetTester tester) async =>
        (await tester.runAsync(() => container.read(appLockProvider).lockout()))!;

    testWidgets('offline / no cloud account: says the PIN cannot be reset; the wait and the session stay',
        (tester) async {
      await tester.runAsync(seedLocked);
      await open(tester);
      expect(find.text('Too many wrong PINs. Wait 1:00.'), findsOneWidget);

      await tester.tap(find.text('Forgot PIN?'));
      await settle(tester);
      expect(find.textContaining('The PIN cannot be reset on this phone now.'), findsOneWidget);
      expect(find.text('Wages: secret').hitTestable(), findsNothing);
      expect((await lockout(tester)).fails, 6);
      expect(container.read(sessionProvider).user, isNotNull, reason: 'Forgot PIN no longer signs out');
      expect(await tester.runAsync(() => container.read(appLockProvider).isOn()), isTrue);

      await tester.tap(find.text('Back'));
      await settle(tester);
      expect(find.textContaining('Too many wrong PINs. Wait'), findsOneWidget, reason: 'the wait is still running');
      expect(find.text('Tries left before sign-out: 4'), findsOneWidget);
      expect(find.text('Wages: secret').hitTestable(), findsNothing);
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
  });
}

class _Google implements GoogleAccountPicker {
  _Google(this.available);
  @override
  final bool available;
  @override
  Future<GoogleIdentityResult?> pick() async => null;
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
