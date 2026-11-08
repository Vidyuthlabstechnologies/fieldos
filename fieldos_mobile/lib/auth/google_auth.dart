/// "Continue with Google": picks a Google account on the phone, makes (or
/// opens) the matching account on this phone, and signs in to Team & sync
/// with the same Google identity, so the person never chooses a password.
///
/// Needs GOOGLE_WEB_CLIENT_ID at build time (the "Web application" OAuth
/// client in Google Cloud, also set as the Google provider's client id in
/// Supabase). Builds without it don't show the button.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// The OAuth client Supabase checks the Google ID token against.
const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

class GoogleIdentityResult {
  const GoogleIdentityResult({required this.email, required this.name, required this.idToken});
  final String email;
  final String name;
  final String idToken;
}

/// The phone's Google account picker, behind an interface so tests and
/// builds without Google can swap it.
abstract class GoogleAccountPicker {
  bool get available;

  /// Null when the person closed the picker.
  Future<GoogleIdentityResult?> pick();

  Future<void> signOut();
}

class PlatformGooglePicker implements GoogleAccountPicker {
  PlatformGooglePicker({this.webClientId = googleWebClientId});
  final String webClientId;
  Future<void>? _init;

  @override
  bool get available => webClientId.isNotEmpty && GoogleSignIn.instance.supportsAuthenticate();

  Future<void> _ready() => _init ??= GoogleSignIn.instance.initialize(serverClientId: webClientId);

  @override
  Future<GoogleIdentityResult?> pick() async {
    await _ready();
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) throw StateError('Google did not return an ID token.');
      return GoogleIdentityResult(
        email: account.email,
        name: (account.displayName ?? '').trim().isEmpty ? account.email.split('@').first : account.displayName!.trim(),
        idToken: idToken,
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled || e.code == GoogleSignInExceptionCode.interrupted) return null;
      rethrow;
    }
  }

  @override
  Future<void> signOut() async {
    if (_init == null) return;
    await GoogleSignIn.instance.signOut();
  }
}

final googlePickerProvider = Provider<GoogleAccountPicker>((ref) => PlatformGooglePicker());
