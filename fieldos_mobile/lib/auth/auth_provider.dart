/// App session state: the logged-in user, their companies, and which company
/// is currently active. Persists the session token locally so the app opens
/// straight back into the last session (offline, no re-login needed).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/providers.dart' show appDatabaseProvider, authServiceProvider;

const _activeSessionKey = 'active_session_token';

class SessionState {
  const SessionState({
    this.user,
    this.token,
    this.companies = const [],
    this.activeCompany,
    this.role,
    this.restoring = false,
  });

  /// Still reading the saved session at launch: show the splash, not the
  /// login screen (which used to flash up on every start).
  final bool restoring;
  final User? user;
  final String? token;
  final List<Company> companies;
  final Company? activeCompany;
  final String? role;

  bool get isAuthenticated => user != null && token != null;
  bool get needsCompany => isAuthenticated && companies.isEmpty;
  bool get canManageSettings => role != null && Roles.canManageSettings(role!);
}

class SessionNotifier extends Notifier<SessionState> {
  late AuthService _auth;
  late AppDatabase _db;

  @override
  SessionState build() {
    _auth = ref.watch(authServiceProvider);
    _db = ref.watch(appDatabaseProvider);
    _bootstrap();
    return const SessionState(restoring: true);
  }

  Future<void> _bootstrap() async {
    try {
      await _restore();
    } catch (_) {
      // A damaged session row must not leave the app stuck on the splash.
      state = const SessionState();
    }
  }

  Future<void> _restore() async {
    final token = await _db.settingsDao.get(_activeSessionKey);
    final user = await _auth.userForSession(token);
    if (user == null) {
      state = const SessionState();
      return;
    }
    final companies = await _auth.companiesFor(user.id);
    final activeCompany = companies.isNotEmpty ? companies.first : null;
    final role = activeCompany != null
        ? await _auth.roleInCompany(userId: user.id, companyId: activeCompany.id)
        : null;
    state = SessionState(
      user: user,
      token: token,
      companies: companies,
      activeCompany: activeCompany,
      role: role,
    );
  }

  /// Creates the account and signs straight in: "Create account" used to
  /// leave people on the sign-up form with no session.
  Future<void> register({
    required String username,
    required String name,
    required String password,
  }) async {
    final user = await _auth.register(username: username, name: name, password: password);
    await login(user.username, password);
  }

  Future<void> login(String username, String password) => _open(_auth.login(username, password));

  /// After Google confirmed who this is: opens (or makes) their account.
  Future<void> loginWithGoogle({required String email, required String name}) =>
      _open(_auth.loginWithGoogle(email: email, name: name));

  Future<void> _open(Future<String> signIn) async {
    final token = await signIn;
    final user = await _auth.userForSession(token);
    if (user == null) throw StateError('Session resolution failed after login.');
    await _db.settingsDao.set(_activeSessionKey, token);
    final companies = await _auth.companiesFor(user.id);
    final activeCompany = companies.isNotEmpty ? companies.first : null;
    final role = activeCompany != null
        ? await _auth.roleInCompany(userId: user.id, companyId: activeCompany.id)
        : null;
    state = SessionState(
      user: user,
      token: token,
      companies: companies,
      activeCompany: activeCompany,
      role: role,
    );
  }

  Future<Company> createCompany(String name) async {
    final user = state.user;
    if (user == null) throw StateError('Not authenticated.');
    final company = await _auth.createCompany(userId: user.id, name: name);
    final companies = [...state.companies, company];
    await _selectCompany(company, companies);
    return company;
  }

  /// After joining a company on the cloud: mirror it (and this user's
  /// server-side role) locally and make it the active company.
  Future<Company> adoptCloudCompany({required String id, required String name, required String role}) async {
    final user = state.user;
    if (user == null) throw StateError('Not authenticated.');
    final company = await _db.companyDao.ensureWithId(id, name);
    await _db.companyDao.upsertMemberRole(companyId: id, userId: user.id, role: Roles.fromCloud(role));
    final companies = await _auth.companiesFor(user.id);
    await _selectCompany(company, companies);
    return company;
  }

  /// Applies a server-side role ([role] in the cloud vocabulary) locally (e.g. after the owner changed it
  /// on the server and a sync brought it down).
  Future<void> setLocalRole(String companyId, String role) async {
    final user = state.user;
    if (user == null) return;
    await _db.companyDao.upsertMemberRole(companyId: companyId, userId: user.id, role: Roles.fromCloud(role));
    final active = state.activeCompany;
    if (active != null && active.id == companyId) await _selectCompany(active, state.companies);
  }

  Future<void> selectCompany(Company company) => _selectCompany(company, state.companies);

  Future<void> _selectCompany(Company company, List<Company> companies) async {
    final user = state.user;
    if (user == null) return;
    final role = await _auth.roleInCompany(userId: user.id, companyId: company.id);
    state = state.copyWith(activeCompany: company, companies: companies, role: role);
  }

  Future<void> logout() async {
    final token = state.token;
    if (token != null) await _auth.logout(token);
    await _db.settingsDao.set(_activeSessionKey, '');
    state = const SessionState();
  }

  SessionState get current => state;
}

extension on SessionState {
  SessionState copyWith({
    User? user,
    String? token,
    List<Company>? companies,
    Company? activeCompany,
    String? role,
  }) =>
      SessionState(
        user: user ?? this.user,
        token: token ?? this.token,
        companies: companies ?? this.companies,
        activeCompany: activeCompany ?? this.activeCompany,
        role: role ?? this.role,
      );
}
