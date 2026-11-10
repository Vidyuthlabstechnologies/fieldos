/// Multi-level approvals by amount, on plain values.
///
/// The owner sets, for each kind of item, the amount above which a
/// project manager must approve and the amount above which the owner must
/// too. An item's chain is the levels its amount crosses, lowest first.
/// It is complete when every level has an approval at that level or above;
/// an owner's approval covers the project manager's level too. One
/// rejection at any level stops the item.
library;

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/auth/site_roles.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/l10n/language.dart';

abstract final class ApprovalKind {
  static const purchaseRequest = 'purchase_request';
  static const expense = 'expense';
  static const purchaseOrder = 'purchase_order';
  static const all = [purchaseRequest, expense, purchaseOrder];

  static String label(String kind) => switch (kind) {
    purchaseRequest => tr('Purchase requests'),
    expense => tr('Expenses'),
    purchaseOrder => tr('Purchase orders'),
    _ => kind,
  };
}

abstract final class ApprovalLevel {
  static const projectManager = 'project_manager';
  static const owner = 'owner';

  /// Lowest first.
  static const order = [projectManager, owner];
  static int rank(String level) => order.indexOf(level);

  static String label(String level) => switch (level) {
    projectManager => tr('Project manager'),
    owner => tr('Owner'),
    _ => level,
  };
}

/// The levels an item of [kind] for [amount] needs, lowest first. A rule
/// covers items recorded ([createdAt]) after it was made, so setting one
/// doesn't hold up last month's records.
List<String> requiredLevels(List<ApprovalRule> rules, String kind, double amount, {DateTime? createdAt}) {
  final out = <String>{
    for (final r in rules)
      if (!r.voided &&
          r.kind == kind &&
          amount.abs() > r.aboveAmount + 0.005 &&
          (createdAt == null || !createdAt.isBefore(r.createdAt)))
        r.role,
  };
  return ApprovalLevel.order.where(out.contains).toList();
}

class ChainStatus {
  const ChainStatus({required this.required, required this.approved, this.rejectedBy});

  /// Levels this item needs, lowest first. Empty: no approval needed.
  final List<String> required;

  /// Approvals so far.
  final List<ApprovalStep> approved;

  /// The rejection, if anyone rejected it.
  final ApprovalStep? rejectedBy;

  bool get rejected => rejectedBy != null;

  int get _top => approved.fold(-1, (m, s) => ApprovalLevel.rank(s.level) > m ? ApprovalLevel.rank(s.level) : m);

  /// Levels still to sign, lowest first.
  List<String> get waitingFor => [
    for (final l in required)
      if (ApprovalLevel.rank(l) > _top) l,
  ];

  /// The next level to sign, or null when complete or rejected.
  String? get next => rejected || waitingFor.isEmpty ? null : waitingFor.first;

  bool get complete => !rejected && waitingFor.isEmpty;

  /// Short state for a list row.
  String get label {
    if (rejected) return tr('Rejected');
    final n = next;
    if (n == null) return required.isEmpty ? '' : tr('Approved');
    return n == ApprovalLevel.owner
        ? tr("Waiting for the owner's approval")
        : tr("Waiting for a project manager's approval");
  }
}

ChainStatus chainStatus(List<String> required, Iterable<ApprovalStep> steps) {
  final approved = <ApprovalStep>[];
  ApprovalStep? rejected;
  for (final s in steps) {
    if (s.decision == 'rejected') {
      rejected ??= s;
    } else if (s.decision == 'approved') {
      approved.add(s);
    }
  }
  return ChainStatus(required: required, approved: approved, rejectedBy: rejected);
}

/// The level this person signs at on this site, when they can sign the
/// chain's next level for [amount]: the owner signs as owner (covering
/// every level); a project manager, within their approval limit, signs
/// the project manager's level. Null when they can't sign now.
String? signingLevel(ChainStatus chain, SiteAccessFor access, double amount) {
  final next = chain.next;
  if (next == null) return null;
  if (access.companyRole == Roles.owner) return ApprovalLevel.owner;
  if (next == ApprovalLevel.projectManager && access.canApprove(amount)) return ApprovalLevel.projectManager;
  return null;
}
