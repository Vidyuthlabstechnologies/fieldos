/// Bridges the app's existing local (pbkdf2) auth to a real Supabase Auth
/// session, gets the device's company onto the server (register it as the
/// owner, or join a colleague's with a join code -- see
/// supabase/migrations/20261105000000_team_onboarding.sql), keeps that
/// session across app restarts, and exposes "sync now" (push pending
/// outbox entries, then pull everything RLS allows).
///
/// Every employee signs in with their OWN email. (An earlier design shared
/// one company login across phones; it could not tell who wrote a DPR or
/// sent a message, and every device was effectively the owner.) See docs/SUPABASE_SYNC_RESEARCH.md's "clean cutover" plan --
/// local pbkdf2 password hashes can't migrate into Supabase Auth (it's
/// bcrypt-only, Supabase-to-Supabase), so enabling sync means setting a
/// (possibly new) password against Supabase directly, once. This tries
/// sign-in first and falls back to sign-up automatically, so the same
/// "Enable cloud sync" action works whether this is the first device to
/// enable sync for this email or a second device joining an already-synced
/// account.
library;

import 'dart:async';
import 'dart:convert';

import 'package:supabase/supabase.dart';

import 'sync_engine.dart';

/// `needsEmailConfirmation`: the account was created but the Supabase
/// project requires a confirmed email before it issues a session (the
/// hosted default). The user confirms from their inbox, then signs in.
///
/// `wrongPassword`: the email already has an account and the password did
/// not match it.
enum CloudSyncOutcome { signedIn, signedUp, needsEmailConfirmation, wrongPassword, failed }

class CloudSyncResult {
  const CloudSyncResult(this.outcome, {this.cause, this.stack});
  final CloudSyncOutcome outcome;

  /// Why it failed. Screens show it through `friendlyError`, never raw.
  final Object? cause;
  final StackTrace? stack;

  /// The failure as text, for logs and test output.
  String? get error => cause?.toString();
}

/// How signing in again (Forgot PIN) went. `wrong`: the server checked the
/// password or code and refused it. `offline`: no answer, so nothing was
/// checked. `noSession`: this phone is not signed in to a cloud account.
enum ReauthOutcome { ok, wrong, wrongAccount, cancelled, offline, failed, noSession }

/// The email inside a Google or Apple ID token, unverified: only used to
/// refuse a token for another account before sending it. Supabase checks
/// the signature.
String? idTokenEmail(String idToken) {
  final parts = idToken.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    return payload is Map ? payload['email'] as String? : null;
  } catch (_) {
    return null;
  }
}

/// The server-side view of one company membership.
class CloudCompany {
  const CloudCompany({required this.companyId, required this.role, this.name, this.joinCode});
  final String companyId;
  final String role;
  final String? name;

  /// Only returned to owners and project managers.
  final String? joinCode;
}

class CloudMember {
  const CloudMember({required this.userId, required this.email, required this.role});
  final String userId;
  final String email;
  final String role;
}

/// Where the Supabase session is kept between app launches. The app wires
/// this to its local settings table; tests can keep it in memory.
abstract class SessionStore {
  Future<String?> read();
  Future<void> write(String? sessionJson);
}

class CloudSyncService {
  CloudSyncService({required this.client, required this.engine, this.sessionStore, this.freshClient}) {
    _authSub = client.auth.onAuthStateChange.listen((state) {
      // Token refreshes rotate the refresh token; persisting each one is
      // what lets the next app launch resume without a password prompt.
      final store = sessionStore;
      if (store == null) return;
      final session = state.session;
      if (state.event == AuthChangeEvent.signedOut) {
        store.write(null);
      } else if (session != null) {
        store.write(jsonEncode(session.toJson()));
      }
    });
  }

  final SupabaseClient client;
  final SyncEngine engine;
  final SessionStore? sessionStore;

  /// Makes a second client for the same project that shares nothing with
  /// [client]: no session, no saved session, no sync. Forgot PIN signs in
  /// on it first ([signInAgainAs]), so an account that turns out not to be
  /// this phone's never holds [client]'s session, not even for the moment
  /// in which background sync could send the outbox under it. Null: no
  /// fresh sign-in.
  final SupabaseClient Function()? freshClient;
  StreamSubscription<AuthState>? _authSub;

  bool get isSignedIn => client.auth.currentSession != null;
  String? get email => client.auth.currentUser?.email;
  String? get userId => client.auth.currentUser?.id;

  /// Resumes the session saved by a previous launch. Returns false (and
  /// forgets it) if it can no longer be refreshed, e.g. the user was
  /// removed or the refresh token expired -- the user then signs in again.
  /// A network failure keeps the saved session for the next attempt.
  Future<bool> restoreSession() async {
    final saved = await sessionStore?.read();
    if (saved == null) return false;
    try {
      await client.auth.recoverSession(saved);
      return isSignedIn;
    } on AuthException catch (e) {
      final offline = e.statusCode == null || e is AuthRetryableFetchException;
      if (!offline) await sessionStore?.write(null);
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> dispose() async => _authSub?.cancel();

  /// Saved right away on sign-in (the auth-state listener above also saves,
  /// but asynchronously -- and it is what keeps rotated tokens current).
  Future<void> _persist() async {
    final session = client.auth.currentSession;
    if (session != null) await sessionStore?.write(jsonEncode(session.toJson()));
  }

  /// Owner's device: registers this device's local company on the server
  /// under the same id (so every local row's company_id already matches)
  /// and makes the signed-in user its owner. Idempotent for an existing
  /// member; fails for anyone else.
  Future<CloudCompany> registerCompany({required String companyId, required String name}) async {
    final res = await client.rpc('ensure_company', params: {'p_company_id': companyId, 'p_name': name});
    final m = Map<String, dynamic>.from(res as Map);
    return CloudCompany(
      companyId: m['company_id'] as String,
      role: m['role'] as String,
      name: name,
      joinCode: m['join_code'] as String?,
    );
  }

  /// A colleague's device: joins the company behind [code] as a site
  /// engineer (the owner can promote them from the Team screen).
  ///
  /// A wrong code comes back as `{"error": ...}` rather than a database
  /// error, so the server can count it (see join_attempts in
  /// supabase/migrations/20261106000000_join_limits_and_approvals.sql).
  /// Both are thrown as the PostgrestException an older server raised, so
  /// friendlyError has one sentence for each.
  Future<CloudCompany> joinCompany(String code) async {
    final res = await client.rpc('join_company', params: {'p_code': code});
    final m = Map<String, dynamic>.from(res as Map);
    switch (m['error']) {
      case null:
        break;
      case 'too_many_attempts':
        throw const PostgrestException(message: 'too many join attempts', code: 'P0001');
      case 'invalid_join_code':
        throw const PostgrestException(message: 'invalid join code', code: 'P0002');
      case final Object other:
        throw PostgrestException(message: '$other');
    }
    return CloudCompany(companyId: m['company_id'] as String, role: m['role'] as String, name: m['name'] as String?);
  }

  /// A subcontractor's phone: joins with the code the builder's owner or
  /// PM shared. The subcontractor does not join the company; they see only
  /// their own firm's work orders and the outcome of their claims (see
  /// 20261110100000_commercial_controls.sql). Errors as [joinCompany].
  Future<SubcontractorLink> joinAsSubcontractor(String code) async {
    final res = await client.rpc('join_as_subcontractor', params: {'p_code': code});
    final m = Map<String, dynamic>.from(res as Map);
    switch (m['error']) {
      case null:
        break;
      case 'too_many_attempts':
        throw const PostgrestException(message: 'too many join attempts', code: 'P0001');
      case 'invalid_join_code':
        throw const PostgrestException(message: 'invalid join code', code: 'P0002');
      case final Object other:
        throw PostgrestException(message: '$other');
    }
    return SubcontractorLink(
      subcontractorId: m['subcontractor_id'] as String,
      subcontractorName: m['subcontractor_name'] as String,
      companyId: m['company_id'] as String,
      companyName: m['company_name'] as String? ?? 'Company',
    );
  }

  /// Owner or PM: the code one subcontractor joins with.
  Future<String> subcontractorAccessCode(String subcontractorId) async =>
      await client.rpc('subcontractor_access_code', params: {'p_subcontractor_id': subcontractorId}) as String;

  Future<List<CloudMember>> roster(String companyId) async {
    final rows = await client.rpc('company_roster', params: {'p_company_id': companyId}) as List;
    return [
      for (final r in rows.cast<Map>())
        CloudMember(userId: r['user_id'] as String, email: r['email'] as String, role: r['role'] as String),
    ];
  }

  Future<void> setMemberRole({required String companyId, required String userId, required String role}) =>
      client.rpc('set_member_role', params: {'p_company_id': companyId, 'p_user_id': userId, 'p_role': role});

  /// Owner only: takes someone who has left off the company. Their phone
  /// keeps what it already has, but gets nothing new and can send nothing.
  Future<void> removeMember({required String companyId, required String userId}) =>
      client.rpc('remove_member', params: {'p_company_id': companyId, 'p_user_id': userId});

  Future<String> regenerateJoinCode(String companyId) async =>
      await client.rpc('regenerate_join_code', params: {'p_company_id': companyId}) as String;

  /// Tries signing in first (the common case: this device or another one
  /// already enabled sync with this email). Falls back to sign-up only on
  /// an auth failure that plausibly means "this email doesn't have a
  /// Supabase account yet" -- any other failure (wrong password for an
  /// account that DOES exist, network error) is surfaced as a real error,
  /// not silently papered over by attempting to create a duplicate account.
  Future<CloudSyncResult> enableSync({required String email, required String password}) async {
    try {
      await client.auth.signInWithPassword(email: email, password: password);
      await _persist();
      return const CloudSyncResult(CloudSyncOutcome.signedIn);
    } on AuthApiException catch (e, st) {
      final looksLikeNoAccountYet = e.code == 'invalid_credentials' || e.statusCode == '400';
      if (!looksLikeNoAccountYet) return CloudSyncResult(CloudSyncOutcome.failed, cause: e, stack: st);
    } catch (e, st) {
      return CloudSyncResult(CloudSyncOutcome.failed, cause: e, stack: st);
    }

    try {
      final res = await client.auth.signUp(email: email, password: password);
      if (res.session == null) {
        // With email confirmation on (the hosted default), an email that
        // already has a confirmed account gets a stand-in user with no
        // identities, and no email is sent: the password was wrong.
        // Telling the person to check their inbox would leave them waiting.
        if (res.user?.identities?.isEmpty ?? false) return const CloudSyncResult(CloudSyncOutcome.wrongPassword);
        return const CloudSyncResult(CloudSyncOutcome.needsEmailConfirmation);
      }
      await _persist();
      return const CloudSyncResult(CloudSyncOutcome.signedUp);
    } on AuthApiException catch (e, st) {
      // With confirmation off, the server says so outright.
      if (e.code == 'user_already_exists' || e.code == 'email_exists' || e.message == 'User already registered') {
        return const CloudSyncResult(CloudSyncOutcome.wrongPassword);
      }
      return CloudSyncResult(CloudSyncOutcome.failed, cause: e, stack: st);
    } catch (e, st) {
      return CloudSyncResult(CloudSyncOutcome.failed, cause: e, stack: st);
    }
  }

  /// Team & sync with a Google account: Supabase checks [idToken] against
  /// the Google provider's client id and signs in, making the cloud account
  /// the first time. No password, so no wrong-password or email-code steps.
  Future<CloudSyncResult> enableSyncWithGoogle({required String idToken}) async {
    try {
      await client.auth.signInWithIdToken(provider: OAuthProvider.google, idToken: idToken);
      await _persist();
      return const CloudSyncResult(CloudSyncOutcome.signedIn);
    } catch (e, st) {
      return CloudSyncResult(CloudSyncOutcome.failed, cause: e, stack: st);
    }
  }

  /// Team & sync with Sign in with Apple (iPhone): Supabase checks
  /// [idToken] against the Apple provider (client id = the app's bundle id)
  /// and the hash of [rawNonce] inside it. Returns the email Supabase has
  /// for this person, which Apple puts in the token even on later sign-ins
  /// when it no longer shares it with the app; null when sign-in failed.
  Future<({CloudSyncResult result, String? email})> enableSyncWithApple({
    required String idToken,
    required String rawNonce,
  }) async {
    try {
      final res = await client.auth.signInWithIdToken(provider: OAuthProvider.apple, idToken: idToken, nonce: rawNonce);
      await _persist();
      return (result: const CloudSyncResult(CloudSyncOutcome.signedIn), email: res.user?.email);
    } catch (e, st) {
      return (result: CloudSyncResult(CloudSyncOutcome.failed, cause: e, stack: st), email: null);
    }
  }

  /// Finishes a sign-up that [enableSync] reported as
  /// [CloudSyncOutcome.needsEmailConfirmation], with the code from the
  /// confirmation email (supabase/templates/confirmation.html). Throws the
  /// server's error when the code is wrong or old.
  Future<void> confirmSignUp({required String email, required String code}) async {
    await client.auth.verifyOTP(email: email, token: code.trim(), type: OtpType.signup);
    await _persist();
  }

  /// Sends the confirmation email again.
  Future<void> resendSignUpCode(String email) async {
    await client.auth.resend(email: email, type: OtpType.signup);
  }

  /// Emails a code that lets this person choose a new cloud password
  /// ([resetPassword]; supabase/templates/recovery.html). Says nothing
  /// about whether the email has an account, like the server.
  Future<void> sendPasswordResetCode(String email) => client.auth.resetPasswordForEmail(email);

  /// Signs in with the code from [sendPasswordResetCode] and sets
  /// [newPassword]. Throws the server's error when the code is wrong or old.
  Future<void> resetPassword({required String email, required String code, required String newPassword}) async {
    await client.auth.verifyOTP(email: email, token: code.trim(), type: OtpType.recovery);
    await client.auth.updateUser(UserAttributes(password: newPassword));
    await _persist();
  }

  /// How the signed-in account can sign in: 'email' (a password), 'google',
  /// 'apple'. From Supabase's app metadata, so it lists every identity
  /// linked to the account, not only the one used on this phone.
  List<String> get signInProviders {
    final meta = client.auth.currentUser?.appMetadata ?? const {};
    final list = meta['providers'];
    if (list is List) return [for (final p in list) '$p'];
    final one = meta['provider'];
    return one == null ? const [] : ['$one'];
  }

  /// Forgot PIN: proves the person holding the phone owns the signed-in
  /// account by signing in to it again with its password. The session is
  /// replaced by a fresh one for the same user; nothing else changes.
  Future<ReauthOutcome> reauthWithPassword(String password) async {
    final email = this.email;
    if (email == null) return ReauthOutcome.noSession;
    return _reauth(() => client.auth.signInWithPassword(email: email, password: password));
  }

  /// Emails the account a one-time sign-in code for [reauthWithCode]. It
  /// is Supabase's "Magic Link" email, which FieldOS words as a sign-in
  /// code (supabase/templates/magic_link.html, subject "FieldOS
  /// verification code"), not the password-reset one.
  Future<ReauthOutcome> sendReauthCode() async {
    final email = this.email;
    if (email == null) return ReauthOutcome.noSession;
    return sendSignInCode(email);
  }

  /// A sign-in code for [email]; needs no session. An email with no
  /// account is refused, never signed up.
  Future<ReauthOutcome> sendSignInCode(String email) async {
    try {
      await client.auth.signInWithOtp(email: email, shouldCreateUser: false);
      return ReauthOutcome.ok;
    } catch (e) {
      return _reauthFailure(e);
    }
  }

  Future<ReauthOutcome> reauthWithCode(String code) async {
    final email = this.email;
    if (email == null) return ReauthOutcome.noSession;
    return _reauth(() => client.auth.verifyOTP(email: email, token: code.trim(), type: OtpType.email));
  }

  /// Google or Apple users: their provider's ID token, from running that
  /// sign-in again. A token for some other email is refused before it
  /// reaches Supabase, which would otherwise sign this phone in as them.
  Future<ReauthOutcome> reauthWithIdToken({
    required OAuthProvider provider,
    required String idToken,
    String? rawNonce,
  }) async {
    final email = this.email;
    if (email == null) return ReauthOutcome.noSession;
    if (idTokenEmail(idToken)?.toLowerCase() != email.toLowerCase()) return ReauthOutcome.wrongAccount;
    return _reauth(() => client.auth.signInWithIdToken(provider: provider, idToken: idToken, nonce: rawNonce));
  }

  /// Runs [signIn] and checks it landed on the same user. If it did not,
  /// the phone's own session is put back.
  Future<ReauthOutcome> _reauth(Future<AuthResponse> Function() signIn) async {
    final before = client.auth.currentSession;
    if (before == null) return ReauthOutcome.noSession;
    try {
      await signIn();
    } catch (e) {
      return _reauthFailure(e);
    }
    if (client.auth.currentUser?.id != before.user.id) {
      try {
        await client.auth.recoverSession(jsonEncode(before.toJson()));
      } catch (_) {}
      await _persist();
      return ReauthOutcome.wrongAccount;
    }
    await _persist();
    return ReauthOutcome.ok;
  }

  /// Forgot PIN on a phone with no usable session: [signIn] runs on a
  /// [freshClient], and its session moves onto this phone only when it is
  /// [userId], the cloud account this phone's data was synced with. Any
  /// other account is dropped unused: signing in to your own account must
  /// not open somebody else's phone.
  Future<ReauthOutcome> signInAgainAs({
    required String userId,
    required Future<void> Function(GoTrueClient auth) signIn,
  }) async {
    final make = freshClient;
    if (make == null) return ReauthOutcome.noSession;
    final fresh = make();
    try {
      try {
        await signIn(fresh.auth);
      } catch (e) {
        return _reauthFailure(e);
      }
      final session = fresh.auth.currentSession;
      if (session == null) return ReauthOutcome.failed;
      if (session.user.id != userId) return ReauthOutcome.wrongAccount;
      try {
        await client.auth.recoverSession(jsonEncode(session.toJson()));
      } catch (e) {
        return _reauthFailure(e);
      }
      if (this.userId != userId) return ReauthOutcome.failed;
      await _persist();
      return ReauthOutcome.ok;
    } finally {
      await fresh.dispose();
    }
  }

  static ReauthOutcome _reauthFailure(Object e) {
    // Retryable means no answer, or a 5xx: the server never judged it.
    if (e is AuthRetryableFetchException) return ReauthOutcome.offline;
    if (e is AuthException) {
      final status = int.tryParse(e.statusCode ?? '');
      if (status == null) return ReauthOutcome.offline;
      if (status >= 400 && status < 500 && status != 429) return ReauthOutcome.wrong;
    }
    return ReauthOutcome.failed;
  }

  /// Deletes this person's cloud account (Google Play requires an in-app
  /// way to do this). Companies where they are the only member are deleted
  /// with all their records; shared companies keep their records and get a
  /// new owner if needed (see the delete_my_account migration). Signs out
  /// afterwards. Data on this phone is untouched.
  Future<AccountDeletion> deleteAccount() async {
    final res = Map<String, dynamic>.from(await client.rpc('delete_my_account') as Map);
    // The deleted sites' photos, selfies and documents (issue #139): the
    // server queued their folders; this asks it to remove the files now.
    // Best effort -- any later call drains the queue too.
    try {
      await client.functions.invoke('account-cleanup').timeout(const Duration(seconds: 20));
    } catch (_) {}
    try {
      await client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // The session's user is already gone server-side; local sign-out is
      // all that matters.
    }
    await sessionStore?.write(null);
    return AccountDeletion(
      companiesDeleted: res['companies_deleted'] as int,
      companiesLeft: res['companies_left'] as int,
    );
  }

  Future<void> disableSync() async {
    // Send what is still queued while this account is signed in. The queue
    // is not tied to an account, so anything left would go up under the
    // next person who signs in on this phone. Best effort: offline, the
    // queue stays and goes with the next sign-in, as before.
    if (isSignedIn) {
      try {
        await engine.pushPending().timeout(const Duration(seconds: 20));
      } catch (_) {}
    }
    try {
      await client.auth.signOut();
    } catch (_) {
      // Offline: the client drops its session before telling the server,
      // so this phone is signed out already; the server's token expires on
      // its own. The saved session must still go, or the next launch would
      // sign back in.
    }
    await sessionStore?.write(null);
  }

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

class SubcontractorLink {
  const SubcontractorLink({
    required this.subcontractorId,
    required this.subcontractorName,
    required this.companyId,
    required this.companyName,
  });
  final String subcontractorId;
  final String subcontractorName;
  final String companyId;
  final String companyName;
}

class AccountDeletion {
  const AccountDeletion({required this.companiesDeleted, required this.companiesLeft});
  final int companiesDeleted;
  final int companiesLeft;
}
