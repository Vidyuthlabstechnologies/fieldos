import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/team/team_sync_screen.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

String _b64(Map<String, Object> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
final _jwt = '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.${_b64({'sub': 'u1', 'exp': 4102444800})}.sig';

Map<String, Object?> _user() => {
      'id': 'u1',
      'aud': 'authenticated',
      'email': 'ravi@example.com',
      'app_metadata': {'provider': 'email'},
      'user_metadata': <String, Object>{},
      'identities': const <Object>[],
      'created_at': '2026-11-06T00:00:00Z',
    };

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  testWidgets('wrong cloud password, then "Forgot password?" with the emailed code', (tester) async {
    final calls = <String>[];
    final client = SupabaseClient('https://example.supabase.co', 'anon-key',
        httpClient: MockClient((req) async {
          calls.add(req.url.path);
          return switch (req.url.path) {
            '/auth/v1/token' =>
              _json({'code': 400, 'error_code': 'invalid_credentials', 'msg': 'Invalid login credentials'}, 400),
            '/auth/v1/signup' => _json(_user()), // existing confirmed account: stand-in user
            '/auth/v1/recover' => _json(<String, Object>{}),
            '/auth/v1/verify' => _json(
                {'access_token': _jwt, 'token_type': 'bearer', 'expires_in': 3600, 'refresh_token': 'r', 'user': _user()}),
            '/auth/v1/user' => _json(_user()),
            _ => _json({'msg': 'unexpected'}, 500),
          };
        }),
        authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit, autoRefreshToken: false));
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      cloudSyncClientProvider.overrideWithValue(client),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await tester.runAsync(() async {
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'ravi', name: 'Ravi Kumar', password: '123456');
      await session.createCompany('Sri Sai Constructions');
    });
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> settle() async {
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pumpAndSettle();
      }
    }

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: const TeamSyncScreen()),
    ));
    await settle();

    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'ravi@example.com');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'not-my-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await settle();
    expect(find.textContaining('that password is not right for it'), findsOneWidget);
    expect(find.textContaining('confirmation link'), findsNothing);

    await tester.tap(find.text('Forgot password?'));
    await settle();
    expect(find.text('Choose a new password'), findsOneWidget);
    expect(calls, contains('/auth/v1/recover'));

    await tester.enterText(find.byKey(const Key('email-code')), '123456');
    await tester.enterText(find.byKey(const Key('new-cloud-password')), 'brand-new-456');
    await tester.tap(find.widgetWithText(FilledButton, 'Save new password'));
    await settle();
    expect(find.textContaining('New password saved'), findsOneWidget);
    expect(find.textContaining('Signed in as ravi@example.com'), findsWidgets);
    expect(calls.where((c) => c == '/auth/v1/verify'), hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
