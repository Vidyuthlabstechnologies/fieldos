/// A payment voucher for one expense, half an A4 sheet: company and site
/// name, voucher number, who was paid, how much in figures and words, the
/// GST split when the bill had GST, and lines for the receiver's and the
/// approver's signatures.
///
/// Onsite's review: "No voucher number or transaction number available in
/// the app, which is not suitable for accounting... Also work name or site
/// name is not printed on voucher if we want to sign from the party."
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/money/bill_pdf.dart' show pdfSafe;
import 'package:fieldos_mobile/features/company/branding.dart';
import 'package:fieldos_mobile/features/money/billing_calc.dart' show rupeesInWords;
import 'package:fieldos_mobile/features/money/money_book.dart';

const _ink = PdfColor.fromInt(0xFF1B2733);
const _muted = PdfColor.fromInt(0xFF5B6B80);
const _line = PdfColor.fromInt(0xFFDDE3EB);
const _paper = PdfColor.fromInt(0xFFF4F6F9);

const _modes = {'cash': 'Cash', 'upi': 'UPI', 'bank': 'Bank transfer', 'cheque': 'Cheque'};

/// Who the voucher says was paid: the worker, else the typed name.
String voucherPayee(SiteExpense e, {String? workerName}) {
  if (e.workerId != null && workerName != null && workerName.isNotEmpty) return workerName;
  return e.paidTo?.trim() ?? '';
}

Future<Uint8List> buildVoucherPdf({
  required SiteExpense expense,
  bool provisional = false,
  required String companyName,
  required String siteName,
  String? workerName,
  String? enteredBy,
  PdfBranding branding = const PdfBranding(),
}) async {
  final e = expense;
  final doc = pw.Document(title: 'Payment voucher ${voucherLabel(e.voucherNo)}', creator: 'FieldOS');
  pw.Widget t(String s, {double size = 10, bool bold = false, PdfColor color = _ink, pw.TextAlign? align}) => pw.Text(
        pdfSafe(s),
        textAlign: align,
        style: pw.TextStyle(fontSize: size, color: color, fontWeight: bold ? pw.FontWeight.bold : null),
      );
  pw.Widget row(String label, String value, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 110, child: t(label, color: _muted)),
          pw.Expanded(child: t(value, bold: bold)),
        ]),
      );
  final payee = voucherPayee(e, workerName: workerName);
  final gst = (e.gstPct ?? 0) > 0 ? gstSplit(e.amount, e.gstPct!, interState: e.gstInterState) : null;
  String money(double v) => rupees(v, paise: true);

  pw.Widget signature(String label) => pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(height: 34),
          pw.Container(height: 0.8, color: _ink),
          pw.SizedBox(height: 4),
          t(label, size: 9, color: _muted),
        ]),
      );

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a5.landscape,
    margin: const pw.EdgeInsets.all(28),
    build: (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          if (branding.logo != null) ...[
            pw.Image(pw.MemoryImage(branding.logo!), height: 40, fit: pw.BoxFit.contain),
            pw.SizedBox(width: 10),
          ],
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              t(companyName, size: 15, bold: true),
              pw.SizedBox(height: 2),
              t('Site: $siteName', color: _muted),
            ]),
          ),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            t(e.voided ? 'PAYMENT VOUCHER (CANCELLED)' : 'PAYMENT VOUCHER', size: 11, bold: true),
            pw.SizedBox(height: 2),
            t('No. ${voucherLabel(e.voucherNo)}', size: 12, bold: true),
            // Not yet numbered by the server: this copy's number may change.
            if (provisional) t('Provisional number', size: 9, color: _muted),
            t('Date: ${fmtDate(expenseDay(e))}', color: _muted),
          ]),
        ]),
        pw.SizedBox(height: 10),
        pw.Container(height: 1, color: _line),
        pw.SizedBox(height: 8),
        row('Paid to', payee.isEmpty ? '-' : payee, bold: true),
        row('Towards', e.category),
        if (e.note != null && e.note!.trim().isNotEmpty) row('Details', e.note!.trim()),
        if (e.mode != null) row('Mode', _modes[e.mode] ?? e.mode!),
        if (gst != null) ...[
          row('Before GST', money(gst.taxable)),
          if (gst.igst > 0)
            row('IGST ${_pct(e.gstPct!)}', money(gst.igst))
          else
            row('CGST + SGST', '${money(gst.cgst)} + ${money(gst.sgst)} (${_pct(e.gstPct!)})'),
        ],
        if (e.voided) row('Cancelled', e.voidReason?.trim().isNotEmpty == true ? e.voidReason!.trim() : 'Yes'),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const pw.BoxDecoration(color: _paper),
          child: pw.Row(children: [
            pw.Expanded(child: t(rupeesInWords(e.amount), size: 9.5)),
            pw.SizedBox(width: 12),
            t(money(e.amount), size: 15, bold: true),
          ]),
        ),
        pw.Spacer(),
        pw.Row(children: [
          signature('Received by (signature)'),
          pw.SizedBox(width: 28),
          signature('Paid by${enteredBy == null || enteredBy.isEmpty ? '' : ': $enteredBy'}'),
          pw.SizedBox(width: 28),
          signature('Approved by'),
        ]),
        if (branding.showFooter) ...[
          pw.SizedBox(height: 8),
          t('Made with FieldOS', size: 7, color: _muted, align: pw.TextAlign.right),
        ],
      ],
    ),
  ));
  return doc.save();
}

String _pct(double v) => '${v == v.roundToDouble() ? v.toInt() : v}%';

/// Builds the voucher and opens the share sheet (print, WhatsApp, Drive).
Future<void> shareVoucher({
  required SiteExpense expense,
  bool provisional = false,
  required String companyName,
  required String siteName,
  String? workerName,
  String? enteredBy,
  PdfBranding branding = const PdfBranding(),
}) async {
  final bytes = await buildVoucherPdf(
      expense: expense,
      provisional: provisional,
      companyName: companyName,
      siteName: siteName,
      workerName: workerName,
      enteredBy: enteredBy,
      branding: branding);
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/Voucher_${voucherLabel(expense.voucherNo).replaceAll('-', '')}_'
      '${siteName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}.pdf');
  await file.writeAsBytes(bytes);
  final payee = voucherPayee(expense, workerName: workerName);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: 'application/pdf')],
    text: 'Voucher ${voucherLabel(expense.voucherNo)}, $siteName: ${rupees(expense.amount, paise: true)}'
        '${payee.isEmpty ? '' : ' to $payee'} (${expense.category}).',
  ));
}
