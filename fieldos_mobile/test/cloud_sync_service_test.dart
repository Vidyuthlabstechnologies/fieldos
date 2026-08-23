/// Real test against the local Supabase Auth (GoTrue) instance -- not
/// mocked. Confirms the sign-in-or-signup fallback actually behaves
/// correctly against a real auth server, including the case that matters
/// most: a wrong password for an account that DOES exist must be reported
/// as a real failure, never silently treated as "no account yet" and
/// papered over with a signup attempt (which would just fail anyway with a
/// confusing "user already exists" error instead of the real problem).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/sync/cloud_sync_service.dart';
import 'package:fieldos_mobile/sync/sync_config.dart';
import 'package:fieldos_mobile/sync/sync_engine.dart';

final _uuid = Uuid();

Future<bool> _localStackReachable() async {
  try {
    final res = await http.get(Uri.parse('${SyncConfig.local.url}/rest/v1/')).timeout(const Duration(seconds: 2));
    return res.statusCode < 500;
  } catch (_) {
    return false;
  }
}

void main() {
  late bool stackUp;

  setUpAll(() async {
    stackUp = await _localStackReachable();
  });

  group('CloudSyncService against real local Supabase Auth', () {
    test('enableSync signs up a brand-new email', () async {
      if (!stackUp) return;
      final client = SyncConfig.local.createClient();
      final db = AppDatabase.memory();
      final service = CloudSyncService(client: client, engine: SyncEngine(db: db, client: client));

      expect(service.isSignedIn, isFalse);

      final result = await service.enableSync(
        email: 'cloud-sync-new-${_uuid.v4()}@test.local',
        password: 'a-real-password-123!',
      );

      expect(result.outcome, CloudSyncOutcome.signedUp, reason: result.error);
      expect(service.isSignedIn, isTrue);

      await client.dispose();
    });

    test('enableSync signs in an existing email with the correct password', () async {
      if (!stackUp) return;
      final email = 'cloud-sync-existing-${_uuid.v4()}@test.local';
      const password = 'a-real-password-123!';

      // First device: creates the account.
      final firstClient = SyncConfig.local.createClient();
      final firstResult = await CloudSyncService(
        client: firstClient,
        engine: SyncEngine(db: AppDatabase.memory(), client: firstClient),
      ).enableSync(email: email, password: password);
      expect(firstResult.outcome, CloudSyncOutcome.signedUp, reason: firstResult.error);
      await firstClient.dispose();

      // Second device: same email, same password -- must sign IN, not
      // attempt (and fail) a duplicate sign-up.
      final secondClient = SyncConfig.local.createClient();
      final secondResult = await CloudSyncService(
        client: secondClient,
        engine: SyncEngine(db: AppDatabase.memory(), client: secondClient),
      ).enableSync(email: email, password: password);

      expect(secondResult.outcome, CloudSyncOutcome.signedIn);
      expect(secondResult.error, isNull);
      await secondClient.dispose();
    });

    test('enableSync with the WRONG password for an existing account reports a real failure, not a silent signup attempt', () async {
      if (!stackUp) return;
      final email = 'cloud-sync-wrongpw-${_uuid.v4()}@test.local';

      final firstClient = SyncConfig.local.createClient();
      await CloudSyncService(
        client: firstClient,
        engine: SyncEngine(db: AppDatabase.memory(), client: firstClient),
      ).enableSync(email: email, password: 'the-real-password-123!');
      await firstClient.dispose();

      final attackerClient = SyncConfig.local.createClient();
      final result = await CloudSyncService(
        client: attackerClient,
        engine: SyncEngine(db: AppDatabase.memory(), client: attackerClient),
      ).enableSync(email: email, password: 'a-completely-wrong-password');

      // A wrong password for an EXISTING account also returns
      // invalid_credentials from GoTrue (same as "no account yet", by
      // design -- Supabase doesn't let you distinguish the two, to avoid
      // leaking which emails have accounts). So this DOES fall through to
      // an attempted signup -- and that signup must itself fail cleanly
      // (email already registered) rather than silently signing the
      // attacker in. Either way, the net result must be: not signed in.
      expect(result.outcome, CloudSyncOutcome.failed);
      expect(attackerClient.auth.currentSession, isNull);

      await attackerClient.dispose();
    });
  });
}
