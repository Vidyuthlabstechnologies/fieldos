/// A library report as a PDF (with the company's logo, colour and footer)
/// or as an Excel sheet, ready to share on WhatsApp or mail.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/features/company/branding.dart';
import 'package:fieldos_mobile/features/export/xlsx_writer.dart';
import 'package:fieldos_mobile/features/money/bill_pdf.dart' show BillingProfile, pdfSafe;
import 'package:fieldos_mobile/features/reports/report_library.dart';

const _ink = PdfColor.fromInt(0xFF1B2733);
const _muted = PdfColor.fromInt(0xFF5B6B80);
const _line = PdfColor.fromInt(0xFFDDE3EB);
const _paper = PdfColor.fromInt(0xFFF4F6F9);

/// Column heads that hold rupees, so the PDF writes them as money.
const moneyHeaders = {
  'Amount', 'Worth', 'Value', 'Cost', 'Gross', 'Net', 'PF', 'ESI', 'PT', 'Billed', 'Received', 'Spent', 'Agreed',
  'Average rate', 'Daily wage', 'Earned', 'GST', 'GST in it', 'Estimate', 'Given', 'Recovered', 'Still owed',
  'To deposit', 'Still to collect', 'Saved vs dearest', 'Landed', 'Advance', 'Other', 'Professional tax', 'To recover',
  'Received worth', 'Ordered worth', 'Short worth', 'Left to bill', 'Estimated cost', 'Approved cost', 'Day rate',
  'Cost an hour', 'Net payable', 'Received less spent', 'Total', 'PF staff', 'PF company', 'ESI staff', 'ESI company',
  'Cost to company',
};

String cellText(Object? v, {bool money = false}) => switch (v) {
      null => '',
      DateTime d => fmtDate(d),
      num n when money => rupees(n),
      num n => fmtQty(n),
      _ => '$v',
    };

/// "1 Nov 2026 to 30 Nov 2026".
String periodText(DateTime from, DateTime to) => '${fmtDate(from)} to ${fmtDate(to.subtract(const Duration(days: 1)))}';

Future<Uint8List> buildReportPdf({
  required ReportDef report,
  required ReportTable table,
  required String companyName,
  required String sitesText,
  String? periodLine,
  BillingProfile profile = const BillingProfile(),
  PdfBranding branding = const PdfBranding(),
  DateTime? now,
}) async {
  final doc = pw.Document(title: '${report.title} $companyName', creator: 'FieldOS');
  final accent = brandInk(branding);
  final wide = table.headers.length > 6;
  final money = [for (final h in table.headers) moneyHeaders.contains(h)];
  final numeric = [
    for (var i = 0; i < table.headers.length; i++) table.rows.any((r) => r[i] is num) || money[i],
  ];

  pw.Widget t(String s, {double size = 8, bool bold = false, PdfColor color = _ink, pw.TextAlign? align}) => pw.Text(
        pdfSafe(s),
        textAlign: align,
        style: pw.TextStyle(fontSize: size, color: color, fontWeight: bold ? pw.FontWeight.bold : null),
      );

  pw.Widget cell(Object? v, int i, {bool bold = false, PdfColor color = _ink}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: t(cellText(v, money: money[i]), bold: bold, color: color, align: numeric[i] ? pw.TextAlign.right : null),
      );

  final totals = table.totals;
  doc.addPage(pw.MultiPage(
    pageFormat: wide ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    header: (ctx) => ctx.pageNumber == 1
        ? pw.SizedBox()
        : pw.Padding(padding: const pw.EdgeInsets.only(bottom: 6), child: t('${report.title}  |  $companyName', color: _muted)),
    footer: (ctx) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Expanded(child: t(branding.footerLine, size: 7, color: _muted)),
      t('Page ${ctx.pageNumber} of ${ctx.pagesCount}', size: 7, color: _muted),
    ]),
    build: (_) => [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        if (branding.logo != null) ...[
          pw.Image(pw.MemoryImage(branding.logo!), height: 40, fit: pw.BoxFit.contain),
          pw.SizedBox(width: 10),
        ],
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            t(companyName, size: 14, bold: true, color: accent),
            if (profile.address.trim().isNotEmpty) t(profile.address.trim(), color: _muted),
            if (profile.gstin.trim().isNotEmpty) t('GSTIN ${profile.gstin.trim()}', color: _muted),
          ]),
        ),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          t(report.title.toUpperCase(), size: 12, bold: true, color: accent),
          t(sitesText, color: _muted),
          if (periodLine != null) t(periodLine, color: _muted),
          t('Made on ${fmtDate(now ?? DateTime.now())}', size: 7, color: _muted),
        ]),
      ]),
      pw.Container(height: 2, color: accent, margin: const pw.EdgeInsets.symmetric(vertical: 8)),
      if (table.rows.isEmpty)
        pw.Padding(padding: const pw.EdgeInsets.all(16), child: t('Nothing recorded for this report.', size: 10, color: _muted))
      else
        pw.Table(
          border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.5), bottom: pw.BorderSide(color: _line)),
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: accent),
              repeat: true,
              children: [for (var i = 0; i < table.headers.length; i++) cell(table.headers[i], i, bold: true, color: PdfColors.white)],
            ),
            for (final r in table.rows) pw.TableRow(children: [for (var i = 0; i < r.length; i++) cell(r[i], i)]),
            if (totals != null)
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _paper),
                children: [for (var i = 0; i < totals.length; i++) cell(totals[i], i, bold: true)],
              ),
          ],
        ),
      if (table.note != null) pw.Padding(padding: const pw.EdgeInsets.only(top: 6), child: t(table.note!, size: 7, color: _muted)),
    ],
  ));
  return doc.save();
}

/// The report as one Excel sheet, with a total row when it has one.
Uint8List buildReportXlsx(ReportDef report, ReportTable table) {
  final totals = table.totals;
  return buildXlsx([
    XlsxSheet(report.title, table.headers, [...table.rows, ?totals]),
  ]);
}

String reportFileName(ReportDef report, DateTime now, String ext) {
  final clean = report.title.replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  final d = '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
  return 'FieldOS $clean $d.$ext';
}

Future<void> shareReportFile(Uint8List bytes, String name, String mime, String text) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: mime)], text: text));
}
