import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet.dart';
import 'package:fieldos_mobile/features/money/money_view.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/features/mascot/mitra.dart';

/// Weekly wage sheet (Monday to Sunday) from GPS punches, with a Pay button
/// per worker and a WhatsApp-ready summary to share with the contractor or
/// the office.
class WageSheetScreen extends ConsumerStatefulWidget {
  const WageSheetScreen({super.key, required this.projectId, required this.projectName, required this.userId});
  final String projectId;
  final String projectName;
  final String userId;

  @override
  ConsumerState<WageSheetScreen> createState() => _WageSheetScreenState();
}

class _WageSheetScreenState extends ConsumerState<WageSheetScreen> {
  late DateTime _from = weekStart(DateTime.now());
  DateTime get _to => _from.add(const Duration(days: 7));

  Future<WageSheet> _load() async {
    final db = ref.read(appDatabaseProvider);
    return buildWageSheet(
      workers: await db.workerDao.forProject(widget.projectId),
      punches: await db.attendanceDao.forProject(widget.projectId),
      expenses: await db.expenseDao.forProject(widget.projectId),
      from: _from,
      to: _to,
    );
  }

  String _days(double d) => d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(1);

  String _range() => '${shortDay(_from)} to ${shortDay(_to.subtract(const Duration(days: 1)))}';

  String _shareText(WageSheet s) {
    final b = StringBuffer('Wage sheet · ${widget.projectName}\n${_range()}\n\n');
    for (final l in s.lines.where((l) => l.days > 0 || l.paidInPeriod > 0 || l.balanceDue != 0)) {
      b.write('${l.name}: ${_days(l.days)} days');
      if (l.dailyWage != null) b.write(' × ${rupees(l.dailyWage!)} = ${rupees(l.earned)}');
      if (l.paidInPeriod > 0) b.write(', paid ${rupees(l.paidInPeriod)}');
      b.write(', due ${rupees(l.balanceDue)}\n');
    }
    b.write('\nTotal earned ${rupees(s.totalEarned)} · paid ${rupees(s.totalPaid)} · due ${rupees(s.totalDue)}');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WageSheet>(
      future: _load(),
      builder: (context, snap) {
        final sheet = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(tr('Wage sheet')),
            actions: [
              if (sheet != null)
                IconButton(
                  tooltip: tr('Share on WhatsApp'),
                  icon: const Icon(Icons.share),
                  onPressed: () => SharePlus.instance.share(ShareParams(text: _shareText(sheet))),
                ),
            ],
          ),
          body: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: tr('Previous week'),
                  onPressed: () => setState(() => _from = _from.subtract(const Duration(days: 7)))),
              Text(_range(), style: const TextStyle(fontWeight: FontWeight.w600)),
              IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: tr('Next week'),
                  onPressed: _to.isAfter(DateTime.now())
                      ? null
                      : () => setState(() => _from = _from.add(const Duration(days: 7)))),
            ]),
            if (sheet != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  'Earned ${rupees(sheet.totalEarned)} · Paid ${rupees(sheet.totalPaid)} · Still due ${rupees(sheet.totalDue)}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            const Divider(),
            Expanded(
              child: sheet == null
                  ? const Center(child: CircularProgressIndicator())
                  : sheet.lines.isEmpty
                      ? MitraEmpty(tr('No workers or punches yet.'))
                      : ListView(children: [
                          for (final l in sheet.lines)
                            ListTile(
                              title: Text(l.name),
                              subtitle: Text([
                                '${_days(l.days)} days (${l.hours.toStringAsFixed(1)} h)',
                                if (l.overtimeHours > 0) 'OT ${l.overtimeHours.toStringAsFixed(1)} h',
                                if (l.dailyWage == null) 'no daily wage set' else '${rupees(l.dailyWage!)}/day',
                                if (l.missingPunchOuts > 0) '${l.missingPunchOuts} missing punch-out (half day)',
                                if (l.paidInPeriod > 0) 'paid ${rupees(l.paidInPeriod)}',
                              ].join(' · ')),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(rupees(l.balanceDue),
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: l.balanceDue < 0 ? toneColor(context, PillTone.warn) : null)),
                                  Text(l.balanceDue < 0 ? 'advance' : 'due', style: const TextStyle(fontSize: 11)),
                                ],
                              ),
                              onTap: l.workerId == null
                                  ? null
                                  : () async {
                                      final saved = await addExpense(context, ref,
                                          projectId: widget.projectId,
                                          userId: widget.userId,
                                          category: 'Labour',
                                          workerId: l.workerId,
                                          suggestedAmount: l.balanceDue > 0 ? l.balanceDue : null,
                                          note: 'Wages ${_range()}');
                                      if (saved && mounted) setState(() {});
                                    },
                            ),
                        ]),
            ),
            Padding(
              padding: EdgeInsets.all(12),
              child: Text(tr('A day counts as full at 7 hours on site and half at 3.5 hours. Tap a worker to pay wages or an advance.'),
                style: TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ]),
        );
      },
    );
  }
}
