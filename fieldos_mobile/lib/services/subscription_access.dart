/// Whether this phone may use FieldOS right now. Pure logic, kept apart
/// from the store SDK so it can be tested.
///
/// Pricing: everyone pays. Each person starts with the store's 3-day free
/// trial (set up on the subscription in Play Console / App Store Connect,
/// so Google and Apple decide who is eligible and charge when it ends),
/// then the subscription renews until cancelled.
library;

class SubscriptionState {
  const SubscriptionState({required this.active, this.inTrial = false, this.expiresAt, this.willRenew = false});

  static const none = SubscriptionState(active: false);

  final bool active;
  final bool inTrial;
  final DateTime? expiresAt;
  final bool willRenew;

  String describe() {
    if (!active) return 'No active subscription';
    final until = expiresAt == null ? '' : ' until ${_date(expiresAt!)}';
    if (inTrial) return willRenew ? 'Free trial$until, then paid' : 'Free trial$until (will not renew)';
    return willRenew ? 'Subscribed, renews${until.replaceFirst(' until', ' on')}' : 'Subscribed$until (cancelled)';
  }

  static String _date(DateTime d) {
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year}';
  }
}

/// How long a phone that was subscribed keeps working with no internet
/// after its paid-up date, since the store can't be asked offline.
const offlineGrace = Duration(days: 3);

enum Access { allowed, blocked }

/// [billingSetUp] is false in builds without store keys (development, or a
/// release before payments are configured): nothing is locked then.
/// [live] is the store's answer, or null when it couldn't be reached.
/// [lastPaidUntil] is the expiry remembered from the last good answer.
Access accessFor({
  required bool billingSetUp,
  required SubscriptionState? live,
  required DateTime? lastPaidUntil,
  required DateTime now,
}) {
  if (!billingSetUp) return Access.allowed;
  if (live != null) return live.active ? Access.allowed : Access.blocked;
  if (lastPaidUntil != null && now.isBefore(lastPaidUntil.add(offlineGrace))) return Access.allowed;
  return Access.blocked;
}
