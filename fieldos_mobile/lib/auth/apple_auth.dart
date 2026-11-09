/// "Sign in with Apple" on iPhone. Apple's App Review Guideline 4.8 asks
/// any app that offers a third-party sign-in (FieldOS has Continue with
/// Google) to offer Sign in with Apple next to it.
///
/// It works like Google: Apple confirms who this is, Supabase checks
/// Apple's ID token (the Apple provider, with the app's bundle id as its
/// client id), and then the account on this phone opens, or is made,
/// keyed by the email. Apple may hand out a private relay address
/// (...@privaterelay.appleid.com) instead of the real one; that is fine,
/// it stays the same for this person and this app.
///
/// Only shown on iOS. Android keeps Google only.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AppleIdentityResult {
  const AppleIdentityResult({required this.idToken, required this.rawNonce, this.email, this.name});

  /// Apple's signed ID token, for Supabase.
  final String idToken;

  /// The nonce before hashing: Apple signs its SHA-256, Supabase checks it.
  final String rawNonce;

  /// Apple shares the email and name only the first time someone signs in
  /// to the app. Later the email comes from the ID token, through Supabase.
  final String? email;
  final String? name;
}

/// The iPhone's Apple sign-in sheet, behind an interface so tests and
/// other platforms can swap it.
abstract class AppleAccountPicker {
  bool get available;

  /// Null when the person closed the sheet.
  Future<AppleIdentityResult?> pick();
}

/// A random nonce of URL-safe characters, as Apple and Supabase expect.
String newAppleNonce([int length = 32]) {
  const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
  final random = math.Random.secure();
  return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
}

/// The hex SHA-256 of [nonce], which is what Apple puts in the token.
Future<String> sha256Hex(String nonce) async {
  final hash = await Sha256().hash(utf8.encode(nonce));
  return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// The name Apple shared, or null.
String? appleDisplayName(String? given, String? family) {
  final name = [given, family].where((p) => p != null && p.trim().isNotEmpty).map((p) => p!.trim()).join(' ');
  return name.isEmpty ? null : name;
}

class PlatformApplePicker implements AppleAccountPicker {
  @override
  bool get available => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<AppleIdentityResult?> pick() async {
    final rawNonce = newAppleNonce();
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
        nonce: await sha256Hex(rawNonce),
      );
      final idToken = credential.identityToken;
      if (idToken == null) throw StateError('Apple did not return an ID token.');
      return AppleIdentityResult(
        idToken: idToken,
        rawNonce: rawNonce,
        email: credential.email,
        name: appleDisplayName(credential.givenName, credential.familyName),
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      rethrow;
    }
  }
}

final applePickerProvider = Provider<AppleAccountPicker>((ref) => PlatformApplePicker());
