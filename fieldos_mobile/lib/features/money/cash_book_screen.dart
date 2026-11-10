/// Cash book screens: everyone holding the site's cash, and one person's
/// book with give, take back and count.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/auth/site_roles.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/money/cash_book.dart';
import 'package:fieldos_mobile/features/money/money_view.dart' show isoDay;
import 'package:fieldos_mobile/features/tasks/team_roster.dart';
import 'package:fieldos_mobile/features/team/site_team_screen.dart' show mySiteAccessProvider;
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

final cashBooksProvider = FutureProvider.autoDispose.family<List<CashBook>, String>(
    (ref, projectId) => loadCashBooks(ref.watch(appDatabaseProvider), projectId));

/// Owners, project managers and the site's accounts person hand out and
/// count cash (the server's is_site_cash_keeper).
bool keepsSiteCash(SiteAccessFor a) => a.canWrite && (a.managesSite || a.siteRole == SiteRole.accounts);

/// Someone who can hold cash: their id as this phone stores it, and a name.
class CashPerson {
  const CashPerson(this.id, this.name);
  final String id;
  final String name;
}

/// The people cash can be given to: this phone's own account (by its local
/// id, which its expenses carry) and the company's team as last seen.
final cashPeopleProvider = FutureProvider.autoDispose<List<CashPerson>>((ref) async {
  final s = ref.watch(sessionProvider);
  final roster = await ref.watch(teamRosterProvider(s.activeCompany?.id ?? '').future);
  final me = s.user;
  return [
    if (me != null) CashPerson(me.id, tr('You')),
    for (final m in roster.members)
      if (m.userId != roster.myUserId) CashPerson(m.userId, memberLabel(m)),
  ];
});

String _nameOf(List<CashPerson> people, String id) {
  for (final p in people) {
    if (p.id == id) return p.name;
  }
  return tr('Someone on the team');
}

class CashBookScreen extends ConsumerWidget {
  const CashBookScreen({super.key, required this.project});
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(mySiteAccessProvider(project.id));
    final books = ref.watch(cashBooksProvider(project.id));
    final people = ref.watch(cashPeopleProvider).value ?? const <CashPerson>[];
    final myId = ref.watch(sessionProvider).user?.id ?? '';
    final keeper = access.value != null && keepsSiteCash(access.value!);

    return Scaffold(
      appBar: AppBar(title: Text(tr('Cash book'))),
      floatingActionButton: keeper
          ? FloatingActionButton.extended(
              onPressed: () => _giveToSomeone(context, ref, people),
              icon: const Icon(Icons.payments_outlined),
              label: Text(tr('Give cash')),
            )
          : null,
      body: books.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st, onRetry: () => ref.invalidate(cashBooksProvider(project.id))),
        data: (all) {
          final shown = keeper ? all : all.where((b) => b.holderId == myId).toList();
          if (shown.isEmpty) {
            return EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: keeper ? tr('No cash handed out on this site yet') : tr('No cash given to you on this site yet'),
              message: tr(
                  'Give cash to a supervisor here. What they spend in cash comes from their own entries in the money book, and a count shows any cash that is missing.'),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              for (final b in shown)
                _HolderCard(
                  book: b,
                  name: _nameOf(people, b.holderId),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => CashHolderScreen(project: project, holderId: b.holderId),
                  )),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _giveToSomeone(BuildContext context, WidgetRef ref, List<CashPerson> people) async {
    final who = await showModalBottomSheet<CashPerson>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(tr('Give cash to'), style: Theme.of(ctx).textTheme.titleMedium)),
            for (final p in people)
              ListTile(leading: const Icon(Icons.person_outline), title: Text(p.name), onTap: () => Navigator.pop(ctx, p)),
            if (people.length <= 1)
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(tr('Add your team in Team & sync to give cash to them.')),
              ),
          ],
        ),
      ),
    );
    if (who == null || !context.mounted) return;
    final done = await recordCashMove(context, ref, project: project, holderId: who.id, kind: 'given');
    if (done && context.mounted) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => CashHolderScreen(project: project, holderId: who.id)));
    }
  }
}

class _HolderCard extends StatelessWidget {
  const _HolderCard({required this.book, required this.name, required this.onTap});
  final CashBook book;
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final short = book.unexplained();
    final noBill = book.spentWithoutBill();
    final last = book.lastCount;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(name, style: theme.textTheme.titleMedium)),
                Text(rupees(book.inHand), style: theme.textTheme.titleLarge),
              ]),
              Text(tr('In hand, by the book'), style: theme.textTheme.bodySmall),
              const SizedBox(height: 6),
              Text(trf('Given {given} · spent {spent} · returned {returned}', {
                'given': rupees(book.given),
                'spent': rupees(book.spent),
                'returned': rupees(book.returned),
              })),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 4, children: [
                if (short > 0.005) StatusPill(trf('Short {amount} at counts', {'amount': rupees(short)}), tone: PillTone.danger),
                if (noBill > 0.005) StatusPill(trf('{amount} spent with no bill', {'amount': rupees(noBill)}), tone: PillTone.warn),
                StatusPill(
                  last == null ? tr('Never counted') : trf('Counted {date}', {'date': fmtDate(DateTime.parse(last.day))}),
                  tone: last == null ? PillTone.warn : PillTone.neutral,
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class CashHolderScreen extends ConsumerWidget {
  const CashHolderScreen({super.key, required this.project, required this.holderId});
  final Project project;
  final String holderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(mySiteAccessProvider(project.id));
    final keeper = access.value != null && keepsSiteCash(access.value!);
    final people = ref.watch(cashPeopleProvider).value ?? const <CashPerson>[];
    final books = ref.watch(cashBooksProvider(project.id));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(_nameOf(people, holderId))),
      bottomNavigationBar: keeper
          ? SystemNavBarSafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () => recordCashMove(context, ref, project: project, holderId: holderId, kind: 'given'),
                      child: Text(tr('Give')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => recordCashMove(context, ref, project: project, holderId: holderId, kind: 'returned'),
                      child: Text(tr('Take back')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => recordCashMove(context, ref, project: project, holderId: holderId, kind: 'counted'),
                      child: Text(tr('Count')),
                    ),
                  ),
                ]),
              ),
            )
          : null,
      body: books.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
        data: (all) {
          final book = all.firstWhere((b) => b.holderId == holderId,
              orElse: () => CashBook(holderId: holderId, lines: const []));
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('In hand, by the book'), style: theme.textTheme.bodySmall),
                    Text(rupees(book.inHand), style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text(trf('Given {given} · spent {spent} · returned {returned}', {
                      'given': rupees(book.given),
                      'spent': rupees(book.spent),
                      'returned': rupees(book.returned),
                    })),
                    if (book.unexplained() > 0.005)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: StatusPill(trf('Short {amount} at counts', {'amount': rupees(book.unexplained())}),
                            tone: PillTone.danger),
                      ),
                  ]),
                ),
              ),
              if (book.lines.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tr('Nothing in this book yet.'), textAlign: TextAlign.center),
                ),
              for (final l in book.lines.reversed)
                _LineTile(
                  line: l,
                  onLongPress: keeper && l.move != null ? () => _cancel(context, ref, l.move!) : null,
                ),
              if (keeper && book.lines.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(tr('Press and hold an entry you made by mistake to cancel it.'),
                      style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, CashMove move) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Cancel this entry?')),
        content: TextField(
          controller: reason,
          autofocus: true,
          maxLength: 200,
          decoration: InputDecoration(labelText: tr('Why')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Keep'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Cancel entry'))),
        ],
      ),
    );
    final why = reason.text.trim();
    reason.dispose();
    if (ok != true || !context.mounted) return;
    if (why.isEmpty) {
      showSnack(context, tr('Say why it is cancelled.'), error: true);
      return;
    }
    try {
      await ref.read(appDatabaseProvider).cashBookDao.cancel(move.id, reason: why);
      ref.invalidate(cashBooksProvider(move.projectId));
    } catch (e, st) {
      if (context.mounted) showSnack(context, friendlyError(e, st), error: true);
    }
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line, this.onLongPress});
  final CashLine line;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (IconData icon, String title, String amount) = switch (line.kind) {
      'given' => (Icons.south_west, tr('Cash given'), '+${rupees(line.amount)}'),
      'returned' => (Icons.north_east, tr('Handed back'), '-${rupees(line.amount)}'),
      'counted' => (Icons.fact_check_outlined, trf('Counted: {amount} in hand', {'amount': rupees(line.amount)}), ''),
      _ => (
          Icons.receipt_long_outlined,
          line.expense?.paidTo ?? line.expense?.category ?? tr('Spent'),
          '-${rupees(line.amount)}'
        ),
    };
    final gap = line.countGap;
    final note = line.move?.note ?? line.expense?.note;
    return ListTile(
      onLongPress: onLongPress,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text([
          fmtDate(DateTime.parse(line.day)),
          if (line.kind == 'counted') trf('book said {amount}', {'amount': rupees(line.bookBefore ?? 0)}),
          if (note != null && note.isNotEmpty) note,
        ].join(' · ')),
        if (line.kind == 'counted' && gap.abs() > 0.005)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: StatusPill(
              gap < 0 ? trf('Short {amount}', {'amount': rupees(-gap)}) : trf('Extra {amount}', {'amount': rupees(gap)}),
              tone: gap < 0 ? PillTone.danger : PillTone.warn,
            ),
          ),
        if (line.noBill)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: StatusPill(tr('No bill attached'), tone: PillTone.warn),
          ),
      ]),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (amount.isNotEmpty) Text(amount, style: theme.textTheme.titleSmall),
          Text(rupees(line.balanceAfter), style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Asks for the amount (or, for a count, the cash found) and records it.
/// Returns whether something was written.
Future<bool> recordCashMove(BuildContext context, WidgetRef ref,
    {required Project project, required String holderId, required String kind}) async {
  final db = ref.read(appDatabaseProvider);
  final books = await loadCashBooks(db, project.id);
  final book = books.where((b) => b.holderId == holderId).firstOrNull;
  if (!context.mounted) return false;
  final inHand = book?.inHand ?? 0;
  final amount = TextEditingController();
  final note = TextEditingController();
  var day = DateTime.now();
  final title = switch (kind) {
    'given' => tr('Give cash'),
    'returned' => tr('Take cash back'),
    _ => tr('Count the cash in hand'),
  };
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final typed = double.tryParse(amount.text.trim());
        final gap = kind == 'counted' && typed != null ? typed - inHand : null;
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(trf('The book says {amount} in hand.', {'amount': rupees(inHand)})),
              const SizedBox(height: 8),
              TextField(
                controller: amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: InputDecoration(
                  labelText: kind == 'counted' ? tr('Cash found in hand (₹)') : tr('Amount (₹)'),
                ),
                onChanged: (_) => set(() {}),
              ),
              if (gap != null && gap.abs() > 0.005)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: StatusPill(
                    gap < 0 ? trf('Short {amount}', {'amount': rupees(-gap)}) : trf('Extra {amount}', {'amount': rupees(gap)}),
                    tone: gap < 0 ? PillTone.danger : PillTone.warn,
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_outlined),
                label: Text(fmtDate(day)),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: day,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (d != null) set(() => day = d);
                },
              ),
              TextField(
                controller: note,
                maxLength: 300,
                decoration: InputDecoration(labelText: tr('Note (optional)')),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
          ],
        );
      },
    ),
  );
  final value = double.tryParse(amount.text.trim());
  final noteText = note.text;
  amount.dispose();
  note.dispose();
  if (ok != true || !context.mounted) return false;
  if (value == null || value < 0 || (kind != 'counted' && value <= 0)) {
    showSnack(context, tr('Enter an amount above zero'), error: true);
    return false;
  }
  try {
    await db.cashBookDao.record(
      projectId: project.id,
      holderId: holderId,
      kind: kind,
      amount: value,
      movedOn: isoDay(day),
      by: ref.read(sessionProvider).user?.id ?? '',
      note: noteText,
    );
    ref.invalidate(cashBooksProvider(project.id));
    return true;
  } catch (e, st) {
    if (context.mounted) showSnack(context, friendlyError(e, st), error: true);
    return false;
  }
}
