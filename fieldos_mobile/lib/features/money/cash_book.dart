/// The site cash book (imprest): how much cash each person on site holds.
///
/// Cash handed over and handed back are cash moves; what the person spent
/// is their own cash expenses on the site, read from the money book, so the
/// two can never disagree. A count is the cash actually found in their
/// hand: below the book is "unexplained", above it is "extra". After a
/// count the book carries on from what was found, so one shortfall is not
/// counted again at the next count.
library;

import 'package:fieldos_mobile/data/app_database.dart';

/// One line of a person's cash book, in date order.
class CashLine {
  const CashLine({
    required this.day,
    required this.kind,
    required this.amount,
    required this.balanceAfter,
    this.move,
    this.expense,
    this.bookBefore,
    this.noBill = false,
  });

  /// yyyy-mm-dd
  final String day;

  /// given | returned | spent | counted
  final String kind;

  /// Cash given, returned or spent; for a count, the cash found.
  final double amount;

  /// What the book says the person holds after this line.
  final double balanceAfter;

  /// For a count: what the book said just before it.
  final double? bookBefore;
  final CashMove? move;
  final SiteExpense? expense;

  /// A cash expense with no bill photo or file on it.
  final bool noBill;

  /// For a count: found minus book. Negative means cash is missing.
  double get countGap => kind == 'counted' ? amount - (bookBefore ?? 0) : 0;
}

class CashBook {
  const CashBook({required this.holderId, required this.lines});

  final String holderId;
  final List<CashLine> lines;

  double get inHand => lines.isEmpty ? 0 : lines.last.balanceAfter;
  double get given => _sum('given');
  double get returned => _sum('returned');
  double get spent => _sum('spent');

  double _sum(String kind) => lines.where((l) => l.kind == kind).fold(0.0, (s, l) => s + l.amount);

  /// Cash missing at counts between [from] and [to] (yyyy-mm-dd, both
  /// inclusive; null means open), as a positive number.
  double unexplained({String? from, String? to}) => lines
      .where((l) => l.kind == 'counted' && l.countGap < -0.005 && _within(l.day, from, to))
      .fold(0.0, (s, l) => s - l.countGap);

  /// Cash spent with no bill attached, between [from] and [to].
  double spentWithoutBill({String? from, String? to}) =>
      lines.where((l) => l.noBill && _within(l.day, from, to)).fold(0.0, (s, l) => s + l.amount);

  CashLine? get lastCount {
    for (final l in lines.reversed) {
      if (l.kind == 'counted') return l;
    }
    return null;
  }
}

bool _within(String day, String? from, String? to) =>
    (from == null || day.compareTo(from) >= 0) && (to == null || day.compareTo(to) <= 0);

/// Paid in cash: the money book's default, and older entries had no mode.
bool isCashExpense(SiteExpense e) => e.mode == null || e.mode == 'cash';

/// The people on a site who have a cash book: anyone cash was given to.
List<String> cashHolders(List<CashMove> moves) {
  final seen = <String>[];
  for (final m in moves) {
    if (!m.voided && !seen.contains(m.holderId)) seen.add(m.holderId);
  }
  return seen;
}

/// [holderId]'s book from [moves] and [expenses] of one site.
/// [billedExpenseIds] are the expenses that have a bill attached. Spending
/// dated before the first cash given is left out: the book starts there.
CashBook buildCashBook({
  required String holderId,
  required List<CashMove> moves,
  required List<SiteExpense> expenses,
  Set<String> billedExpenseIds = const {},
}) {
  final mine = moves.where((m) => !m.voided && m.holderId == holderId).toList();
  if (mine.isEmpty) return CashBook(holderId: holderId, lines: const []);
  final start = mine.map((m) => m.movedOn).reduce((a, b) => a.compareTo(b) <= 0 ? a : b);

  final events = <({String day, DateTime at, CashMove? move, SiteExpense? expense})>[
    for (final m in mine) (day: m.movedOn, at: m.createdAt, move: m, expense: null),
    for (final e in expenses)
      if (!e.voided && e.recordedBy == holderId && isCashExpense(e) && _day(e.incurredOn).compareTo(start) >= 0)
        (day: _day(e.incurredOn), at: e.createdAt, move: null, expense: e),
  ]..sort((a, b) {
      final d = a.day.compareTo(b.day);
      return d != 0 ? d : a.at.compareTo(b.at);
    });

  var balance = 0.0;
  final lines = <CashLine>[];
  for (final ev in events) {
    final m = ev.move;
    if (m != null) {
      final before = balance;
      balance = switch (m.kind) {
        'given' => balance + m.amount,
        'returned' => balance - m.amount,
        _ => m.amount,
      };
      lines.add(CashLine(
        day: ev.day,
        kind: m.kind,
        amount: m.amount,
        balanceAfter: _round(balance),
        move: m,
        bookBefore: m.kind == 'counted' ? _round(before) : null,
      ));
    } else {
      final e = ev.expense!;
      balance -= e.amount;
      lines.add(CashLine(
        day: ev.day,
        kind: 'spent',
        amount: e.amount,
        balanceAfter: _round(balance),
        expense: e,
        noBill: !billedExpenseIds.contains(e.id),
      ));
    }
  }
  return CashBook(holderId: holderId, lines: lines);
}

double _round(double v) => (v * 100).roundToDouble() / 100;

/// incurredOn is yyyy-mm-dd, sometimes with a time after it.
String _day(String s) => s.length >= 10 ? s.substring(0, 10) : s;

/// Every holder's book on a site, read from the phone's database.
Future<List<CashBook>> loadCashBooks(AppDatabase db, String projectId) async {
  final moves = await db.cashBookDao.forProject(projectId);
  if (moves.isEmpty) return const [];
  final expenses = await db.expenseDao.forProject(projectId);
  final counts = await db.expenseDao.attachmentCounts(projectId);
  final billed = {for (final e in counts.entries) if (e.value > 0) e.key};
  return [
    for (final h in cashHolders(moves))
      buildCashBook(holderId: h, moves: moves, expenses: expenses, billedExpenseIds: billed),
  ];
}
