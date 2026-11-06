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

  /// The server (Supabase, mirroring the desktop backend) names roles
  /// owner / project_manager / site_engineer; the app's local vocabulary
  /// is owner / manager / member.
  static String fromCloud(String cloudRole) => switch (cloudRole) {
        'owner' => owner,
        'project_manager' => manager,
        _ => member,
      };

  static String toCloud(String localRole) => switch (localRole) {
        owner => 'owner',
        manager => 'project_manager',
        _ => 'site_engineer',
      };
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

  /// Shortest password a new account may have.
  static const minPasswordLength = 6;

  static final _usernamePattern = RegExp(r'^[\p{L}\p{N}._@+-]{3,40}$', unicode: true);

  /// Create an account. Usernames are kept in lower case so "Ravi" can log
  /// in as "ravi". Throws [AuthException] with a message for the screen.
  Future<User> register({
    required String username,
    required String name,
    required String password,
  }) async {
    final clean = username.trim().toLowerCase();
    if (clean.isEmpty) throw AuthException('Choose a username.');
    if (name.trim().isEmpty) throw AuthException('Enter your name.');
    if (password.isEmpty) throw AuthException('Choose a password.');
    if (!_usernamePattern.hasMatch(clean)) {
      throw AuthException('Usernames are 3 to 40 letters or numbers, with no spaces (dots, dashes, _ and @ are fine).');
    }
    if (password.length < minPasswordLength) {
      throw AuthException('Use at least $minPasswordLength characters for the password.');
    }
    final existing = await db.userDao.byUsernameIgnoringCase(clean);
    if (existing != null) {
      throw AuthException('That username is already taken on this phone. Log in instead, or pick another.');
    }
    final user = UsersCompanion.insert(
      id: const Uuid().v4(),
      username: clean,
      name: name.trim(),
      passwordHash: await hashPassword(password),
    );
    await db.userDao.create(user);
    return (await db.userDao.byUsername(clean))!;
  }

  /// Returns a session token on success, throws [AuthException] otherwise.
  Future<String> login(String username, String password) async {
    final typed = username.trim();
    if (typed.isEmpty || password.isEmpty) throw AuthException('Enter your username and password.');
    // Exact first (accounts made before usernames were kept in lower
    // case), then ignoring capitals.
    final user = await db.userDao.byUsername(typed) ?? await db.userDao.byUsernameIgnoringCase(typed);
    if (user == null) throw AuthException('That username or password is not right.');
    final ok = await verifyPassword(password, user.passwordHash);
    if (!ok) throw AuthException('That username or password is not right.');
    final token = newSessionToken();
    await db.sessionDao.create(SessionsCompanion.insert(
      token: token,
      userId: user.id,
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    ));
    return token;
  }

  Future<void> logout(String token) => db.sessionDao.deleteByToken(token);

  /// Changes the password of [userId] after checking the current one.
  /// Throws [AuthException] with a message for the screen.
  Future<void> changePassword({required String userId, required String current, required String next}) async {
    final user = await db.userDao.byId(userId);
    if (user == null) throw AuthException('This account is no longer on this phone.');
    if (!await verifyPassword(current, user.passwordHash)) {
      throw AuthException('Your current password is not right.');
    }
    if (next.length < minPasswordLength) {
      throw AuthException('Use at least $minPasswordLength characters for the new password.');
    }
    if (next == current) throw AuthException('The new password is the same as the current one.');
    await db.userDao.setPasswordHash(userId, await hashPassword(next));
  }

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

  /// Longest company name the app accepts.
  static const maxCompanyNameLength = 80;

  /// Create a company and make [userId] its owner. Throws [AuthException]
  /// with a message for the screen when the name is unusable.
  Future<Company> createCompany({
    required String userId,
    required String name,
  }) async {
    final cleaned = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) throw AuthException('Enter your company name.');
    if (cleaned.length > maxCompanyNameLength) {
      throw AuthException('Use at most $maxCompanyNameLength characters for the company name.');
    }
    final company = await db.companyDao.create(cleaned);
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
