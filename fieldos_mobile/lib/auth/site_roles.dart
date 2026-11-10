/// Site roles: what a person may do on one site, from their company role
/// and their row on the site's team (if any). Mirrors the server's
/// is_project_owner_or_pm and can_approve_on_site (20261110210000_site_roles.sql).
library;

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/l10n/language.dart';

class SiteRole {
  static const owner = 'owner';
  static const projectManager = 'project_manager';
  static const siteEngineer = 'site_engineer';
  static const accounts = 'accounts';
  static const storekeeper = 'storekeeper';
  static const viewer = 'viewer';

  static const all = siteRoleValues;

  static String label(String role) => switch (role) {
        owner => tr('Owner'),
        projectManager => tr('Project manager'),
        siteEngineer => tr('Site engineer'),
        accounts => tr('Accounts'),
        storekeeper => tr('Storekeeper'),
        viewer => tr('Viewer'),
        _ => role,
      };

  /// One line on what the role does on a site.
  static String explain(String role) => switch (role) {
        owner => tr('Everything on this site.'),
        projectManager => tr('Runs the site and approves up to their limit.'),
        siteEngineer => tr('Records the day: reports, labour, money, material.'),
        accounts => tr('Sees the money and sends packs to accounts.'),
        storekeeper => tr('Receives material and keeps the stock.'),
        viewer => tr('Can see the site, changes nothing.'),
        _ => '',
      };
}

/// What one person may do on one site.
class SiteAccessFor {
  const SiteAccessFor({required this.companyRole, this.member});

  /// The app's company role: owner / manager / member / viewer.
  final String companyRole;

  /// Their row on the site's team, if any.
  final ProjectMember? member;

  /// The company's owner and managers run every site.
  bool get isCompanyManager => companyRole == Roles.owner || companyRole == Roles.manager;

  /// Owner or project manager of this site.
  bool get managesSite =>
      isCompanyManager ||
      (companyRole != Roles.viewer && (member?.role == SiteRole.owner || member?.role == SiteRole.projectManager));

  /// The role that applies on this site, in site-role words.
  String get siteRole {
    final m = member;
    if (companyRole == Roles.owner) return SiteRole.owner;
    if (m != null) return m.role;
    return switch (companyRole) {
      Roles.manager => SiteRole.projectManager,
      Roles.viewer => SiteRole.viewer,
      _ => SiteRole.siteEngineer,
    };
  }

  bool get canWrite => companyRole != Roles.viewer && siteRole != SiteRole.viewer;

  /// The most this person may approve in one item; null means no limit.
  /// The owner has none. A team row decides for anyone on it; a company
  /// manager without a row has none.
  double? get approvalLimit {
    if (companyRole == Roles.owner) return null;
    final m = member;
    if (m != null) return m.approvalLimit;
    return null;
  }

  bool canApprove(double amount) {
    if (companyRole == Roles.owner) return true;
    final m = member;
    if (m != null) {
      if (companyRole == Roles.viewer) return false;
      if (m.role != SiteRole.owner && m.role != SiteRole.projectManager) return false;
      final limit = m.approvalLimit;
      return limit == null || amount.abs() <= limit + 0.005;
    }
    return companyRole == Roles.manager;
  }
}

/// [userId] is this phone's own user id; [cloudUserId] the same person's
/// cloud account. A team row added on another phone names the cloud
/// account until the next pull turns it into this phone's id, so both are
/// looked up.
Future<SiteAccessFor> siteAccessFor(AppDatabase db, String projectId,
    {required String? userId, required String? companyRole, String? cloudUserId}) async {
  ProjectMember? member;
  for (final id in [userId, cloudUserId]) {
    if (id == null || id.isEmpty) continue;
    member = await db.siteTeamDao.memberOf(projectId, id);
    if (member != null) break;
  }
  return SiteAccessFor(companyRole: companyRole ?? Roles.viewer, member: member);
}

/// What one person may change on a site's team. Mirrors the server's
/// project_members policies: the company's owners and managers change
/// anything; a site's own manager adds and changes others, but can't hand
/// out "owner", change their own row or remove themselves.
class TeamRules {
  const TeamRules(this.access);
  final SiteAccessFor access;

  bool get canManageTeam => access.managesSite && access.canWrite;
  bool get canSetMembersOnly => access.isCompanyManager;
  List<String> get rolesTheyCanGive =>
      access.isCompanyManager ? SiteRole.all : SiteRole.all.where((r) => r != SiteRole.owner).toList();

  /// [isSelf]: the row is the person's own. [role]: the row's current role.
  bool canChange({required bool isSelf, required String role}) {
    if (!canManageTeam) return false;
    if (access.isCompanyManager) return true;
    return !isSelf && role != SiteRole.owner;
  }

  bool canRemove({required bool isSelf, required String role}) => canChange(isSelf: isSelf, role: role);
}

/// The company's sites this person may see on the phone: all of them for
/// the company's owners and managers, and every site except members-only
/// ones they aren't on for everyone else (the server's has_project_access).
Future<Set<String>> visibleSiteIds(AppDatabase db, String companyId,
    {required String? userId, required String? companyRole, String? cloudUserId}) async {
  final ids = [for (final p in await db.projectDao.forCompany(companyId)) p.id];
  if (companyRole == Roles.owner || companyRole == Roles.manager) return ids.toSet();
  final hidden = await db.siteTeamDao.membersOnlySites(ids);
  if (hidden.isEmpty) return ids.toSet();
  final me = {userId, cloudUserId}.whereType<String>().where((i) => i.isNotEmpty).toSet();
  final teams = await db.siteTeamDao.membersByProject(hidden);
  return {
    for (final id in ids)
      if (!hidden.contains(id) || (teams[id] ?? const []).any((m) => me.contains(m.userId))) id,
  };
}
