/// Bridges the app's existing local (pbkdf2) auth to a real Supabase Auth
/// session, and exposes the one action a user/owner actually triggers:
/// "sync now" (push pending outbox entries, then pull everything RLS
/// allows). See docs/SUPABASE_SYNC_RESEARCH.md's "clean cutover" plan --
/// local pbkdf2 password hashes can't migrate into Supabase Auth (it's
/// bcrypt-only, Supabase-to-Supabase), so enabling sync means setting a
/// (possibly new) password against Supabase directly, once. This tries
/// sign-in first and falls back to sign-up automatically, so the same
/// "Enable cloud sync" action works whether this is the first device to
/// enable sync for this email or a second device joining an already-synced
/// account.
library;

import 'package:supabase/supabase.dart';

import 'sync_engine.dart';

enum CloudSyncOutcome { signedIn, signedUp, failed }

class CloudSyncResult {
  const CloudSyncResult(this.outcome, {this.error});
  final CloudSyncOutcome outcome;
  final String? error;
}

class CloudSyncService {
  CloudSyncService({required this.client, required this.engine});

  final SupabaseClient client;
  final SyncEngine engine;

  bool get isSignedIn => client.auth.currentSession != null;

  /// Tries signing in first (the common case: this device or another one
  /// already enabled sync with this email). Falls back to sign-up only on
  /// an auth failure that plausibly means "this email doesn't have a
  /// Supabase account yet" -- any other failure (wrong password for an
  /// account that DOES exist, network error) is surfaced as a real error,
  /// not silently papered over by attempting to create a duplicate account.
  Future<CloudSyncResult> enableSync({required String email, required String password}) async {
    try {
      await client.auth.signInWithPassword(email: email, password: password);
      return const CloudSyncResult(CloudSyncOutcome.signedIn);
    } on AuthApiException catch (e) {
      final looksLikeNoAccountYet = e.code == 'invalid_credentials' || e.statusCode == '400';
      if (!looksLikeNoAccountYet) {
        return CloudSyncResult(CloudSyncOutcome.failed, error: e.message);
      }
    } catch (e) {
      return CloudSyncResult(CloudSyncOutcome.failed, error: e.toString());
    }

    try {
      await client.auth.signUp(email: email, password: password);
      return const CloudSyncResult(CloudSyncOutcome.signedUp);
    } catch (e) {
      return CloudSyncResult(CloudSyncOutcome.failed, error: e.toString());
    }
  }

  Future<void> disableSync() => client.auth.signOut();

  /// Push everything queued locally, then pull everything RLS allows. Push
  /// goes first deliberately -- this device's own not-yet-synced writes
  /// should reach the server before a pull potentially overwrites local
  /// rows with a server-wins merge (see docs/SUPABASE_SYNC_RESEARCH.md's
  /// conflict strategy).
  Future<SyncPushResult> syncNow() async {
    if (!isSignedIn) {
      throw StateError('syncNow() called before enableSync() -- no authenticated Supabase session.');
    }
    final pushResult = await engine.pushPending();
    await engine.pullAll();
    return pushResult;
  }
}
