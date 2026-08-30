import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/crypto.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('offline auth', () {
    test('password hash verifies and rejects', () async {
      final hash = await hashPassword('s3cret');
      expect(hash, startsWith('pbkdf2:'));
      expect(await verifyPassword('s3cret', hash), isTrue);
      expect(await verifyPassword('wrong', hash), isFalse);
    });

    test('register -> login -> session resolves', () async {
      final db = AppDatabase.memory();
      addTearDown(() async => db.close());
      final auth = AuthService(db);

      final user = await auth.register(
        username: 'alice',
        name: 'Alice',
        password: 'pw',
      );
      expect(user.id, isNotEmpty);

      final token = await auth.login('alice', 'pw');
      expect(token, isNotEmpty);

      final resolved = await auth.userForSession(token);
      expect(resolved?.id, user.id);

      // Wrong password yields no token.
      expect(() => auth.login('alice', 'nope'), throwsA(isA<AuthException>()));

      // Expired / bogus token resolves to null.
      expect(await auth.userForSession('bogus'), isNull);
    });

    test('register twice with same username is rejected', () async {
      final db = AppDatabase.memory();
      addTearDown(() async => db.close());
      final auth = AuthService(db);
      await auth.register(username: 'bob', name: 'Bob', password: 'pw');
      expect(
        () => auth.register(username: 'bob', name: 'Bob2', password: 'pw'),
        throwsA(isA<AuthException>()),
      );
    });

    test('register rejects empty fields with a clean AuthException, not a raw DB error', () async {
      final db = AppDatabase.memory();
      addTearDown(() async => db.close());
      final auth = AuthService(db);

      // Each of these must fail validation *before* reaching the database --
      // an empty username used to slip through to the Drift insert, which
      // throws an InvalidDataException whose toString() includes the full
      // row (including the password hash). That must never reach the UI.
      expect(
        () => auth.register(username: '', name: 'Carl', password: 'pw'),
        throwsA(isA<AuthException>()),
      );
      expect(
        () => auth.register(username: 'carl', name: '', password: 'pw'),
        throwsA(isA<AuthException>()),
      );
      expect(
        () => auth.register(username: 'carl', name: 'Carl', password: ''),
        throwsA(isA<AuthException>()),
      );

      // Confirm nothing was actually written to the database by the empty-username attempt.
      expect(await db.userDao.byUsername(''), isNull);
    });
  });
}
