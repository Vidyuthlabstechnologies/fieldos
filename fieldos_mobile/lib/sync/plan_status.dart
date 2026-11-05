/// A company's paid plan, as the server's company_plan RPC reports it.
library;

/// A company's plan as the server reports it.
class PlanStatus {
  const PlanStatus({required this.plan, this.expiresAt, required this.members, this.memberLimit});

  factory PlanStatus.fromJson(Map<String, dynamic> j) => PlanStatus(
        plan: j['plan'] as String,
        expiresAt: j['expires_at'] == null ? null : DateTime.parse(j['expires_at'] as String),
        members: j['members'] as int,
        memberLimit: j['member_limit'] as int?,
      );

  final String plan;
  final DateTime? expiresAt;
  final int members;
  final int? memberLimit;

  bool get isPaid => plan == 'team';
  bool get isFull => memberLimit != null && members >= memberLimit!;

  String describe() {
    if (isPaid) {
      final e = expiresAt?.toLocal();
      final until = e == null ? '' : ' · renews or ends ${e.day}-${e.month}-${e.year}';
      return 'Team plan · $members people$until';
    }
    return 'Free plan · $members of $memberLimit people';
  }
}
