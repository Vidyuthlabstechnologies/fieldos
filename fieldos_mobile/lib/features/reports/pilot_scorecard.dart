/// The pilot scorecard: what changed on one site over a 60-day pilot, in
/// numbers from the site's own records. Week 1 is the baseline; days 8 to
/// 30 and 31 to 60 show the change. It is what the owner looks at before
/// deciding on the annual plan, so every figure is something the site
/// recorded, never an estimate, except office time (fixed minutes per
/// record, labelled as an estimate).
library;

import 'dart:typed_data';

import 'package:drift/drift.dart' show BooleanExpressionOperators;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/company/branding.dart';
import 'package:fieldos_mobile/features/dashboard/value_summary.dart'
    show minutesPerAttendance, minutesPerBill, minutesPerDelivery, minutesPerReport, minutesPerVoucher;
import 'package:fieldos_mobile/features/money/bill_pdf.dart' show pdfSafe;
import 'package:fieldos_mobile/features/money/cash_book.dart';
import 'package:fieldos_mobile/features/money/money_view.dart' show isoDay;

String pilotStartKey(String projectId) => 'pilot_start:$projectId';

Future<DateTime?> loadPilotStart(AppDatabase db, String projectId) async {
  final v = await db.settingsDao.get(pilotStartKey(projectId));
  return v == null ? null : DateTime.tryParse(v);
}

Future<void> savePilotStart(AppDatabase db, String projectId, DateTime day) =>
    db.settingsDao.set(pilotStartKey(projectId), isoDay(day));

/// One stretch of the pilot: [from] to [to], both inclusive.
class PilotPeriod {
  const PilotPeriod(this.label, this.from, this.to, {this.started = true});
  final String label;
  final DateTime from;
  final DateTime to;

  /// False while the period lies wholly in the future.
  final bool started;
  String get fromDay => isoDay(from);
  String get toDay => isoDay(to);
  bool contains(DateTime t) {
    final d = DateTime(t.year, t.month, t.day);
    return !d.isBefore(from) && !d.isAfter(to);
  }

  bool containsDay(String day) => day.compareTo(fromDay) >= 0 && day.compareTo(toDay) <= 0;
}

/// Week 1, days 8 to 30 and days 31 to 60 from [start], each cut off at
/// [today].
List<PilotPeriod> pilotPeriods(DateTime start, DateTime today) {
  final s = DateTime(start.year, start.month, start.day);
  final t = DateTime(today.year, today.month, today.day);
  PilotPeriod p(String label, int a, int b) {
    final from = s.add(Duration(days: a));
    var to = s.add(Duration(days: b));
    if (to.isAfter(t)) to = t;
    return PilotPeriod(label, from, to, started: !from.isAfter(t));
  }

  return [p('Week 1 (baseline)', 0, 6), p('Days 8 to 30', 7, 29), p('Days 31 to 60', 30, 59)];
}

/// Which way is better for a measure.
enum Better { up, down, neither }

class ScoreRow {
  const ScoreRow(this.measure, this.values, {required this.better, required this.format, this.note});
  final String measure;

  /// One per period; null when the period has not started or nothing was
  /// there to measure.
  final List<double?> values;
  final Better better;
  final String Function(double) format;
  final String? note;

  String cell(int i) => values[i] == null ? '-' : format(values[i]!);

  /// The latest period with a value against week 1, e.g. "better".
  String get change {
    final first = values.first;
    final last = values.skip(1).lastWhere((v) => v != null, orElse: () => null);
    if (first == null || last == null || better == Better.neither) return '';
    if ((last - first).abs() < 0.005) return 'same';
    final up = last > first;
    return (up == (better == Better.up)) ? 'better' : 'worse';
  }
}

class PilotScorecard {
  const PilotScorecard({required this.site, required this.start, required this.periods, required this.rows});
  final Project site;
  final DateTime start;
  final List<PilotPeriod> periods;
  final List<ScoreRow> rows;
}

String _pct(double v) => '${v.round()}%';
String _count(double v) => fmtQty(v);
String _days(double v) => '${v.toStringAsFixed(1)} days';
String _hours(double v) => '${v.toStringAsFixed(1)} h';

double? _share(int part, int whole) => whole == 0 ? null : part * 100 / whole;

bool _sameDay(DateTime a, DateTime b) {
  final x = a.toLocal(), y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

String _dayOf(String s) => s.length >= 10 ? s.substring(0, 10) : s;

/// Everything on the scorecard, from the phone's database.
Future<PilotScorecard> buildPilotScorecard(AppDatabase db, Project site, DateTime start, {DateTime? now}) async {
  final today = now ?? DateTime.now();
  final periods = pilotPeriods(start, today);
  final pid = site.id;

  final dprs = await db.dprDao.forProject(pid);
  final dayEvents = await db.dayCloseDao.eventsFor(pid);
  final expenses = await db.expenseDao.forProject(pid);
  final billCounts = await db.expenseDao.attachmentCounts(pid);
  final receipts = (await db.materialDao.forProject(pid)).where((r) => r.notes?.trim() != 'Opening stock').toList();
  final slips = await db.materialDao.slipsForProject(pid);
  final punches = await db.attendanceDao.forProject(pid);
  final books = await loadCashBooks(db, pid);
  final overruns = await (db.select(db.approvals)
        ..where((a) => a.projectId.equals(pid) & a.entityType.equals('budget_overrun')))
      .get();
  final bills = {for (final b in await db.billDao.forProject(pid)) b.id: b};
  final payments = {for (final p in await db.paymentDao.forProject(pid)) p.id: p};
  final allocations = (await db.billingRecordsDao.allocationsFor(pid)).where((a) => a.kind == 'bill').toList();

  List<double?> per(double? Function(PilotPeriod p) f) => [for (final p in periods) p.started ? f(p) : null];

  // Days a report was due: every day but Sunday, and not a day marked
  // "site closed".
  final closedDays = {for (final e in dayEvents) if (e.kind == 'submitted' && e.siteClosed) e.workDate};
  List<String> dueDays(PilotPeriod p) => [
        for (var d = p.from; !d.isAfter(p.to); d = d.add(const Duration(days: 1)))
          if (d.weekday != DateTime.sunday && !closedDays.contains(isoDay(d))) isoDay(d),
      ];
  // A day's report: the daily report or the day close sent. On time when
  // it was written the same day.
  final reportedOn = <String, bool>{};
  void mark(String day, bool onTime) => reportedOn[day] = (reportedOn[day] ?? false) || onTime;
  for (final d in dprs) {
    mark(isoDay(d.entryDate.toLocal()), _sameDay(d.createdAt, d.entryDate));
  }
  for (final e in dayEvents.where((e) => e.kind == 'submitted' && !e.siteClosed)) {
    mark(e.workDate, isoDay(e.createdAt.toLocal()) == e.workDate);
  }

  final rows = <ScoreRow>[
    ScoreRow('Days with a daily report', per((p) {
      final due = dueDays(p);
      return _share(due.where(reportedOn.containsKey).length, due.length);
    }), better: Better.up, format: _pct, note: 'Of the days work was due (Sundays and days marked closed left out).'),
    ScoreRow('Daily reports sent the same day', per((p) {
      final due = dueDays(p);
      return _share(due.where((d) => reportedOn[d] == true).length, due.length);
    }), better: Better.up, format: _pct),
    ScoreRow('Cash short at counts', per((p) {
      if (books.isEmpty) return null;
      return books.fold<double>(0, (s, b) => s + b.unexplained(from: p.fromDay, to: p.toDay));
    }), better: Better.down, format: rupees, note: 'Cash book counts below what the book said.'),
    ScoreRow('Cash spent with no bill', per((p) {
      if (books.isEmpty) return null;
      return books.fold<double>(0, (s, b) => s + b.spentWithoutBill(from: p.fromDay, to: p.toDay));
    }), better: Better.down, format: rupees),
    ScoreRow('Expenses with a bill attached', per((p) {
      final xs = expenses.where((e) => p.containsDay(_dayOf(e.incurredOn))).toList();
      final total = xs.fold<double>(0, (s, e) => s + e.amount);
      if (total <= 0) return null;
      final billed = xs.where((e) => (billCounts[e.id] ?? 0) > 0).fold<double>(0, (s, e) => s + e.amount);
      return billed * 100 / total;
    }), better: Better.up, format: _pct, note: 'By rupees spent.'),
    ScoreRow('Deliveries with a challan photo', per((p) {
      final xs = receipts.where((r) => p.contains(r.receivedOn)).toList();
      return _share(xs.where((r) => (slips[r.id] ?? const []).isNotEmpty).length, xs.length);
    }), better: Better.up, format: _pct),
    ScoreRow('Labour marked inside the site fence', per((p) {
      final xs = punches.where((a) => p.contains(a.punchIn) && a.withinGeofence != null).toList();
      return _share(xs.where((a) => a.withinGeofence == true).length, xs.length);
    }), better: Better.up, format: _pct, note: 'Of punches with a GPS fix, at a site with a location set.'),
    ScoreRow('Budget overruns flagged', per((p) => overruns.where((a) => p.contains(a.createdAt)).length.toDouble()),
        better: Better.neither, format: _count, note: 'Raised while there was still time to act.'),
    ScoreRow('Days from bill to payment', per((p) {
      final gaps = <double>[];
      for (final a in allocations) {
        final pay = payments[a.paymentId];
        final bill = bills[a.billId];
        if (pay == null || bill == null || !p.contains(pay.receivedOn)) continue;
        gaps.add(pay.receivedOn.difference(bill.billDate).inHours / 24);
      }
      return gaps.isEmpty ? null : gaps.reduce((a, b) => a + b) / gaps.length;
    }), better: Better.down, format: _days, note: 'Payments put against a bill in the period.'),
    ScoreRow('Office time saved (estimate)', per((p) {
      final reports = dprs.where((d) => p.contains(d.entryDate)).length;
      final att = punches.where((a) => p.contains(a.punchIn)).length;
      final vouchers = expenses.where((e) => p.contains(e.createdAt)).length;
      final deliveries = receipts.where((r) => r.amount > 0 && p.contains(r.receivedOn)).length;
      final billsMade = bills.values.where((b) => p.contains(b.billDate)).length;
      return (reports * minutesPerReport +
              att * minutesPerAttendance +
              vouchers * minutesPerVoucher +
              deliveries * minutesPerDelivery +
              billsMade * minutesPerBill) /
          60;
    }), better: Better.neither, format: _hours, note: 'Fixed minutes per record, the same as the time-saved card.'),
  ];
  return PilotScorecard(site: site, start: start, periods: periods, rows: rows);
}

const _ink = PdfColor.fromInt(0xFF1B2733);
const _muted = PdfColor.fromInt(0xFF5B6B80);
const _line = PdfColor.fromInt(0xFFDDE3EB);
const _good = PdfColor.fromInt(0xFF1E7A46);
const _bad = PdfColor.fromInt(0xFFB3261E);

/// The scorecard as a one-page PDF, in English like the other packs.
Future<Uint8List> buildPilotScorecardPdf(PilotScorecard card,
    {required String companyName, PdfBranding branding = const PdfBranding(), DateTime? now}) async {
  final doc = pw.Document(title: 'Pilot scorecard ${card.site.name}', creator: 'FieldOS');
  final accent = brandInk(branding);
  pw.Widget t(String s, {double size = 9, bool bold = false, PdfColor color = _ink, pw.TextAlign? align}) => pw.Text(
        pdfSafe(s),
        textAlign: align,
        style: pw.TextStyle(fontSize: size, color: color, fontWeight: bold ? pw.FontWeight.bold : null),
      );
  pw.Widget cell(String s, {bool bold = false, PdfColor color = _ink, bool right = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        child: t(s, bold: bold, color: color, align: right ? pw.TextAlign.right : null),
      );
  final last = card.periods.last;
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        if (branding.logo != null) ...[
          pw.Image(pw.MemoryImage(branding.logo!), height: 40, fit: pw.BoxFit.contain),
          pw.SizedBox(width: 10),
        ],
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            t(companyName, size: 14, bold: true, color: accent),
            t(card.site.name, color: _muted),
          ]),
        ),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          t('PILOT SCORECARD', size: 13, bold: true, color: accent),
          t('Pilot started ${fmtDate(card.start)}', color: _muted),
          t('Figures to ${fmtDate(last.started ? last.to : card.periods.lastWhere((p) => p.started).to)}', color: _muted),
          t('Made on ${fmtDate(now ?? DateTime.now())}', size: 7, color: _muted),
        ]),
      ]),
      pw.Container(height: 2, color: accent, margin: const pw.EdgeInsets.symmetric(vertical: 10)),
      t('Every figure comes from what this site recorded in FieldOS. Week 1 is the baseline.', color: _muted),
      pw.SizedBox(height: 10),
      pw.Table(
        columnWidths: {0: const pw.FlexColumnWidth(3.2)},
        border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.5), bottom: pw.BorderSide(color: _line)),
        children: [
          pw.TableRow(decoration: pw.BoxDecoration(color: accent), children: [
            cell('Measure', bold: true, color: PdfColors.white),
            for (final p in card.periods) cell(p.label, bold: true, color: PdfColors.white, right: true),
            cell('Change', bold: true, color: PdfColors.white, right: true),
          ]),
          for (final r in card.rows)
            pw.TableRow(children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  t(r.measure, bold: true),
                  if (r.note != null) t(r.note!, size: 7, color: _muted),
                ]),
              ),
              for (var i = 0; i < card.periods.length; i++) cell(r.cell(i), right: true),
              cell(r.change,
                  bold: true, right: true, color: r.change == 'better' ? _good : (r.change == 'worse' ? _bad : _muted)),
            ]),
        ],
      ),
      pw.Spacer(),
      t(branding.footerLine, size: 7, color: _muted),
    ]),
  ));
  return doc.save();
}
