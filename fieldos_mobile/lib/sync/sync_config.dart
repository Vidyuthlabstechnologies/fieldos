/// Supabase connection config for the sync engine (see
/// docs/SUPABASE_SYNC_RESEARCH.md). Defaults point at the LOCAL Docker-based
/// dev instance (`supabase start`, see supabase/ at the repo root) so the
/// sync engine is testable without a real cloud account -- this assistant
/// does not create third-party accounts on the user's behalf, so wiring in
/// real production credentials is a manual step for whoever deploys this.
///
/// The anon key below is Supabase's well-known, publicly-documented local
/// development default (identical for every local Supabase project unless
/// overridden) -- not a secret, safe to have in source.
library;

import 'package:supabase/supabase.dart';

const _localAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';

class SyncConfig {
  const SyncConfig({required this.url, required this.anonKey});

  final String url;
  final String anonKey;

  /// The one correct way to construct a client for this config -- PKCE
  /// (Supabase's default auth flow) needs persistent storage for a code
  /// verifier across steps, which only matters for OAuth/magic-link
  /// redirect flows and requires wiring up `supabase_flutter`'s storage
  /// layer. CloudSyncService only ever does direct email+password sign-in/
  /// sign-up, which has no redirect step -- implicit flow needs no storage
  /// and is the correct choice here, not a workaround. Using the raw
  /// SupabaseClient constructor with PKCE's default instead throws a hard
  /// assertion ('_asyncStorage != null') the first time anything calls
  /// signUp -- caught by cloud_sync_service_test.dart, not assumed away.
  SupabaseClient createClient() => SupabaseClient(
        url,
        anonKey,
        authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
      );

  /// Local Docker-based dev instance, reached from a normal Dart VM test run
  /// or from a desktop build (both share the host's network namespace).
  static const local = SyncConfig(url: 'http://127.0.0.1:54321', anonKey: _localAnonKey);

  /// Same local instance, reached from an Android emulator -- 127.0.0.1
  /// inside the emulator refers to the emulator itself, not the host
  /// machine; Android's emulator networking reserves 10.0.2.2 for that.
  static const localAndroidEmulator = SyncConfig(url: 'http://10.0.2.2:54321', anonKey: _localAnonKey);

  /// TODO once a real Supabase project exists: replace with the real
  /// project URL + anon key (Settings > API in the Supabase dashboard) and
  /// switch whatever calls SyncConfig.local today to this instead. Never put
  /// the service_role key in the mobile app -- only the anon key, which is
  /// safe to ship since RLS is what actually protects the data.
  static const production = SyncConfig(url: '', anonKey: '');
}
