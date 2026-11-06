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
        password: 'pw1234',
      );
      expect(user.id, isNotEmpty);

      final token = await auth.login('alice', 'pw1234');
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
      await auth.register(username: 'bob', name: 'Bob', password: 'pw1234');
      expect(
        () => auth.register(username: 'bob', name: 'Bob2', password: 'pw1234'),
        throwsA(isA<AuthException>()),
      );
      // Capitals don't make a different person.
      expect(
        () => auth.register(username: 'BOB', name: 'Bob3', password: 'pw1234'),
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

    test('new accounts need a 6-character password and a username without spaces', () async {
      final db = AppDatabase.memory();
      addTearDown(() async => db.close());
      final auth = AuthService(db);
      expect(() => auth.register(username: 'dev', name: 'Dev', password: '12345'), throwsA(isA<AuthException>()));
      expect(() => auth.register(username: 'ravi kumar', name: 'Ravi', password: '123456'), throwsA(isA<AuthException>()));
      final u = await auth.register(username: '  Ravi.K ', name: ' Ravi Kumar ', password: '123456');
      expect(u.username, 'ravi.k');
      expect(u.name, 'Ravi Kumar');
    });

    test('login ignores capitals and spaces around the username', () async {
      final db = AppDatabase.memory();
      addTearDown(() async => db.close());
      final auth = AuthService(db);
      await auth.register(username: 'meena', name: 'Meena', password: 'secret1');
      expect(await auth.login(' Meena ', 'secret1'), isNotEmpty);
      // An account made before usernames were lower-cased still works.
      await db.userDao.create(UsersCompanion.insert(
        id: 'old-user',
        username: 'Suresh',
        name: 'Suresh',
        passwordHash: await hashPassword('oldpass'),
      ));
      expect(await auth.login('Suresh', 'oldpass'), isNotEmpty);
      expect(await auth.login('suresh', 'oldpass'), isNotEmpty);
    });

    test('a company needs a name, which is tidied before saving', () async {
      final db = AppDatabase.memory();
      addTearDown(() async => db.close());
      final auth = AuthService(db);
      final u = await auth.register(username: 'owner', name: 'Owner', password: '123456');
      expect(
        () => auth.createCompany(userId: u.id, name: '   '),
        throwsA(isA<AuthException>().having((e) => e.message, 'message', 'Enter your company name.')),
      );
      expect(() => auth.createCompany(userId: u.id, name: 'x' * 81), throwsA(isA<AuthException>()));
      final c = await auth.createCompany(userId: u.id, name: '  Sri   Sai Constructions ');
      expect(c.name, 'Sri Sai Constructions');
      expect(await auth.roleInCompany(userId: u.id, companyId: c.id), Roles.owner);
    });

    test('changing the password checks the current one', () async {
      final db = AppDatabase.memory();
      addTearDown(() async => db.close());
      final auth = AuthService(db);
      final u = await auth.register(username: 'asha', name: 'Asha', password: 'first1');
      expect(() => auth.changePassword(userId: u.id, current: 'wrong1', next: 'second2'),
          throwsA(isA<AuthException>().having((e) => e.message, 'message', 'Your current password is not right.')));
      expect(() => auth.changePassword(userId: u.id, current: 'first1', next: '123'), throwsA(isA<AuthException>()));
      await auth.changePassword(userId: u.id, current: 'first1', next: 'second2');
      expect(await auth.login('asha', 'second2'), isNotEmpty);
      expect(() => auth.login('asha', 'first1'), throwsA(isA<AuthException>()));
    });
  });
}
