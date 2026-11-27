/// The signed-in cloud session lives in the phone's secure store (Keystore or
/// Keychain), not as plain text in the app's database (customer review: the
/// refresh token is as good as the password). The ways this can go wrong are
/// the ones tested here: the token still in the database, a secure-store
/// failure signing someone out, an iPhone's leftover Keychain item signing a
/// fresh install in, and "erase this phone" leaving the token behind.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/data/erase_phone.dart';
import 'package:fieldos_mobile/data/secret_store.dart';
import 'package:fieldos_mobile/features/legal/consent_record.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

class _FakeSecrets implements SecretStore {
  final values = <String, String>{};
  bool broken = false;

  @override
  Future<String?> read(String key) async {
    if (broken) throw StateError('Keystore unavailable');
    return values[key];
  }

  @override
  Future<void> write(String key, String? value) async {
    if (broken) throw StateError('Keystore unavailable');
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

const _session = '{"access_token":"a","refresh_token":"r-secret","user":{"id":"u1"}}';

void main() {
  late AppDatabase db;
  late _FakeSecrets secrets;
  late SettingsSessionStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    secrets = _FakeSecrets();
    store = SettingsSessionStore(db, secrets: secrets);
    addTearDown(db.close);
  });

  Future<String?> inDatabase() => db.settingsDao.get(SettingsSessionStore.key);

  test('the token goes to the secure store and never to the database', () async {
    await store.write(_session);
    expect(secrets.values[SettingsSessionStore.key], _session);
    expect(await inDatabase(), SettingsSessionStore.secureMarker);
    expect(await inDatabase(), isNot(contains('refresh_token')));
    expect(await store.read(), _session);
  });

  test('a token that rotates is replaced in the secure store, not left behind', () async {
    await store.write(_session);
    await store.write(_session.replaceFirst('r-secret', 'r-rotated'));
    expect(await store.read(), contains('r-rotated'));
    expect(secrets.values.values.single, isNot(contains('r-secret')));
  });

  test('a session saved in the database by an older version moves to the secure store on first read', () async {
    await db.settingsDao.set(SettingsSessionStore.key, _session);
    expect(await store.read(), _session, reason: 'still signed in after the update');
    expect(secrets.values[SettingsSessionStore.key], _session);
    expect(await inDatabase(), SettingsSessionStore.secureMarker, reason: 'and no longer in the database');
  });

  test('if the secure store fails, the session stays in the database: nobody is signed out for it', () async {
    secrets.broken = true;
    await store.write(_session);
    expect(await inDatabase(), _session);
    expect(await store.read(), _session);
    // A legacy session that cannot be moved is still returned.
    await db.settingsDao.set(SettingsSessionStore.key, _session);
    expect(await store.read(), _session);
  });

  test('when the secure store fails to read, the person signs in again and nothing crashes', () async {
    await store.write(_session);
    secrets.broken = true;
    expect(await store.read(), isNull);
  });

  test('after the secure store recovers, a database fallback is moved in on the next read', () async {
    secrets.broken = true;
    await store.write(_session);
    secrets.broken = false;
    expect(await store.read(), _session);
    expect(secrets.values[SettingsSessionStore.key], _session);
    expect(await inDatabase(), SettingsSessionStore.secureMarker);
  });

  test('signing out clears both, even when the secure store is down', () async {
    await store.write(_session);
    await store.write(null);
    expect(secrets.values, isEmpty);
    expect(await inDatabase(), '');
    expect(await store.read(), isNull);

    await store.write(_session);
    secrets.broken = true;
    await store.write(null);
    expect(await inDatabase(), '', reason: 'the database says no session, whatever the secure store holds');
    secrets.broken = false;
    expect(await store.read(), isNull);
  });

  test('a Keychain item an earlier install left on an iPhone does not sign a fresh install in', () async {
    secrets.values[SettingsSessionStore.key] = _session; // survived the uninstall
    expect(await inDatabase(), isNull, reason: 'a fresh database has no marker');
    expect(await store.read(), isNull);
  });

  test('a saved session still counts as saved for the consent flush (the marker is not empty)', () async {
    await store.write(_session);
    final saved = await db.settingsDao.get(cloudSessionSettingsKey);
    expect(saved, isNotNull);
    expect(saved, isNotEmpty);
    await store.write(null);
    expect(await db.settingsDao.get(cloudSessionSettingsKey), isEmpty);
  });

  test('erasing the phone also erases the token from the secure store', () async {
    final root = Directory.systemTemp.createTempSync('erase-secrets');
    addTearDown(() => root.deleteSync(recursive: true));
    final docs = Directory(p.join(root.path, 'docs'))..createSync();
    await store.write(_session);
    expect(secrets.values, isNotEmpty);
    await PhoneEraser(db, databasePath: () async => p.join(docs.path, 'fieldos.sqlite'), folders: () async => [docs], secrets: secrets)
        .erase();
    expect(secrets.values, isEmpty);
    expect(await store.read(), isNull);
  });

  test('erasing still works when the secure store is down', () async {
    final root = Directory.systemTemp.createTempSync('erase-secrets');
    addTearDown(() => root.deleteSync(recursive: true));
    final docs = Directory(p.join(root.path, 'docs'))..createSync();
    await store.write(_session);
    secrets.broken = true;
    await PhoneEraser(db, databasePath: () async => p.join(docs.path, 'fieldos.sqlite'), folders: () async => [docs], secrets: secrets)
        .erase();
    expect(await inDatabase(), isNull, reason: 'the marker is gone, so the leftover cannot be used');
    secrets.broken = false;
    expect(await store.read(), isNull);
  });
}
