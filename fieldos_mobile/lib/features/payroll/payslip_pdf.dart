/// A month's payslip as a PDF, with the company's logo and address, to
/// hand or WhatsApp to the staff member.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/company/branding.dart';
import 'package:fieldos_mobile/features/money/bill_pdf.dart' show BillingProfile, pdfSafe;
import 'package:fieldos_mobile/features/money/billing_calc.dart' show rupeesInWords;
import 'package:fieldos_mobile/features/payroll/payroll_rules.dart';

const _ink = PdfColor.fromInt(0xFF1B2733);
const _muted = PdfColor.fromInt(0xFF5B6B80);
const _line = PdfColor.fromInt(0xFFDDE3EB);
const _paper = PdfColor.fromInt(0xFFF4F6F9);

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October',
  'November', 'December'];

/// "November 2026" for "2026-11".
String monthTitle(String key) {
  final d = monthStart(key);
  return '${_months[d.month - 1]} ${d.year}';
}

String _money(double v) => pdfSafe(rupees(v));

Future<Uint8List> buildPayslipPdf({
  required PayrollLine line,
  required StaffMember staff,
  required String companyName,
  String? siteName,
  BillingProfile profile = const BillingProfile(),
  PdfBranding branding = const PdfBranding(),
}) async {
  final doc = pw.Document(title: 'Payslip ${staff.name} ${line.month}', creator: 'FieldOS');

  pw.Widget t(String s, {double size = 9, bool bold = false, PdfColor color = _ink, pw.TextAlign? align}) => pw.Text(
        pdfSafe(s),
        textAlign: align,
        style: pw.TextStyle(fontSize: size, color: color, fontWeight: bold ? pw.FontWeight.bold : null),
      );

  pw.Widget row(String label, String value, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: pw.Row(children: [
          pw.Expanded(child: t(label, bold: bold)),
          t(value, bold: bold, align: pw.TextAlign.right),
        ]),
      );

  pw.Widget box(String title, List<pw.Widget> rows) => pw.Container(
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _line)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.Container(color: _paper, padding: const pw.EdgeInsets.all(6), child: t(title, bold: true)),
          ...rows,
        ]),
      );

  final deductions = line.pfEmployee + line.esiEmployee + line.pt + line.advanceRecovery + line.otherDeduction;
  final days = line.paidDays == line.paidDays.roundToDouble() ? line.paidDays.toInt().toString() : fmtQty(line.paidDays);

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        if (branding.logo != null) ...[
          pw.Image(pw.MemoryImage(branding.logo!), height: 44, fit: pw.BoxFit.contain),
          pw.SizedBox(width: 12),
        ],
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            t(companyName, size: 15, bold: true, color: brandInk(branding)),
            if (profile.address.trim().isNotEmpty) t(profile.address.trim(), color: _muted),
          ]),
        ),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          t('PAYSLIP', size: 14, bold: true),
          t(monthTitle(line.month), color: _muted),
        ]),
      ]),
      pw.SizedBox(height: 16),
      box('Employee', [
        row('Name', staff.name),
        if (staff.designation != null) row('Designation', staff.designation!),
        if (siteName != null) row('Site', siteName),
        if (staff.uan != null) row('UAN', staff.uan!),
        row('Days paid', '$days of ${line.daysInMonth}'),
      ]),
      pw.SizedBox(height: 12),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: box('Earnings', [
            row('Basic', _money(line.basic)),
            if (line.hra > 0) row('HRA', _money(line.hra)),
            if (line.otherAllowance > 0) row('Other allowance', _money(line.otherAllowance)),
            row('Gross', _money(line.gross), bold: true),
          ]),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: box('Deductions', [
            if (line.pfEmployee > 0) row('Provident fund', _money(line.pfEmployee)),
            if (line.esiEmployee > 0) row('ESI', _money(line.esiEmployee)),
            if (line.pt > 0) row('Professional tax', _money(line.pt)),
            if (line.advanceRecovery > 0) row('Advance recovered', _money(line.advanceRecovery)),
            if (line.otherDeduction > 0) row('Other', _money(line.otherDeduction)),
            row('Total deductions', _money(deductions), bold: true),
          ]),
        ),
      ]),
      pw.SizedBox(height: 12),
      pw.Container(
        color: _paper,
        padding: const pw.EdgeInsets.all(10),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          row('Net pay', _money(line.net), bold: true),
          pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 6), child: t(rupeesInWords(line.net), color: _muted)),
          if (line.status == 'paid' && line.paidOn != null)
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(6, 4, 6, 0),
              child: t('Paid on ${fmtDate(line.paidOn!)}${line.paidMode == null ? '' : ' by ${payModes[line.paidMode] ?? line.paidMode}'}',
                  color: _muted),
            ),
        ]),
      ),
      if (line.pfEmployer > 0 || line.esiEmployer > 0) ...[
        pw.SizedBox(height: 8),
        t('Company also pays: ${[
          if (line.pfEmployer > 0) 'PF ${_money(line.pfEmployer)}',
          if (line.esiEmployer > 0) 'ESI ${_money(line.esiEmployer)}',
        ].join(', ')}.', color: _muted, size: 8),
      ],
      pw.Spacer(),
      t('This is a computer-made payslip.', color: _muted, size: 8),
      if (branding.hasFooter) t(branding.footerLine, size: 7, color: _muted, align: pw.TextAlign.right),
    ]),
  ));
  return doc.save();
}

Future<void> sharePayslip({
  required PayrollLine line,
  required StaffMember staff,
  required String companyName,
  String? siteName,
  BillingProfile profile = const BillingProfile(),
  PdfBranding branding = const PdfBranding(),
}) async {
  final bytes = await buildPayslipPdf(
      line: line, staff: staff, companyName: companyName, siteName: siteName, profile: profile, branding: branding);
  final dir = await getTemporaryDirectory();
  final safe = staff.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  final file = File('${dir.path}/Payslip_${safe}_${line.month}.pdf');
  await file.writeAsBytes(bytes);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: 'application/pdf')],
    text: 'Payslip for ${monthTitle(line.month)}: ${staff.name}, net pay ${rupees(line.net)}.',
  ));
}
