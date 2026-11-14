/// App lock: wrong-PIN waits and the forced sign-out after ten.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Table;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/security/app_lock.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

void main() {
  final t0 = DateTime(2026, 11, 14, 10);

  group('PinLockout rules', () {
    test('four wrong PINs are free; the 5th waits 30 s, then it doubles', () {
      expect([for (var n = 0; n <= 4; n++) PinLockout.waitAfter(n)], everyElement(Duration.zero));
      expect(PinLockout.waitAfter(5), const Duration(seconds: 30));
      expect(PinLockout.waitAfter(6), const Duration(seconds: 60));
      expect(PinLockout.waitAfter(7), const Duration(seconds: 120));
      expect(PinLockout.waitAfter(9), const Duration(seconds: 480));
    });

    test('wrong() counts and starts the wait only from the 5th', () {
      var s = PinLockout.none;
      for (var i = 0; i < 4; i++) {
        s = s.wrong(t0);
      }
      expect(s.fails, 4);
      expect(s.lockedAt, isNull);
      expect(s.isLocked(t0), isFalse);
      s = s.wrong(t0);
      expect(s.remaining(t0), const Duration(seconds: 30));
      expect(s.remaining(t0.add(const Duration(seconds: 29))), const Duration(seconds: 1));
      expect(s.isLocked(t0.add(const Duration(seconds: 30))), isFalse);
      expect(s.triesLeft, 5);
      expect(s.mustSignIn, isFalse);
    });

    test('the 10th in a row means sign in again', () {
      var s = PinLockout.none;
      for (var i = 0; i < 10; i++) {
        s = s.wrong(t0);
      }
      expect(s.mustSignIn, isTrue);
      expect(s.triesLeft, 0);
    });

    test('a wait that starts in the future (clock set back) runs in full from now', () {
      final s = PinLockout(fails: 6, lockedAt: t0);
      final back = t0.subtract(const Duration(hours: 3));
      expect(s.remaining(back), const Duration(seconds: 60));
      expect(s.settle(back).lockedAt, back);
      expect(s.settle(t0.add(const Duration(seconds: 1))), s, reason: 'a start in the past is kept');
    });

    test('formats the wait as m:ss', () {
      expect(formatPinWait(const Duration(seconds: 30)), '0:30');
      expect(formatPinWait(const Duration(milliseconds: 29001)), '0:30');
      expect(formatPinWait(const Duration(seconds: 120)), '2:00');
      expect(formatPinWait(const Duration(seconds: 485)), '8:05');
    });
  });

  group('AppLock.attempt', () {
    late AppDatabase db;
    late DateTime now;
    AppLock lock() => AppLock(db, clock: () => now);

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      now = t0;
      await lock().setPin('2580');
    });
    tearDown(() => db.close());

    Future<PinAttempt> wrong() => lock().attempt('1111');

    test('the 5th wrong PIN locks for 30 s; inside it even the right PIN is refused and not counted', () async {
      for (var i = 1; i <= 4; i++) {
        final r = await wrong();
        expect(r.result, PinResult.wrong);
        expect(r.wait, Duration.zero, reason: 'try $i');
      }
      final fifth = await wrong();
      expect(fifth.result, PinResult.wrong);
      expect(fifth.wait, const Duration(seconds: 30));
      expect(fifth.triesLeft, 5);

      now = t0.add(const Duration(seconds: 10));
      final refused = await lock().attempt('2580');
      expect(refused.result, PinResult.locked);
      expect(refused.wait, const Duration(seconds: 20));
      expect((await lock().lockout()).fails, 5, reason: 'refused tries are not counted');
    });

    test('the 6th locks 60 s, the 7th 120 s', () async {
      for (var i = 0; i < 5; i++) {
        await wrong();
      }
      now = now.add(const Duration(seconds: 30));
      expect((await wrong()).wait, const Duration(seconds: 60));
      now = now.add(const Duration(seconds: 60));
      expect((await wrong()).wait, const Duration(seconds: 120));
    });

    test('a right PIN resets the count', () async {
      for (var i = 0; i < 4; i++) {
        await wrong();
      }
      expect((await lock().attempt('2580')).result, PinResult.right);
      expect(await lock().lockout(), PinLockout.none);
      for (var i = 0; i < 4; i++) {
        expect((await wrong()).wait, Duration.zero);
      }
    });

    test('the 10th wrong PIN in a row asks for sign-out', () async {
      PinAttempt? last;
      for (var i = 0; i < 10; i++) {
        last = await wrong();
        now = now.add(const Duration(hours: 1));
      }
      expect(last!.result, PinResult.signOut);
      expect((await lock().lockout()).mustSignIn, isTrue, reason: 'kept until the sign-out is done');
      expect((await lock().attempt('2580')).result, PinResult.signOut, reason: 'no PIN gets back in');
      await lock().turnOff();
      expect(await lock().isOn(), isFalse);
      expect(await lock().lockout(), PinLockout.none);
    });

    test('the count and the wait survive a restart', () async {
      for (var i = 0; i < 5; i++) {
        await wrong();
      }
      // A new AppLock on the same database is the app reopened.
      now = t0.add(const Duration(seconds: 5));
      final reopened = AppLock(db, clock: () => now);
      expect((await reopened.lockout()).fails, 5);
      final r = await reopened.attempt('2580');
      expect(r.result, PinResult.locked);
      expect(r.wait, const Duration(seconds: 25));
      expect(await db.settingsDao.get(appLockFailsKey), '5');
    });

    test('setting the clock back does not end the wait early', () async {
      for (var i = 0; i < 5; i++) {
        await wrong();
      }
      now = t0.subtract(const Duration(days: 1));
      final r = await lock().attempt('2580');
      expect(r.result, PinResult.locked);
      expect(r.wait, const Duration(seconds: 30), reason: 'runs in full from the new "now"');
      // Saved that way: once the clock is back to normal, it is over.
      expect(await db.settingsDao.get(appLockLockedAtKey), '${now.millisecondsSinceEpoch}');
      now = now.add(const Duration(seconds: 30));
      expect((await lock().attempt('2580')).result, PinResult.right);
    });

    test('choosing a new PIN, or turning the lock off, clears the count', () async {
      for (var i = 0; i < 6; i++) {
        await wrong();
      }
      await lock().setPin('1357');
      expect(await lock().lockout(), PinLockout.none);
    });
  });

  group('PIN pad', () {
    late AppDatabase db;
    late ProviderContainer container;
    late DateTime now;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      now = DateTime.now();
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          appLockProvider.overrideWith((ref) => AppLock(db, clock: () => now)),
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

    Future<void> open(WidgetTester tester, {Size size = const Size(412, 915)}) async {
      tester.view.physicalSize = size;
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
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    Future<void> enterPin(WidgetTester tester, String pin) async {
      for (final d in pin.split('')) {
        await tester.tap(find.widgetWithText(TextButton, d), warnIfMissed: false);
        await tester.pump();
      }
      // Hashing and the database writes finish outside the fake clock.
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    Future<void> seed(int fails, {DateTime? lockedAt}) async {
      await AppLock(db).setPin('2580');
      await db.settingsDao.set(appLockFailsKey, '$fails');
      await db.settingsDao.set(appLockLockedAtKey, lockedAt == null ? '' : '${lockedAt.millisecondsSinceEpoch}');
    }

    testWidgets('shows the wait and refuses input while locked, then takes the PIN', (tester) async {
      await tester.runAsync(() => seed(5, lockedAt: now));
      await open(tester);
      expect(find.text('Too many wrong PINs. Wait 0:30.'), findsOneWidget);
      expect(find.text('Tries left before sign-out: 5'), findsOneWidget);
      final one = tester.widget<TextButton>(find.widgetWithText(TextButton, '1'));
      expect(one.onPressed, isNull, reason: 'keys are off during the wait');

      // The right PIN typed during the wait goes nowhere.
      await enterPin(tester, '2580');
      expect(find.text('Wages: secret').hitTestable(), findsNothing);
      expect((await tester.runAsync(() => container.read(appLockProvider).lockout()))!.fails, 5);

      await tester.pump(const Duration(seconds: 10));
      expect(find.text('Too many wrong PINs. Wait 0:20.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 20));
      expect(find.textContaining('Too many wrong PINs'), findsNothing);
      now = now.add(const Duration(seconds: 30));

      await enterPin(tester, '2580');
      await tester.pumpAndSettle();
      expect(find.text('Wages: secret').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a wrong PIN after the free tries starts the next, longer wait', (tester) async {
      await tester.runAsync(() => seed(5, lockedAt: now.subtract(const Duration(minutes: 5))));
      await open(tester);
      expect(find.textContaining('Wait'), findsNothing);
      await enterPin(tester, '1111');
      expect(find.text('Too many wrong PINs. Wait 1:00.'), findsOneWidget);
      expect(find.text('Tries left before sign-out: 4'), findsOneWidget);
    });

    testWidgets('the 10th wrong PIN removes the lock and signs out, keeping the data', (tester) async {
      await tester.runAsync(() async {
        await container.read(sessionProvider.notifier).register(username: 'ravi', name: 'Ravi', password: 'pw123456');
        await db.companyDao.create('Ravi Builders');
        await db.settingsDao.set(SettingsSessionStore.key, '{"saved":"cloud session"}');
        await seed(9, lockedAt: now.subtract(const Duration(hours: 1)));
      });
      expect(container.read(sessionProvider).user, isNotNull);
      await open(tester);
      await enterPin(tester, '1111');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();

      expect(find.text('Too many wrong PINs. The app lock is off. Log in again with your password.'), findsOneWidget);
      expect(container.read(sessionProvider).user, isNull, reason: 'signed out on the phone');
      await tester.runAsync(() async {
        expect(await container.read(appLockProvider).isOn(), isFalse);
        expect(await db.settingsDao.get(SettingsSessionStore.key), '', reason: 'and of the cloud account');
        expect((await db.select(db.companies).get()).map((c) => c.name), contains('Ravi Builders'));
      });

      await tester.tap(find.text('Log in'));
      await tester.pumpAndSettle();
      expect(find.text('Wages: secret').hitTestable(), findsOneWidget);
    });

    testWidgets('a half-done sign-out (app killed) finishes on the next launch', (tester) async {
      await tester.runAsync(() => seed(10));
      await open(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      expect(find.text('Too many wrong PINs. The app lock is off. Log in again with your password.'), findsOneWidget);
      expect(await tester.runAsync(() => container.read(appLockProvider).isOn()), isFalse);
    });

    testWidgets('the wait fits a 320 dp phone in Tamil', (tester) async {
      setCurrentLanguage(AppLanguage.ta);
      await tester.runAsync(() => seed(6, lockedAt: now));
      await open(tester, size: const Size(320, 640));
      expect(find.textContaining('{'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
