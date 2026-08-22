/// Password hashing + session-token generation for local, offline auth.
///
/// Mirrors the desktop app's bcrypt + opaque-token model, but uses PBKDF2
/// (pure Dart via `package:cryptography`) so there is no native dependency
/// and it runs identically on Android, iOS, and the dev machine.
library;

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

/// Format: `pbkdf2:<iterations>:<saltBase64>:<hashBase64>`
const _scheme = 'pbkdf2';
const _defaultIterations = 100000;
const _saltBytes = 16;
const _hashBytes = 32;

final _pbkdf2 = Pbkdf2(
  macAlgorithm: Hmac.sha256(),
  iterations: _defaultIterations,
  bits: _hashBytes * 8,
);

String _randomSaltBase64() {
  final bytes = List<int>.generate(_saltBytes, (_) => Random.secure().nextInt(256));
  return base64Encode(bytes);
}

/// Hash a plaintext password for storage.
Future<String> hashPassword(String password) async {
  final salt = _randomSaltBase64();
  final secret = SecretKey(utf8.encode(password));
  final derived = await _pbkdf2.deriveKey(
    secretKey: secret,
    nonce: base64Decode(salt),
  );
  final hash = base64Encode(await derived.extractBytes());
  return '$_scheme:$_defaultIterations:$salt:$hash';
}

/// Constant-time-ish verification. Returns false on any mismatch or malformed
/// stored hash.
Future<bool> verifyPassword(String password, String stored) async {
  final parts = stored.split(':');
  if (parts.length != 4 || parts[0] != _scheme) return false;
  final iterations = int.tryParse(parts[1]);
  if (iterations == null) return false;
  final salt = parts[2];
  final expected = parts[3];
  final secret = SecretKey(utf8.encode(password));
  final derived = await Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: _hashBytes * 8,
  ).deriveKey(secretKey: secret, nonce: base64Decode(salt));
  final actual = base64Encode(await derived.extractBytes());
  if (actual.length != expected.length) return false;
  var diff = 0;
  for (var i = 0; i < actual.length; i++) {
    diff |= actual.codeUnitAt(i) ^ expected.codeUnitAt(i);
  }
  return diff == 0;
}

/// Opaque, unguessable session token (64 hex chars).
String newSessionToken() =>
    const Uuid().v4().replaceAll('-', '') + const Uuid().v4().replaceAll('-', '');
