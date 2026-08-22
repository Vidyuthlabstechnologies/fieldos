/// Local, offline authentication: account creation, login, opaque session
/// tokens, and company ownership. Mirrors the desktop app's auth model.
library;

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/core/crypto.dart';
import 'package:uuid/uuid.dart';

/// Roles within a company. Ordered by privilege for convenience checks.
class Roles {
  static const owner = 'owner';
  static const manager = 'manager';
  static const member = 'member';
  static const viewer = 'viewer';

  /// Only an owner may configure installation-wide settings (e.g. the Sarvam
  /// API key) — matching the desktop app's authorization gap fix.
  static bool canManageSettings(String role) => role == owner;

  static bool canWrite(String role) => role != viewer;
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

class AuthService {
  AuthService(this.db);
  final AppDatabase db;

  /// Create the first account. Throws [AuthException] if the username exists.
  Future<User> register({
    required String username,
    required String name,
    required String password,
  }) async {
    final existing = await db.userDao.byUsername(username);
    if (existing != null) {
      throw AuthException('That username is already taken.');
    }
    final user = UsersCompanion.insert(
      id: Uuid().v4(),
      username: username,
      name: name,
      passwordHash: await hashPassword(password),
    );
    await db.userDao.create(user);
    return (await db.userDao.byUsername(username))!;
  }

  /// Returns a session token on success, throws [AuthException] otherwise.
  Future<String> login(String username, String password) async {
    final user = await db.userDao.byUsername(username);
    if (user == null) throw AuthException('Invalid username or password.');
    final ok = await verifyPassword(password, user.passwordHash);
    if (!ok) throw AuthException('Invalid username or password.');
    final token = newSessionToken();
    await db.sessionDao.create(SessionsCompanion.insert(
      token: token,
      userId: user.id,
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    ));
    return token;
  }

  Future<void> logout(String token) => db.sessionDao.deleteByToken(token);

  /// Resolve a session token to its user, or null if missing/expired.
  Future<User?> userForSession(String? token) async {
    if (token == null || token.isEmpty) return null;
    final session = await db.sessionDao.byToken(token);
    if (session == null) return null;
    if (session.expiresAt.isBefore(DateTime.now())) {
      await db.sessionDao.deleteByToken(token);
      return null;
    }
    return db.userDao.byId(session.userId);
  }

  /// Create a company and make [userId] its owner.
  Future<Company> createCompany({
    required String userId,
    required String name,
  }) async {
    final company = await db.companyDao.create(name);
    await db.companyDao.addMember(
      companyId: company.id,
      userId: userId,
      role: Roles.owner,
    );
    return company;
  }

  Future<String?> roleInCompany({
    required String userId,
    required String companyId,
  }) =>
      db.companyDao.roleOf(companyId, userId);

  Future<List<Company>> companiesFor(String userId) =>
      db.companyDao.forUser(userId);
}
