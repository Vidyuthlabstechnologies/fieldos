/// The weekly close pack for accounts: one PDF a project manager can
/// forward inside the company. Wage and advance summary, expense vouchers,
/// deliveries checked against their orders, days without attendance, every
/// exception, the dated approval history, and the bill and delivery-slip
/// photos behind them. English, like the bill and voucher PDFs: it goes to
/// the office.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/close/week_close.dart';
import 'package:fieldos_mobile/features/company/branding.dart';
import 'package:fieldos_mobile/features/money/bill_pdf.dart' show pdfSafe;
import 'package:fieldos_mobile/features/money/money_book.dart' show voucherLabel;

const _ink = PdfColor.fromInt(0xFF1B2733);
const _muted = PdfColor.fromInt(0xFF5B6B80);
const _line = PdfColor.fromInt(0xFFDDE3EB);
const _paper = PdfColor.fromInt(0xFFF4F6F9);
const _danger = PdfColor.fromInt(0xFFB3412E);

/// At most this many photos go in, so a busy week's pack still opens on a
/// phone and fits in a WhatsApp message.
const packPhotoLimit = 40;

/// One photo behind an item.
class PackPhoto {
  const PackPhoto(this.path, this.caption);
  final String path;
  final String caption;
}

String _money(num v) => pdfSafe(rupees(v, paise: true));

String _date(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final l = d.toLocal();
  return '${l.day} ${m[l.month - 1]} ${l.year}';
}

String _dateTime(DateTime d) {
  final l = d.toLocal();
  return '${_date(l)} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

String _stateEnglish(ItemState s) => switch (s) {
      ItemState.waiting => 'To review',
      ItemState.approved => 'Approved',
      ItemState.sentBack => 'Sent back',
      ItemState.fixed => 'Corrected, to review',
      ItemState.changed => 'Changed after approval',
    };

String _kindEnglish(String kind) => switch (kind) {
      'wages' => 'Wages',
      'expense' => 'Expense',
      'receipt' => 'Delivery',
      'attendance' => 'Attendance',
      'week' => 'Week',
      _ => kind,
    };

/// The week's status in one line.
String packStatusLine(WeekClose w, {Map<String, String> names = const {}}) {
  final d = w.weekDecision;
  if (w.isClosed && d != null) {
    final who = names[d.decidedBy] ?? 'a manager';
    return w.changedSinceClose
        ? 'Closed by $who on ${_dateTime(d.createdAt)}, but ${w.waiting.length + w.sentBack.length} item(s) changed since'
        : 'Closed by $who on ${_dateTime(d.createdAt)}';
  }
  return 'Open: ${w.waiting.length} to review, ${w.sentBack.length} sent back, ${w.approved.length} approved';
}

/// The photos to print: bills of the week's expenses, slips of its
/// deliveries.
Future<List<PackPhoto>> packPhotos(AppDatabase db, WeekClose w) async {
  final out = <PackPhoto>[];
  for (final i in w.items) {
    if (i.kind == CloseKind.expense && i.evidence > 0) {
      for (final a in await db.expenseDao.attachmentsFor(i.id)) {
        out.add(PackPhoto(a.filePath, '${voucherLabel(i.expense?.voucherNo)} ${i.expense?.category ?? ''} bill'.trim()));
      }
    }
    if (i.kind == CloseKind.receipt && i.evidence > 0) {
      for (final a in await db.materialDao.slipsFor(i.id)) {
        out.add(PackPhoto(a.filePath, '${i.title} - delivery slip'));
      }
    }
  }
  return out;
}

Future<Uint8List> buildWeekClosePack({
  required WeekClose week,
  required String companyName,
  Map<String, String> names = const {},
  Map<String, String> workerNames = const {},
  List<PackPhoto> photos = const [],
  PdfBranding branding = const PdfBranding(),
  DateTime? now,
}) async {
  final w = week;
  final doc = pw.Document(title: 'Weekly close ${w.project.name} ${w.weekKey}', creator: 'FieldOS');
  pw.Widget t(String s, {double size = 9, bool bold = false, PdfColor color = _ink}) => pw.Text(pdfSafe(s),
      style: pw.TextStyle(fontSize: size, color: color, fontWeight: bold ? pw.FontWeight.bold : null));

  pw.Widget table(List<String> head, List<List<String>> rows, {Map<int, pw.TableColumnWidth>? widths}) {
    if (rows.isEmpty) return pw.Padding(padding: const pw.EdgeInsets.only(bottom: 8), child: t('None this week.', color: _muted));
    return pw.TableHelper.fromTextArray(
      headers: [for (final h in head) pdfSafe(h)],
      data: [for (final r in rows) [for (final c in r) pdfSafe(c)]],
      headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _ink),
      cellStyle: const pw.TextStyle(fontSize: 8, color: _ink),
      headerDecoration: const pw.BoxDecoration(color: _paper),
      border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.5)),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      columnWidths: widths,
    );
  }

  pw.Widget heading(String s) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14, bottom: 6), child: t(s, size: 12, bold: true));

  String flags(CloseItem i) => i.flags.map((f) => f.english).join('; ');
  String lastNote(CloseItem i) {
    final n = i.last?.note?.trim() ?? '';
    return n.isEmpty ? '' : ' - "$n"';
  }

  final wages = w.items.where((i) => i.kind == CloseKind.wages).toList();
  final expenses = w.items.where((i) => i.kind == CloseKind.expense).toList();
  final receipts = w.items.where((i) => i.kind == CloseKind.receipt).toList();
  final days = w.items.where((i) => i.kind == CloseKind.attendance).toList();
  final last = w.to.subtract(const Duration(days: 1));

  final images = <(pw.MemoryImage, String)>[];
  for (final p in photos.take(packPhotoLimit)) {
    final lower = p.path.toLowerCase();
    if (!(lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png'))) continue;
    final f = File(p.path);
    if (!f.existsSync()) continue;
    try {
      images.add((pw.MemoryImage(f.readAsBytesSync()), p.caption));
    } catch (_) {
      // A damaged or half-downloaded photo is left out, not the whole pack.
    }
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    footer: (ctx) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      t(branding.showFooter ? 'Made with FieldOS' : '', size: 7, color: _muted),
      t('Page ${ctx.pageNumber} of ${ctx.pagesCount}', size: 7, color: _muted),
    ]),
    build: (ctx) => [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            t(companyName, size: 10, color: _muted),
            t('Weekly close - ${w.project.name}', size: 16, bold: true),
            t('${_date(w.from)} to ${_date(last)}', size: 10),
            pw.SizedBox(height: 4),
            t(packStatusLine(w, names: names), size: 9, bold: true, color: w.isClosed && !w.changedSinceClose ? _ink : _danger),
          ]),
        ),
        if (branding.logo != null) pw.SizedBox(height: 44, child: pw.Image(pw.MemoryImage(branding.logo!))),
      ]),
      heading('Summary'),
      table(['', 'Amount'], [
        ['Wages earned', _money(w.wagesEarned)],
        ['Wages and advances paid', _money(w.wagesPaid)],
        ['Wages still due', _money(w.wagesDue)],
        ['Advances not yet worked off', _money(w.advancesOut)],
        ['Site expenses (not cancelled)', _money(w.expensesTotal)],
        ['Material delivered (invoice value)', _money(w.receiptsTotal)],
        ['Approved so far', _money(w.approvedTotal)],
      ], widths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(1.4)}),
      pw.SizedBox(height: 4),
      t('${w.items.length} items: ${w.approved.length} approved, ${w.sentBack.length} sent back, '
          '${w.waiting.length} to review. ${w.flagged.length} with exceptions.', color: _muted),
      heading('Wages and advances'),
      table(['Worker', 'Days', 'Rate', 'Earned', 'Paid', 'Balance', 'Status', 'Exceptions'], [
        for (final i in wages)
          [
            i.title,
            fmtQty(i.wage!.days),
            i.wage!.dailyWage == null ? '-' : _money(i.wage!.dailyWage!),
            _money(i.wage!.earned),
            _money(i.wage!.paidInPeriod),
            i.wage!.balanceDue < 0 ? 'Advance ${_money(-i.wage!.balanceDue)}' : _money(i.wage!.balanceDue),
            _stateEnglish(i.state) + lastNote(i),
            flags(i),
          ],
      ]),
      heading('Expense vouchers'),
      table(['Voucher', 'Date', 'Category', 'Paid to', 'Amount', 'Bill', 'Status', 'Exceptions'], [
        for (final i in expenses)
          [
            voucherLabel(i.expense!.voucherNo),
            _date(i.day),
            i.expense!.category,
            i.expense!.workerId != null
                ? (workerNames[i.expense!.workerId] ?? i.expense!.paidTo ?? 'Worker')
                : (i.expense!.paidTo ?? ''),
            i.expense!.voided ? '(${_money(i.expense!.amount)}) cancelled' : _money(i.expense!.amount),
            i.evidence > 0 ? 'Yes' : 'No',
            _stateEnglish(i.state) + lastNote(i),
            flags(i),
          ],
      ]),
      heading('Material receipts'),
      table(['Date', 'Material', 'Received', 'Ordered', 'Accepted', 'Invoice', 'Slip', 'Status', 'Exceptions'], [
        for (final i in receipts)
          [
            _date(i.day),
            i.receipt!.materialName,
            [fmtQty(i.quantity ?? 0), i.unit].where((s) => s.isNotEmpty).join(' '),
            i.orderedQty == null ? 'No PO' : fmtQty(i.orderedQty!),
            i.acceptedQty == null
                ? '-'
                : (i.acceptedQty! < (i.quantity ?? 0) - 0.0001
                    ? '${fmtQty(i.acceptedQty!)} (short ${fmtQty((i.quantity ?? 0) - i.acceptedQty!)})'
                    : fmtQty(i.acceptedQty!)),
            _money(i.amount ?? 0),
            i.evidence > 0 ? 'Yes' : 'No',
            _stateEnglish(i.state) + lastNote(i),
            flags(i),
          ],
      ]),
      if (days.isNotEmpty) ...[
        heading('Days without attendance'),
        table(['Day', 'Exception', 'Status'], [
          for (final i in days) [_date(i.day), flags(i), _stateEnglish(i.state) + lastNote(i)],
        ]),
      ],
      heading('Approval history'),
      table(['When', 'Who', 'Item', 'Decision', 'Note'], [
        for (final r in w.history)
          [
            _dateTime(r.createdAt),
            names[r.decidedBy] ?? 'Team member',
            r.itemKind == 'week' ? 'Week' : '${_kindEnglish(r.itemKind)}: ${_itemName(w, r)}',
            decisionEnglish(r.decision) +
                (r.acceptedQty != null && r.itemKind == 'receipt' ? ' (${fmtQty(r.acceptedQty!)} accepted)' : ''),
            r.note ?? '',
          ],
      ], widths: {
        0: const pw.FlexColumnWidth(1.6),
        1: const pw.FlexColumnWidth(1.4),
        2: const pw.FlexColumnWidth(2.4),
        3: const pw.FlexColumnWidth(1.4),
        4: const pw.FlexColumnWidth(2.4),
      }),
      pw.SizedBox(height: 10),
      t('Made on ${_dateTime(now ?? DateTime.now())} from the site\'s own records in FieldOS.', size: 7, color: _muted),
    ],
  ));

  if (images.isNotEmpty) {
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) => [
        t('Supporting photos', size: 12, bold: true),
        if (photos.length > images.length) t('${photos.length - images.length} more are on the phone.', color: _muted),
        pw.SizedBox(height: 8),
        pw.Wrap(spacing: 10, runSpacing: 10, children: [
          for (final (img, caption) in images)
            pw.Container(
              width: 255,
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Container(
                  height: 190,
                  alignment: pw.Alignment.center,
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: _line)),
                  child: pw.Image(img, fit: pw.BoxFit.contain),
                ),
                pw.SizedBox(height: 2),
                t(caption, size: 8),
              ]),
            ),
        ]),
      ],
    ));
  }
  return doc.save();
}

String _itemName(WeekClose w, CloseReview r) {
  for (final i in w.items) {
    if (i.kind.key == r.itemKind && i.id == r.itemId) {
      return i.kind == CloseKind.expense
          ? '${voucherLabel(i.expense?.voucherNo)} ${_money(i.amount ?? 0)}'.trim()
          : i.kind == CloseKind.attendance
              ? _date(i.day)
              : i.title;
    }
  }
  return 'removed record';
}

/// The CSV next to the PDF, for accounts to load: one line per item.
String weekCloseCsv(WeekClose w) {
  String c(Object? v) {
    final s = '${v ?? ''}';
    return s.contains(RegExp('[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  final b = StringBuffer('site,week_start,kind,item,date,amount,quantity,accepted_qty,status,exceptions,last_note\n');
  for (final i in w.items) {
    b.writeln([
      w.project.name,
      w.weekKey,
      i.kind.key,
      i.kind == CloseKind.expense ? '${voucherLabel(i.expense?.voucherNo)} ${i.expense?.category ?? ''}'.trim() : i.title,
      '${i.day.year}-${i.day.month.toString().padLeft(2, '0')}-${i.day.day.toString().padLeft(2, '0')}',
      i.amount?.toStringAsFixed(2) ?? '',
      i.quantity == null ? '' : fmtQty(i.quantity!),
      i.acceptedQty == null ? '' : fmtQty(i.acceptedQty!),
      _stateEnglish(i.state),
      i.flags.map((f) => f.english).join('; '),
      i.last?.note ?? '',
    ].map(c).join(','));
  }
  return b.toString();
}
