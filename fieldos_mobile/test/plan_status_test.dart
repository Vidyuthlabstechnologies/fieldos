import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/sync/plan_status.dart';

void main() {
  test('free plan reads members against the limit', () {
    final p = PlanStatus.fromJson({'plan': 'free', 'expires_at': null, 'members': 3, 'member_limit': 3});
    expect(p.isPaid, isFalse);
    expect(p.isFull, isTrue);
    expect(p.describe(), 'Free plan · 3 of 3 people');
  });

  test('team plan has no limit and shows its end date', () {
    final p = PlanStatus.fromJson({'plan': 'team', 'expires_at': '2026-12-05T00:00:00Z', 'members': 12, 'member_limit': null});
    expect(p.isPaid, isTrue);
    expect(p.isFull, isFalse);
    expect(p.describe(), startsWith('Team plan · 12 people'));
  });
}
