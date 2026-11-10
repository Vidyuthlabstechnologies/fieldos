/// The money book's rules, kept apart from the screens so they can be
/// tested: GST split, filters with their totals, the breakdown by
/// category, and the company's own expense categories.
///
/// From Onsite's Play reviews: "Please add gst charges in percentage (%)
/// also in CGST SGST IGST formet and auto calculation", "No voucher number
/// or transaction number available", "filter total is not showing", "I
/// cannot add any category", "pie chart to differentiate each and every
/// type of expenses".
library;

import 'dart:convert';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/l10n/language.dart';

/// The categories every company starts with.
const defaultExpenseCategories = ['Material', 'Labour', 'Transport', 'Equipment hire', 'Food & tea', 'Fuel', 'Other'];

/// GST rates offered as one tap.
const gstRates = [5.0, 12.0, 18.0, 28.0];

/// Rounds to paise, half up. The nudge keeps an exact half such as
/// 263.025 (stored as 263.02499...) from rounding down.
double _round2(double v) => ((v * 100) + (v < 0 ? -1e-6 : 1e-6)).roundToDouble() / 100;

/// What a GST bill is made of. [total] is what was paid.
class GstSplit {
  const GstSplit({required this.total, required this.taxable, required this.cgst, required this.sgst, required this.igst});

  final double total;
  final double taxable;
  final double cgst;
  final double sgst;
  final double igst;

  double get tax => cgst + sgst + igst;
}

/// Splits [total] (GST included) at [ratePct]: CGST and SGST half each,
/// or all IGST for a supplier in another state. Rounded to paise so the
/// parts always add back to the total.
GstSplit gstSplit(double total, double ratePct, {bool interState = false}) {
  if (ratePct <= 0) return GstSplit(total: total, taxable: total, cgst: 0, sgst: 0, igst: 0);
  final taxable = _round2(total * 100 / (100 + ratePct));
  final tax = _round2(total - taxable);
  if (interState) return GstSplit(total: total, taxable: taxable, cgst: 0, sgst: 0, igst: tax);
  final cgst = _round2(tax / 2);
  return GstSplit(total: total, taxable: taxable, cgst: cgst, sgst: _round2(tax - cgst), igst: 0);
}

/// The total to save when a bill's amount was typed before GST.
double withGst(double beforeGst, double ratePct) => _round2(beforeGst * (100 + ratePct) / 100);

/// "V-12", as printed on the voucher and shown in the list.
/// [provisional]: the phone's own number for an entry the server has not
/// numbered yet (see ExpenseDao.nextVoucherNo); it can still change.
String voucherLabel(int? n, {bool provisional = false}) =>
    n == null ? '' : (provisional ? trf('V-{n} (provisional)', {'n': n}) : 'V-$n');

enum MoneyPeriod { all, thisWeek, thisMonth, lastMonth, custom }

/// What the money list is narrowed to.
class MoneyFilter {
  const MoneyFilter({
    this.period = MoneyPeriod.all,
    this.from,
    this.to,
    this.category,
    this.workerId,
    this.query = '',
    this.showCancelled = true,
  });

  final MoneyPeriod period;

  /// Only for [MoneyPeriod.custom]: first and last day, both included.
  final DateTime? from;
  final DateTime? to;
  final String? category;
  final String? workerId;
  final String query;

  /// Cancelled entries stay visible (struck through) unless hidden here.
  final bool showCancelled;

  bool get isEmpty =>
      period == MoneyPeriod.all && category == null && workerId == null && query.trim().isEmpty;

  MoneyFilter copyWith({
    MoneyPeriod? period,
    DateTime? from,
    DateTime? to,
    Object? category = _keep,
    Object? workerId = _keep,
    String? query,
    bool? showCancelled,
  }) =>
      MoneyFilter(
        period: period ?? this.period,
        from: from ?? this.from,
        to: to ?? this.to,
        category: identical(category, _keep) ? this.category : category as String?,
        workerId: identical(workerId, _keep) ? this.workerId : workerId as String?,
        query: query ?? this.query,
        showCancelled: showCancelled ?? this.showCancelled,
      );

  /// The days this filter covers, as [start, end) in local time, or null
  /// for all time.
  (DateTime, DateTime)? range(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (period) {
      case MoneyPeriod.all:
        return null;
      case MoneyPeriod.thisWeek:
        final monday = today.subtract(Duration(days: today.weekday - 1));
        return (monday, monday.add(const Duration(days: 7)));
      case MoneyPeriod.thisMonth:
        return (DateTime(now.year, now.month), DateTime(now.year, now.month + 1));
      case MoneyPeriod.lastMonth:
        return (DateTime(now.year, now.month - 1), DateTime(now.year, now.month));
      case MoneyPeriod.custom:
        final f = from ?? DateTime(2000);
        final t = to ?? today;
        return (DateTime(f.year, f.month, f.day), DateTime(t.year, t.month, t.day + 1));
    }
  }

  bool _inRange(DateTime day, DateTime now) {
    final r = range(now);
    return r == null || (!day.isBefore(r.$1) && day.isBefore(r.$2));
  }

  /// The expenses that pass, newest first. [workerName] lets the search
  /// find an entry by the worker it was paid to.
  List<SiteExpense> expenses(List<SiteExpense> all, {Map<String, String> workerName = const {}, DateTime? now}) {
    final n = now ?? DateTime.now();
    final q = query.trim().toLowerCase();
    final out = all.where((e) {
      if (!showCancelled && e.voided) return false;
      if (category != null && e.category != category) return false;
      if (workerId != null && e.workerId != workerId) return false;
      if (!_inRange(expenseDay(e), n)) return false;
      if (q.isEmpty) return true;
      return [
        e.category,
        e.note,
        e.paidTo,
        voucherLabel(e.voucherNo),
        if (e.workerId != null) workerName[e.workerId],
        e.amount.toStringAsFixed(0),
      ].whereType<String>().any((s) => s.toLowerCase().contains(q));
    }).toList();
    out.sort((a, b) {
      final d = expenseDay(b).compareTo(expenseDay(a));
      return d != 0 ? d : b.createdAt.compareTo(a.createdAt);
    });
    return out;
  }

  List<PaymentsReceivedData> payments(List<PaymentsReceivedData> all, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final q = query.trim().toLowerCase();
    final out = all.where((p) {
      if (!showCancelled && p.voided) return false;
      if (!_inRange(DateTime(p.receivedOn.year, p.receivedOn.month, p.receivedOn.day), n)) return false;
      if (q.isEmpty) return true;
      return [p.fromParty, p.note, p.amount.toStringAsFixed(0)]
          .whereType<String>()
          .any((s) => s.toLowerCase().contains(q));
    }).toList()
      ..sort((a, b) => b.receivedOn.compareTo(a.receivedOn));
    return out;
  }
}

const _keep = Object();

/// The day an expense was spent on (stored as yyyy-mm-dd text).
DateTime expenseDay(SiteExpense e) {
  final d = DateTime.tryParse(e.incurredOn) ?? e.createdAt;
  return DateTime(d.year, d.month, d.day);
}

/// Total of what counts: cancelled entries never add up.
double totalOf(Iterable<SiteExpense> xs) => xs.where((e) => !e.voided).fold(0.0, (s, e) => s + e.amount);

double totalReceived(Iterable<PaymentsReceivedData> xs) =>
    xs.where((p) => !p.voided).fold(0.0, (s, p) => s + p.amount);

/// One bar of the breakdown.
class CategoryShare {
  const CategoryShare(this.category, this.amount, this.share, this.count);
  final String category;
  final double amount;

  /// 0..1 of the total.
  final double share;
  final int count;
}

/// Spending by category, biggest first, cancelled entries left out.
List<CategoryShare> categoryBreakdown(Iterable<SiteExpense> xs) {
  final sums = <String, double>{};
  final counts = <String, int>{};
  for (final e in xs.where((e) => !e.voided)) {
    sums[e.category] = (sums[e.category] ?? 0) + e.amount;
    counts[e.category] = (counts[e.category] ?? 0) + 1;
  }
  final total = sums.values.fold(0.0, (s, v) => s + v);
  final out = [
    for (final MapEntry(:key, :value) in sums.entries)
      CategoryShare(key, value, total == 0 ? 0 : value / total, counts[key] ?? 0),
  ]..sort((a, b) => b.amount.compareTo(a.amount));
  return out;
}

/// Settings key for a company's own categories.
String customCategoriesKey(String companyId) => 'expense_categories:$companyId';

/// The categories to offer: the defaults, the company's own, and any used
/// on the site already (a teammate's own category arrives with sync), with
/// "Other" kept last.
List<String> categoriesToOffer({List<String> custom = const [], Iterable<SiteExpense> used = const []}) {
  final seen = <String>{};
  final out = <String>[];
  void add(String c) {
    final v = c.trim();
    if (v.isEmpty || v == 'Other' || !seen.add(v.toLowerCase())) return;
    out.add(v);
  }

  defaultExpenseCategories.forEach(add);
  custom.forEach(add);
  for (final e in used) {
    add(e.category);
  }
  return [...out, 'Other'];
}

Future<List<String>> loadCustomCategories(AppDatabase db, String companyId) async {
  final raw = await db.settingsDao.get(customCategoriesKey(companyId));
  if (raw == null || raw.isEmpty) return const [];
  try {
    return (jsonDecode(raw) as List).whereType<String>().toList();
  } catch (_) {
    return const [];
  }
}

/// Adds a category (up to 50 characters, the column's limit). Returns the
/// name as saved, or null when it was empty or already there.
Future<String?> addCustomCategory(AppDatabase db, String companyId, String name) async {
  var v = name.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (v.isEmpty) return null;
  if (v.length > 50) v = v.substring(0, 50).trim();
  final list = [...await loadCustomCategories(db, companyId)];
  final all = categoriesToOffer(custom: list);
  if (all.any((c) => c.toLowerCase() == v.toLowerCase())) return null;
  list.add(v);
  await db.settingsDao.set(customCategoriesKey(companyId), jsonEncode(list));
  return v;
}

Future<void> removeCustomCategory(AppDatabase db, String companyId, String name) async {
  final list = [...await loadCustomCategories(db, companyId)]..removeWhere((c) => c == name);
  await db.settingsDao.set(customCategoriesKey(companyId), jsonEncode(list));
}
