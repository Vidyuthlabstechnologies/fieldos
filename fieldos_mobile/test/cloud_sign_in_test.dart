/// Sign-in, sign-up confirmation and password reset against a stand-in for
/// the hosted Supabase Auth with "Confirm email" on, which the local stack
/// (confirmations off) cannot show. The answers below are the shapes the
/// hosted server sends.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/sync/cloud_sync_service.dart';
import 'package:fieldos_mobile/sync/sync_engine.dart';

String _b64(Map<String, Object> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
final _jwt = '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.${_b64({'sub': 'u1', 'exp': 4102444800, 'role': 'authenticated'})}.sig';

Map<String, Object?> _user({List<Object> identities = const []}) => {
      'id': 'u1',
      'aud': 'authenticated',
      'email': 'ravi@example.com',
      'app_metadata': {'provider': 'email'},
      'user_metadata': <String, Object>{},
      'identities': identities,
      'created_at': '2026-11-06T00:00:00Z',
    };

Map<String, Object?> _session() =>
    {'access_token': _jwt, 'token_type': 'bearer', 'expires_in': 3600, 'refresh_token': 'r1', 'user': _user()};

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

final _invalidCredentials =
    _json({'code': 400, 'error_code': 'invalid_credentials', 'msg': 'Invalid login credentials'}, 400);

(CloudSyncService, SupabaseClient) _service(Future<http.Response> Function(http.Request) handler) {
  final client = SupabaseClient('https://example.supabase.co', 'anon-key',
      httpClient: MockClient(handler), authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit));
  addTearDown(client.dispose);
  return (CloudSyncService(client: client, engine: SyncEngine(db: AppDatabase.memory(), client: client)), client);
}

void main() {
  test('a wrong password for a confirmed account says so, instead of "check your email"', () async {
    final (service, client) = _service((req) async => switch (req.url.path) {
          '/auth/v1/token' => _invalidCredentials,
          // Hosted answer for an existing confirmed email: a stand-in user
          // with no identities, no session, and no email sent.
          '/auth/v1/signup' => _json(_user()),
          _ => _json({'msg': 'unexpected ${req.url.path}'}, 500),
        });
    final result = await service.enableSync(email: 'ravi@example.com', password: 'not-it-123');
    expect(result.outcome, CloudSyncOutcome.wrongPassword);
    expect(client.auth.currentSession, isNull);
  });

  test('a new account with confirmation on is finished with the emailed code', () async {
    final verified = <Map<String, dynamic>>[];
    final (service, _) = _service((req) async {
      switch (req.url.path) {
        case '/auth/v1/token':
          return _invalidCredentials;
        case '/auth/v1/signup':
          return _json(_user(identities: [
            {'id': 'i1', 'user_id': 'u1', 'identity_id': 'i1', 'provider': 'email', 'identity_data': <String, Object>{}},
          ]));
        case '/auth/v1/verify':
          verified.add(jsonDecode(req.body) as Map<String, dynamic>);
          return _json(_session());
      }
      return _json({'msg': 'unexpected'}, 500);
    });
    final result = await service.enableSync(email: 'ravi@example.com', password: 'a-good-one-123');
    expect(result.outcome, CloudSyncOutcome.needsEmailConfirmation);
    expect(service.isSignedIn, isFalse);

    await service.confirmSignUp(email: 'ravi@example.com', code: ' 123456 ');
    expect(service.isSignedIn, isTrue);
    expect(verified.single['type'], 'signup');
    expect(verified.single['token'], '123456');
    expect(verified.single['email'], 'ravi@example.com');
  });

  test('forgot password: code by email, then the new password, then signed in', () async {
    final calls = <String>[];
    final (service, _) = _service((req) async {
      calls.add('${req.method} ${req.url.path}');
      switch (req.url.path) {
        case '/auth/v1/recover':
          return _json(<String, Object>{});
        case '/auth/v1/verify':
          expect((jsonDecode(req.body) as Map)['type'], 'recovery');
          return _json(_session());
        case '/auth/v1/user':
          expect((jsonDecode(req.body) as Map)['password'], 'brand-new-456');
          return _json(_user());
      }
      return _json({'msg': 'unexpected'}, 500);
    });
    await service.sendPasswordResetCode('ravi@example.com');
    await service.resetPassword(email: 'ravi@example.com', code: '654321', newPassword: 'brand-new-456');
    expect(calls, ['POST /auth/v1/recover', 'POST /auth/v1/verify', 'PUT /auth/v1/user']);
    expect(service.isSignedIn, isTrue);
  });

  test('a wrong or old code is a plain sentence', () async {
    final (service, _) = _service((req) async =>
        _json({'code': 403, 'error_code': 'otp_expired', 'msg': 'Token has expired or is invalid'}, 403));
    Object? caught;
    try {
      await service.confirmSignUp(email: 'ravi@example.com', code: '000000');
    } catch (e) {
      caught = e;
    }
    expect(caught, isNotNull);
    expect(friendlyError(caught!), contains('code is not right'));
  });

  test('no connection: the failure keeps its cause, shown as "no internet"', () async {
    final (service, _) = _service((req) async => throw const SocketException('Failed host lookup'));
    final result = await service.enableSync(email: 'ravi@example.com', password: 'whatever-123');
    expect(result.outcome, CloudSyncOutcome.failed);
    expect(friendlyError(result.cause!, result.stack), offlineMessage);
    expect(result.error, isNotNull, reason: 'kept as text for logs');
  });
}
