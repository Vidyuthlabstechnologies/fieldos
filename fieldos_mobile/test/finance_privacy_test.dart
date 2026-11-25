/// Expense heads and who sees site finance: every category rolls up to
/// Material, Equipment, Labour or Others, tea and food sit inside Others
/// and are counted separately, cancelled entries do not add up, and only a
/// site's management and accounts see wage rates and payouts.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/auth/site_roles.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/money/expense_heads.dart';

SiteExpense _e(String category, double amount, {bool voided = false}) => SiteExpense(
      id: category + amount.toString(),
      projectId: 'p1',
      category: category,
      amount: amount,
      incurredOn: '2026-11-25',
      recordedBy: 'u1',
      createdAt: DateTime(2026, 11, 25),
      voided: voided,
      gstInterState: false,
    );

void main() {
  test('every category rolls up to one of four heads; tea and food are informal Others', () {
    expect(expenseHeadOf('Material'), ExpenseHead.material);
    expect(expenseHeadOf('Labour'), ExpenseHead.labour);
    expect(expenseHeadOf('Equipment hire'), ExpenseHead.equipment);
    expect(expenseHeadOf('Fuel'), ExpenseHead.equipment);
    expect(expenseHeadOf('Transport'), ExpenseHead.others);
    expect(expenseHeadOf('Food & tea'), ExpenseHead.others);
    expect(expenseHeadOf('Chai and biscuits'), ExpenseHead.others);
    expect(isInformalCategory('Food & tea'), isTrue);
    expect(isInformalCategory('Material'), isFalse);

    final t = headTotals([_e('Material', 1000), _e('Labour', 500), _e('Fuel', 200), _e('Food & tea', 80), _e('Transport', 120), _e('Material', 999, voided: true)]);
    expect([for (final h in t) (h.head, h.amount)], [
      (ExpenseHead.material, 1000.0),
      (ExpenseHead.equipment, 200.0),
      (ExpenseHead.labour, 500.0),
      (ExpenseHead.others, 200.0),
    ]);
    expect(t.last.informal, 80);
    expect(t.first.informal, 0);
  });

  test('only management and accounts see wage rates and payouts', () {
    SiteAccessFor on(String company, String? site) => SiteAccessFor(
        companyRole: company,
        member: site == null ? null : ProjectMember(id: 'm', projectId: 'p1', userId: 'u', role: site, createdAt: DateTime(2026), updatedAt: DateTime(2026)));
    expect(canSeeSiteFinance(on('owner', null)), isTrue);
    expect(canSeeSiteFinance(on('manager', null)), isTrue);
    expect(canSeeSiteFinance(on('member', SiteRole.projectManager)), isTrue);
    expect(canSeeSiteFinance(on('member', SiteRole.accounts)), isTrue);
    expect(canSeeSiteFinance(on('member', SiteRole.siteEngineer)), isFalse);
    expect(canSeeSiteFinance(on('member', SiteRole.security)), isFalse);
    expect(canSeeSiteFinance(on('member', SiteRole.storekeeper)), isFalse);
    expect(canSeeSiteFinance(on('viewer', null)), isFalse);
    expect(canSeeSiteFinance(null), isFalse);
  });
}
