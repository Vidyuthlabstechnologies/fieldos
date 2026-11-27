/// Somewhere safer than the app's database for a secret: Android's Keystore,
/// or the iPhone's Keychain. Used for the signed-in cloud session, whose
/// refresh token is as good as the person's password for as long as it lives.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class SecretStore {
  /// Null when nothing is stored under [key]. May throw when the platform
  /// store is unavailable; callers fall back rather than lock anyone out.
  Future<String?> read(String key);

  /// Null [value] deletes.
  Future<void> write(String key, String? value);
}

class PlatformSecretStore implements SecretStore {
  const PlatformSecretStore();

  // On an iPhone the Keychain outlives an uninstall, so the app also keeps a
  // marker in its own database and ignores a secret it has no marker for (see
  // SettingsSessionStore). This device only, and readable after the first
  // unlock so a background sync can resume.
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String? value) =>
      value == null ? _storage.delete(key: key) : _storage.write(key: key, value: value);
}
