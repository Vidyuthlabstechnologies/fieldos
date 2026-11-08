import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/auth/google_auth.dart';
import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/auth/login_screen.dart';
import 'package:fieldos_mobile/features/company/company_setup_screen.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';
import 'package:supabase/supabase.dart';

/// The first screens everyone sees must fit a small phone in both themes
/// (an overflow fails the test) and say what went wrong in plain words.
void main() {
  const sizes = [Size(320, 568), Size(412, 915)];

  Future<ProviderContainer> pumpScreen(
    WidgetTester tester,
    Widget screen, {
    Size size = const Size(412, 915),
    Brightness brightness = Brightness.light,
    bool signedIn = false,
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db), ...overrides]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    if (signedIn) {
      await tester.runAsync(() => container
          .read(sessionProvider.notifier)
          .register(username: 'ravi', name: 'Ravi Kumar', password: '123456'));
    }
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildFieldOsTheme(brightness),
        home: screen,
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    return container;
  }

  for (final size in sizes) {
    for (final brightness in Brightness.values) {
      final label = '${size.width.toInt()}x${size.height.toInt()} ${brightness.name}';
      testWidgets('login fits $label', (tester) async {
        await pumpScreen(tester, const LoginScreen(), size: size, brightness: brightness);
        // A phone with no accounts opens on "Create account".
        expect(find.text('Create your account'), findsOneWidget);
        // On a small phone the form scrolls to reach the switch.
        await tester.ensureVisible(find.text('Already have an account? Log in'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Already have an account? Log in'));
        await tester.pumpAndSettle();
        expect(find.text('Welcome back'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('company setup fits $label', (tester) async {
        await pumpScreen(tester, const CompanySetupScreen(), size: size, brightness: brightness, signedIn: true);
        expect(find.text('Welcome, Ravi'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('a blank company name gets a plain message, not a database error', (tester) async {
    await pumpScreen(tester, const CompanySetupScreen(), signedIn: true);
    await tester.tap(find.text('Create company'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Enter your company name.'), findsOneWidget);
  });

  testWidgets('a wrong password says so in words', (tester) async {
    final container = await pumpScreen(tester, const LoginScreen());
    await tester.runAsync(() => AuthService(container.read(appDatabaseProvider))
        .register(username: 'meena', name: 'Meena', password: 'secret1'));
    await tester.tap(find.text('Already have an account? Log in'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Username'), 'Meena');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'wrong-one');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    expect(find.text('That username or password is not right.'), findsOneWidget);
  });

  testWidgets('no Google button when the build has no Google client', (tester) async {
    await pumpScreen(tester, const LoginScreen(), overrides: [googlePickerProvider.overrideWithValue(_FakePicker(available: false))]);
    expect(find.text('Continue with Google'), findsNothing);
  });

  testWidgets('Google sign-in that the server refuses keeps the phone signed out', (tester) async {
    final container = await pumpScreen(tester, const LoginScreen(), overrides: [
      googlePickerProvider.overrideWithValue(_FakePicker(available: true)),
      cloudSyncClientProvider.overrideWithValue(SupabaseClient('http://localhost:1', 'anon',
          authOptions: const AuthClientOptions(autoRefreshToken: false, authFlowType: AuthFlowType.implicit))),
    ]);
    expect(find.text('Continue with Google'), findsOneWidget);
    await tester.tap(find.text('Continue with Google'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pumpAndSettle();
    expect(find.text('Google sign-in did not go through. Check the internet and try again.'), findsOneWidget);
    final users = await tester.runAsync(() => container.read(appDatabaseProvider).select(container.read(appDatabaseProvider).users).get());
    expect(users, isEmpty);
  });
}

class _FakePicker implements GoogleAccountPicker {
  _FakePicker({required this.available});
  @override
  final bool available;
  @override
  Future<GoogleIdentityResult?> pick() async =>
      const GoogleIdentityResult(email: 'Meena@Example.com', name: 'Meena', idToken: 'not-a-real-token');
  @override
  Future<void> signOut() async {}
}
