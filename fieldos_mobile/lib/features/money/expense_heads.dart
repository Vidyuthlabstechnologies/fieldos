/// Expense heads and who sees site finance. Every expense falls under one
/// of four heads (Material, Equipment, Labour, Others), whatever category
/// it was filed under; tea, food and the like are informal spend inside
/// Others, so management sees how much goes on them without a head of
/// their own. Wage rates, dues and what was paid out to vendors are for
/// the site's management and accounts; everyone else sees only the
/// entries they recorded themselves (the server enforces the same, see
/// supabase/migrations/20261125130000_finance_privacy.sql).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/auth/site_roles.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/team/site_team_screen.dart' show mySiteAccessProvider;
import 'package:fieldos_mobile/l10n/language.dart';

enum ExpenseHead { material, equipment, labour, others }

String expenseHeadLabel(ExpenseHead h) => switch (h) {
      ExpenseHead.material => tr('Material'),
      ExpenseHead.equipment => tr('Equipment'),
      ExpenseHead.labour => tr('Labour'),
      ExpenseHead.others => tr('Others'),
    };

final _informalWords = RegExp(r'\b(tea|chai|coffee|food|snack|snacks|biscuit|biscuits|lunch|breakfast|dinner|water|pan|paan|gutka|cigarette|misc|miscellaneous)\b',
    caseSensitive: false);

/// Tea, food and other small informal spend.
bool isInformalCategory(String category) => _informalWords.hasMatch(category);

/// The head a category rolls up to. Fuel and transport of equipment belong
/// with Equipment; Material and Labour are their own heads; anything else,
/// including every informal category, is Others.
ExpenseHead expenseHeadOf(String category) {
  final c = category.toLowerCase();
  if (isInformalCategory(category)) return ExpenseHead.others;
  if (c.contains('material') || c.contains('cement') || c.contains('steel') || c.contains('sand') || c.contains('aggregate')) {
    return ExpenseHead.material;
  }
  if (c.contains('labour') || c.contains('labor') || c.contains('wage') || c.contains('salary') || c.contains('contractor')) {
    return ExpenseHead.labour;
  }
  if (c.contains('equipment') || c.contains('machine') || c.contains('fuel') || c.contains('diesel') || c.contains('hire')) {
    return ExpenseHead.equipment;
  }
  return ExpenseHead.others;
}

class HeadTotal {
  const HeadTotal(this.head, this.amount, this.count, this.informal);
  final ExpenseHead head;
  final double amount;
  final int count;

  /// Of [amount], what was tea, food and the like (only under Others).
  final double informal;
}

/// All four heads in order, cancelled entries left out.
List<HeadTotal> headTotals(Iterable<SiteExpense> xs) {
  final sums = {for (final h in ExpenseHead.values) h: 0.0};
  final counts = {for (final h in ExpenseHead.values) h: 0};
  var informal = 0.0;
  for (final e in xs.where((e) => !e.voided)) {
    final h = expenseHeadOf(e.category);
    sums[h] = sums[h]! + e.amount;
    counts[h] = counts[h]! + 1;
    if (isInformalCategory(e.category)) informal += e.amount;
  }
  return [for (final h in ExpenseHead.values) HeadTotal(h, sums[h]!, counts[h]!, h == ExpenseHead.others ? informal : 0)];
}

/// Wage rates, dues and vendor payouts: the site's management and accounts.
bool canSeeSiteFinance(SiteAccessFor? a) => a != null && (a.managesSite || a.siteRole == SiteRole.accounts);

/// Whether this person sees wage rates, dues and payouts on the site.
final siteFinanceProvider = FutureProvider.autoDispose.family<bool, String>((ref, projectId) async {
  return canSeeSiteFinance(await ref.watch(mySiteAccessProvider(projectId).future));
});
