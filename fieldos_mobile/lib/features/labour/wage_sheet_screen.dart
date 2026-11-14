import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/features/labour/overtime_settings_screen.dart';
import 'package:fieldos_mobile/features/labour/pay_calendar_screen.dart';
import 'package:fieldos_mobile/features/labour/wage_contributions.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet.dart';
import 'package:fieldos_mobile/features/money/money_view.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/features/mascot/mitra.dart';

String _days(double d) => d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(1);

/// " + 2 h overtime ₹400" after the days × wage, where overtime is paid on
/// day wages; empty when there is none.
String overtimeShareText(WageLine l) =>
    l.overtimePay > 0 ? ' + ${fmtQty(l.overtimeHours)} h overtime ${rupees(l.overtimePay, paise: true)}' : '';

/// "5 h overtime", with California's double-time hours in it.
String _hourlyOvertimeShareText(WageLine l) => l.doubleTimeHours > 0
    ? '${fmtQty(l.overtimeHours)} h overtime, ${fmtQty(l.doubleTimeHours)} h of it double time'
    : '${fmtQty(l.overtimeHours)} h overtime';

/// The sheet as a WhatsApp message. Where crews are paid by the hour (US,
/// UK) a line is the hours at the hourly rate: "45 h (5 h overtime) ×
/// $30/hr", not "5 days × $30", which did not add up.
String wageSheetShareText(WageSheet s, {required String projectName, required String range}) {
  final b = StringBuffer('Wage sheet · $projectName\n$range\n\n');
  for (final l in s.lines.where((l) => l.days > 0 || l.paidInPeriod > 0 || l.balanceDue != 0)) {
    if (market.payHourly) {
      b.write('${l.name}: ${fmtQty(l.hours)} h');
      if (l.overtimeHours > 0) b.write(' (${_hourlyOvertimeShareText(l)})');
      if (l.dailyWage != null) b.write(' × ${rupees(l.dailyWage!, paise: true)}/hr = ${rupees(l.earned, paise: true)}');
    } else {
      b.write('${l.name}: ${_days(l.days)} days');
      if (l.dailyWage != null) {
        b.write(' × ${rupees(l.dailyWage!, paise: true)}${overtimeShareText(l)} = ${rupees(l.earned, paise: true)}');
      }
    }
    if (l.paidInPeriod > 0) b.write(', paid ${rupees(l.paidInPeriod, paise: true)}');
    b.write(', due ${rupees(l.balanceDue, paise: true)}\n');
  }
  b.write('\nTotal earned ${rupees(s.totalEarned, paise: true)} · paid ${rupees(s.totalPaid, paise: true)} · due ${rupees(s.totalDue, paise: true)}');
  return b.toString();
}

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
  PayCalendar _cal = const PayCalendar();
  Map<String, WageContribution> _contrib = const {};
  OvertimePolicy _ot = OvertimePolicy.marketDefault;
  DateTime get _to => addDays(_from, 7);

  Future<WageSheet> _load() async {
    final db = ref.read(appDatabaseProvider);
    final sheet = await _build(db);
    _contrib = wageSheetContributionsShown
        ? wageContributions(sheet,
            foreign: foreignWorkerIds(await db.siteExecutionDao.permitsFor(widget.projectId)))
        : const {};
    return sheet;
  }

  Future<WageSheet> _build(AppDatabase db) async {
    return buildWageSheet(
      workers: await db.workerDao.forProject(widget.projectId),
      punches: await db.attendanceDao.forProject(widget.projectId),
      expenses: await db.expenseDao.forProject(widget.projectId),
      from: _from,
      to: _to,
      marks: await db.attendanceDao.marksForProject(widget.projectId),
      calendar: _cal = await _calendar(db),
      overtime: _ot = await _overtime(db),
    );
  }

  Future<OvertimePolicy> _overtime(AppDatabase db) async {
    final p = await db.projectDao.byId(widget.projectId);
    return p == null ? OvertimePolicy.marketDefault : loadOvertimePolicy(db, p.companyId);
  }

  Future<PayCalendar> _calendar(AppDatabase db) async {
    final p = await db.projectDao.byId(widget.projectId);
    return p == null ? const PayCalendar() : loadPayCalendar(db, p.companyId);
  }


  String _range() => trf('{from} to {to}',
      {'from': shortDay(_from), 'to': shortDay(addDays(_to, -1))});

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
              if (market.premiumRestAndHolidayPay)
                IconButton(
                  key: const Key('pay-calendar'),
                  tooltip: tr('Rest day and public holidays'),
                  icon: const Icon(Icons.event_available_outlined),
                  onPressed: () async {
                    final p = await ref.read(appDatabaseProvider).projectDao.byId(widget.projectId);
                    if (p == null || !context.mounted) return;
                    await Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => PayCalendarScreen(companyId: p.companyId)));
                    if (mounted) setState(() {});
                  },
                ),
              IconButton(
                key: const Key('overtime-pay'),
                tooltip: tr('Overtime pay'),
                icon: const Icon(Icons.more_time),
                onPressed: () async {
                  final p = await ref.read(appDatabaseProvider).projectDao.byId(widget.projectId);
                  if (p == null || !context.mounted) return;
                  await Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => OvertimeSettingsScreen(companyId: p.companyId)));
                  if (mounted) setState(() {});
                },
              ),
              if (sheet != null)
                IconButton(
                  tooltip: tr('Share on WhatsApp'),
                  icon: const Icon(Icons.share),
                  onPressed: () => SharePlus.instance.share(
                      ShareParams(text: wageSheetShareText(sheet, projectName: widget.projectName, range: _range()))),
                ),
            ],
          ),
          body: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: tr('Previous week'),
                  onPressed: () => setState(() => _from = addDays(_from, -7))),
              // The week can be long in Tamil or with large text: it wraps
              // between the arrows instead of pushing "next week" off screen.
              Expanded(
                child: Text(_range(), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: tr('Next week'),
                  onPressed: _to.isAfter(DateTime.now())
                      ? null
                      : () => setState(() => _from = addDays(_from, 7))),
            ]),
            if (sheet != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  trf('Earned {earned} · Paid {paid} · Still due {due}', {
                    'earned': rupees(sheet.totalEarned, paise: true),
                    'paid': rupees(sheet.totalPaid, paise: true),
                    'due': rupees(sheet.totalDue, paise: true),
                  }),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            if (sheet != null && _contrib.isNotEmpty)
              if (contributionTotals(_contrib) case final t)
                Padding(
                  key: const Key('contribution-totals'),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    trf('EPF, SOCSO and EIS: workers {ee} · employer {er}', {
                      'ee': rupees(t.employee, paise: true),
                      'er': rupees(t.employer, paise: true),
                    }),
                    style: Theme.of(context).textTheme.bodySmall,
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
                              subtitle: _withContributions(_contrib[l.key], Text([
                                trf(l.days == 1 ? '{n} day ({h} h)' : '{n} days ({h} h)',
                                    {'n': _days(l.days), 'h': l.hours.toStringAsFixed(1)}),
                                if (l.overtimeHours > 0) trf('OT {h} h', {'h': l.overtimeHours.toStringAsFixed(1)}),
                                if (l.doubleTimeHours > 0)
                                  trf('{h} h double time', {'h': l.doubleTimeHours.toStringAsFixed(1)}),
                                if (l.overtimePay > 0) trf('OT pay {amount}', {'amount': rupees(l.overtimePay, paise: true)}),
                                if (l.dailyWage == null)
                                  tr('no daily wage set')
                                else
                                  trf(market.payHourly ? '{amount}/hr' : '{amount}/day',
                                      {'amount': rupees(l.dailyWage!, paise: true)}),
                                if (belowMinimumWage(l.dailyWage, _cal) case final min?)
                                  trf(market.payHourly ? 'below the minimum wage of {amount}/hr' : 'below the minimum wage of {amount}/day',
                                      {'amount': rupees(min, paise: true)}),
                                if (l.missingPunchOuts > 0)
                                  trf(l.missingPunchOuts == 1 ? '1 missing punch-out (half day)' : '{n} missing punch-outs (half days)',
                                      {'n': l.missingPunchOuts}),
                                if (l.markedDays > 0) trf('{n} marked by hand', {'n': l.markedDays}),
                                if (l.paidInPeriod > 0) trf('paid {amount}', {'amount': rupees(l.paidInPeriod, paise: true)}),
                              ].join(' · '))),
                              // ListTile caps the trailing height; with very
                              // large text the two lines scale down to fit.
                              trailing: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(rupees(l.balanceDue, paise: true),
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: l.balanceDue < 0 ? toneColor(context, PillTone.warn) : null)),
                                    Text(l.balanceDue < 0 ? tr('advance') : tr('due'), style: const TextStyle(fontSize: 11)),
                                  ],
                                ),
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
                          // The note scrolls with the list: fixed under it, on a
                          // small phone with large text it left no room for
                          // the workers themselves.
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              tr('A day counts as full at 7 hours on site and half at 3.5 hours, unless it was marked by hand on the day register. Tap a worker to pay wages or an advance.'),
                              style: const TextStyle(fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          if (!market.payHourly)
                            Padding(
                              key: const Key('overtime-note'),
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: Text(
                                [
                                  trf('Hours past {h} in a day are overtime. The hourly rate is the day wage divided by {h}.',
                                      {'h': fmtQty(normalDayHours)}),
                                  trf('Overtime hours are paid at the hourly rate times {rate}.', {'rate': fmtQty(_ot.multiplier)}),
                                ].join(' '),
                                style: const TextStyle(fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          if (_contrib.isNotEmpty)
                            Padding(
                              key: const Key('contribution-note'),
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                              child: Text(
                                tr('EPF, SOCSO and EIS are worked out on the wages in this sheet. They are due on a month\'s wages, so check them against the month\'s total before paying them over. A worker with a PLKS permit on file is counted as foreign: EPF 2% each, SOCSO as for a local worker, no EIS.'),
                                style: const TextStyle(fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          if (market.minimumWage != null)
                            Padding(
                              key: const Key('minimum-wage-note'),
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                              child: Text(
                                tr(market.minimumWage!.note),
                                style: const TextStyle(fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                            ),
                        ]),
            ),
          ]),
        );
      },
    );
  }
}

/// A wage line's subtitle, with the worker's EPF, SOCSO and EIS, the
/// employer's, and the net pay on lines of their own (Malaysia).
Widget _withContributions(WageContribution? c, Text summary) {
  if (c == null) return summary;
  final k = c.contributions;
  String items(List<(String, double)> xs) => [
        for (final (label, v) in xs)
          if (v > 0) '${tr(label)} ${rupees(v, paise: true)}',
      ].join(' · ');
  final worker = items([('EPF', k.epfEmployee), ('SOCSO', k.socsoEmployee), ('EIS', k.eisEmployee)]);
  final employer = items([('EPF', k.epfEmployer), ('SOCSO', k.socsoEmployer), ('EIS', k.eisEmployer)]);
  return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
    summary,
    if (worker.isNotEmpty) Text(trf('Cut from pay: {items}', {'items': worker})),
    if (employer.isNotEmpty) Text(trf('Employer pays: {items}', {'items': employer})),
    Text(trf('Net pay {amount}', {'amount': rupees(c.netPay, paise: true)}),
        style: const TextStyle(fontWeight: FontWeight.w600)),
  ]);
}
