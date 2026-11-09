/// The PDF of a client bill: an RA bill with previous, this-bill and
/// cumulative quantities per item, or a GST tax invoice. Both carry the
/// GST split, retention, TDS, the amount payable and the amount in words.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/money/billing_calc.dart';
import 'package:fieldos_mobile/features/company/branding.dart';

const _ink = PdfColor.fromInt(0xFF1B2733);
const _muted = PdfColor.fromInt(0xFF5B6B80);
const _line = PdfColor.fromInt(0xFFDDE3EB);
const _paper = PdfColor.fromInt(0xFFF4F6F9);

/// The built-in PDF font covers Latin-1 only: swap the rupee sign and
/// typographic punctuation, and replace anything else (a name typed in
/// Telugu, an emoji) with "?" rather than drawing boxes.
String pdfSafe(String s) {
  final t = s
      .replaceAll(RegExp('[–—−]'), '-')
      .replaceAll(RegExp('[‘’‚′]'), "'")
      .replaceAll(RegExp('[“”„″]'), '"')
      .replaceAll('₹', 'Rs. ')
      .replaceAll('…', '...');
  return String.fromCharCodes(t.runes.map((r) => r > 0xFF ? 0x3F : r));
}

/// Our side of the bill, kept on the phone per company.
class BillingProfile {
  const BillingProfile({this.gstin = '', this.address = '', this.upiId = ''});
  final String gstin;
  final String address;
  final String upiId;
}

String _money(double v) => pdfSafe(rupees(v, paise: true));

Future<Uint8List> buildBillPdf({
  required ClientBill bill,
  required String companyName,
  required Project project,
  required BillingProfile profile,
  Map<String, double> previousQty = const {},
  PdfBranding branding = const PdfBranding(),
}) async {
  final lines = decodeLines(bill.linesJson);
  final totals = billTotals(lines,
      gstRate: bill.gstRate, interState: bill.interState, retentionPct: bill.retentionPct, tdsPct: bill.tdsPct);
  final isRa = bill.kind == 'ra';
  final title = isRa ? 'RUNNING ACCOUNT BILL' : 'TAX INVOICE';
  final doc = pw.Document(title: '$title ${bill.billNumber}', creator: 'FieldOS');

  pw.Widget t(String s, {double size = 9, bool bold = false, PdfColor color = _ink, pw.TextAlign? align}) => pw.Text(
        pdfSafe(s),
        textAlign: align,
        style: pw.TextStyle(fontSize: size, color: color, fontWeight: bold ? pw.FontWeight.bold : null),
      );

  pw.Widget cell(String s, {bool bold = false, bool right = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: t(s, bold: bold, align: right ? pw.TextAlign.right : null),
      );

  final headers = isRa
      ? ['#', 'Item', 'Unit', 'Rate', 'Previous qty', 'This bill qty', 'Total to date', 'Amount']
      : ['#', 'Description', 'Unit', 'Qty', 'Rate', 'Amount'];

  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: _paper),
      children: [for (final (i, h) in headers.indexed) cell(h, bold: true, right: i >= 3)],
    ),
    for (final (i, l) in lines.indexed)
      pw.TableRow(children: [
        cell('${i + 1}'),
        cell(l.description),
        cell(l.unit),
        if (isRa) ...[
          cell(fmtQty(l.rate), right: true),
          cell(fmtQty(previousQty[l.itemKey] ?? 0), right: true),
          cell(fmtQty(l.qty), right: true),
          cell(fmtQty((previousQty[l.itemKey] ?? 0) + l.qty), right: true),
        ] else ...[
          cell(fmtQty(l.qty), right: true),
          cell(fmtQty(l.rate), right: true),
        ],
        cell(_money(l.amount), right: true),
      ]),
  ];

  pw.Widget sumRow(String label, String value, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(children: [
          pw.Expanded(child: t(label, bold: bold, align: pw.TextAlign.right)),
          pw.SizedBox(width: 100, child: t(value, bold: bold, align: pw.TextAlign.right)),
        ]),
      );

  final rate = fmtQty(bill.gstRate);
  final halfRate = fmtQty(bill.gstRate / 2);
  final client = bill.clientName;

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    footer: branding.showFooter
        ? (ctx) => pw.Align(
              alignment: pw.Alignment.centerRight,
              child: t('Made with FieldOS', size: 7, color: _muted),
            )
        : null,
    build: (_) => [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        if (branding.logo != null) ...[
          pw.Image(pw.MemoryImage(branding.logo!), height: 48, fit: pw.BoxFit.contain),
          pw.SizedBox(width: 12),
        ],
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            t(companyName, size: 16, bold: true),
            if (profile.address.trim().isNotEmpty) t(profile.address.trim(), color: _muted),
            if (profile.gstin.trim().isNotEmpty) t('GSTIN: ${profile.gstin.trim().toUpperCase()}', color: _muted),
          ]),
        ),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          t(title, size: 13, bold: true),
          t('No. ${bill.billNumber}'),
          t('Date ${fmtDate(bill.billDate)}'),
        ]),
      ]),
      pw.SizedBox(height: 14),
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _line)),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              t('Bill to', color: _muted),
              t(client, bold: true),
              if ((bill.clientGstin ?? '').isNotEmpty) t('GSTIN: ${bill.clientGstin}'),
              if ((bill.clientGstin ?? '').length >= 2 && gstStates[bill.clientGstin!.substring(0, 2)] != null)
                t('Place of supply: ${gstStates[bill.clientGstin!.substring(0, 2)]} (${bill.clientGstin!.substring(0, 2)})'),
            ]),
          ),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              t('Project', color: _muted),
              t(project.name, bold: true),
              t('SAC ${bill.sac}'),
            ]),
          ),
        ]),
      ),
      pw.SizedBox(height: 12),
      pw.Table(
        border: pw.TableBorder.all(color: _line, width: 0.5),
        columnWidths: isRa
            ? const {0: pw.FixedColumnWidth(18), 1: pw.FlexColumnWidth(3)}
            : const {0: pw.FixedColumnWidth(18), 1: pw.FlexColumnWidth(4)},
        children: rows,
      ),
      pw.SizedBox(height: 10),
      sumRow(isRa ? 'Value of work this bill' : 'Taxable value', _money(totals.gross)),
      if (bill.interState)
        sumRow('IGST @ $rate%', _money(totals.igst))
      else if (bill.gstRate > 0) ...[
        sumRow('CGST @ $halfRate%', _money(totals.cgst)),
        sumRow('SGST @ $halfRate%', _money(totals.sgst)),
      ],
      sumRow('Total with GST', _money(totals.invoiceTotal), bold: true),
      if (totals.retention > 0) sumRow('Less retention @ ${fmtQty(bill.retentionPct)}%', '- ${_money(totals.retention)}'),
      if (totals.tds > 0) sumRow('Less TDS @ ${fmtQty(bill.tdsPct)}%', '- ${_money(totals.tds)}'),
      if (totals.retention > 0 || totals.tds > 0) sumRow('Amount payable', _money(totals.netPayable), bold: true),
      pw.SizedBox(height: 6),
      t(rupeesInWords(totals.netPayable), bold: true),
      if (profile.upiId.trim().isNotEmpty) ...[
        pw.SizedBox(height: 12),
        pw.Row(children: [
          pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: upiPayLink(profile.upiId.trim(), companyName, totals.netPayable, bill.billNumber),
            width: 72,
            height: 72,
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(child: t('Scan with any UPI app to pay ${_money(totals.netPayable)} to ${profile.upiId.trim()}.')),
        ]),
      ],
      if ((bill.notes ?? '').trim().isNotEmpty) ...[pw.SizedBox(height: 10), t(bill.notes!.trim(), color: _muted)],
      pw.SizedBox(height: 36),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        t('Client / engineer-in-charge', color: _muted),
        t('For $companyName', color: _muted),
      ]),
    ],
  ));
  return doc.save();
}

/// A UPI payment link (NPCI's upi://pay format) for the QR on a bill.
String upiPayLink(String vpa, String payee, double amount, String note) => Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: {
        'pa': vpa,
        'pn': payee,
        'am': amount.toStringAsFixed(2),
        'cu': 'INR',
        'tn': 'Bill $note',
      },
    ).toString();

/// Builds the bill's PDF and opens the share sheet with a short message.
Future<void> shareBill({
  required ClientBill bill,
  required String companyName,
  required Project project,
  required BillingProfile profile,
  Map<String, double> previousQty = const {},
  PdfBranding branding = const PdfBranding(),
}) async {
  final bytes = await buildBillPdf(
      bill: bill,
      companyName: companyName,
      project: project,
      profile: profile,
      previousQty: previousQty,
      branding: branding);
  final dir = await getTemporaryDirectory();
  final safe = bill.billNumber.replaceAll(RegExp(r'[^A-Za-z0-9\-]+'), '_');
  final file = File('${dir.path}/${bill.kind == 'ra' ? 'RA_bill' : 'Invoice'}_$safe.pdf');
  await file.writeAsBytes(bytes);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: 'application/pdf')],
    text: '${billKinds[bill.kind]} ${bill.billNumber} for ${project.name}: '
        '${rupees(bill.netPayable, paise: true)} payable. ${rupeesInWords(bill.netPayable)}.',
  ));
}
