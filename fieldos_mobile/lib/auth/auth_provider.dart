/// App session state: the logged-in user, their companies, and which company
/// is currently active. Persists the session token locally so the app opens
/// straight back into the last session (offline, no re-login needed).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/data/app_database.dart';

const _activeSessionKey = 'active_session_token';

class SessionState {
  const SessionState({
    this.user,
    this.token,
    this.companies = const [],
    this.activeCompany,
    this.role,
  });
  final User? user;
  final String? token;
  final List<Company> companies;
  final Company? activeCompany;
  final String? role;

  bool get isAuthenticated => user != null && token != null;
  bool get needsCompany => isAuthenticated && companies.isEmpty;
  bool get canManageSettings => role != null && Roles.canManageSettings(role!);
}

class SessionNotifier extends StateNotifier<SessionState> {
  SessionNotifier(this._auth, this._db) : super(const SessionState()) {
    _bootstrap();
  }
  final AuthService _auth;
  final AppDatabase _db;

  Future<void> _bootstrap() async {
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

  Future<void> register({
    required String username,
    required String name,
    required String password,
  }) async {
    final user = await _auth.register(username: username, name: name, password: password);
    state = SessionState(user: user, companies: const [], token: null);
  }

  Future<void> login(String username, String password) async {
    final token = await _auth.login(username, password);
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
