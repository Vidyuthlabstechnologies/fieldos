/// The quotation PDF a lead receives: items, discount, GST, total in words,
/// validity and terms, with the company's logo and GSTIN like its bills.
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
import 'package:fieldos_mobile/features/crm/crm_rules.dart';
import 'package:fieldos_mobile/features/money/bill_pdf.dart' show BillingProfile, pdfSafe;
import 'package:fieldos_mobile/features/money/billing_calc.dart' show rupeesInWords;

const _ink = PdfColor.fromInt(0xFF1B2733);
const _muted = PdfColor.fromInt(0xFF5B6B80);
const _line = PdfColor.fromInt(0xFFDDE3EB);
const _paper = PdfColor.fromInt(0xFFF4F6F9);

String _money(double v) => pdfSafe(rupees(v, paise: true));

/// Terms most small contractors print, used when a quote has none.
const defaultQuoteTerms = '50% advance with the work order, balance as running bills.\n'
    'Rates hold for the validity shown. Work beyond these items is quoted separately.\n'
    'Water and power at site by the client.';

Future<Uint8List> buildQuotePdf({
  required CrmQuote quote,
  required CrmLead lead,
  required String companyName,
  BillingProfile profile = const BillingProfile(),
  PdfBranding branding = const PdfBranding(),
}) async {
  final lines = decodeQuoteLines(quote.linesJson);
  final totals = quoteTotals(lines, discount: quote.discount, gstRate: quote.gstRate, interState: quote.interState);
  final doc = pw.Document(title: 'Quotation ${quote.quoteNumber}', creator: 'FieldOS');

  pw.Widget t(String s, {double size = 9, bool bold = false, PdfColor color = _ink, pw.TextAlign? align}) => pw.Text(
        pdfSafe(s),
        textAlign: align,
        style: pw.TextStyle(fontSize: size, color: color, fontWeight: bold ? pw.FontWeight.bold : null),
      );

  pw.Widget cell(String s, {bool bold = false, bool right = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: t(s, bold: bold, align: right ? pw.TextAlign.right : null),
      );

  pw.Widget sumRow(String label, String value, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(children: [
          pw.Expanded(child: t(label, bold: bold, align: pw.TextAlign.right)),
          pw.SizedBox(width: 100, child: t(value, bold: bold, align: pw.TextAlign.right)),
        ]),
      );

  final half = fmtQty(quote.gstRate / 2);
  final terms = (quote.terms ?? '').trim().isEmpty ? defaultQuoteTerms : quote.terms!.trim();

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    footer: branding.showFooter
        ? (ctx) => pw.Align(alignment: pw.Alignment.centerRight, child: t('Made with FieldOS', size: 7, color: _muted))
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
          t('QUOTATION', size: 13, bold: true),
          t('No. ${quote.quoteNumber}'),
          t('Date ${fmtDate(quote.quoteDate)}'),
          if (quote.validUntil != null) t('Valid until ${fmtDate(quote.validUntil!)}'),
        ]),
      ]),
      pw.SizedBox(height: 14),
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _line)),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              t('To', color: _muted),
              t(lead.name, bold: true),
              if ((lead.phone ?? '').isNotEmpty) t(lead.phone!),
              if ((lead.email ?? '').isNotEmpty) t(lead.email!),
            ]),
          ),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              t('Work', color: _muted),
              t((lead.workType ?? '').isEmpty ? 'As per items below' : lead.workType!, bold: true),
              if ((lead.location ?? '').isNotEmpty) t(lead.location!),
            ]),
          ),
        ]),
      ),
      pw.SizedBox(height: 12),
      pw.Table(
        border: pw.TableBorder.all(color: _line, width: 0.5),
        columnWidths: const {0: pw.FixedColumnWidth(18), 1: pw.FlexColumnWidth(4)},
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _paper),
            children: [
              for (final (i, h) in ['#', 'Description', 'Unit', 'Qty', 'Rate', 'Amount'].indexed)
                cell(h, bold: true, right: i >= 3),
            ],
          ),
          for (final (i, l) in lines.indexed)
            pw.TableRow(children: [
              cell('${i + 1}'),
              cell(l.description),
              cell(l.unit),
              cell(fmtQty(l.qty), right: true),
              cell(fmtQty(l.rate), right: true),
              cell(_money(l.amount), right: true),
            ]),
        ],
      ),
      pw.SizedBox(height: 10),
      sumRow('Subtotal', _money(totals.subtotal)),
      if (totals.discount > 0) ...[
        sumRow('Less discount', '- ${_money(totals.discount)}'),
        sumRow('Taxable value', _money(totals.taxable)),
      ],
      if (quote.interState && quote.gstRate > 0)
        sumRow('IGST @ ${fmtQty(quote.gstRate)}%', _money(totals.igst))
      else if (quote.gstRate > 0) ...[
        sumRow('CGST @ $half%', _money(totals.cgst)),
        sumRow('SGST @ $half%', _money(totals.sgst)),
      ],
      sumRow('Total', _money(totals.total), bold: true),
      pw.SizedBox(height: 6),
      t(rupeesInWords(totals.total), bold: true),
      pw.SizedBox(height: 14),
      t('Terms', bold: true),
      for (final line in terms.split('\n').where((l) => l.trim().isNotEmpty)) t(line.trim(), color: _muted),
      pw.SizedBox(height: 36),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        t('Accepted by (client)', color: _muted),
        t('For $companyName', color: _muted),
      ]),
    ],
  ));
  return doc.save();
}

/// The text sent with the PDF on WhatsApp or email.
String quoteShareText(CrmQuote q, CrmLead lead, String companyName) {
  final valid = q.validUntil == null ? '' : ' Valid until ${fmtDate(q.validUntil!)}.';
  return 'Namaste ${lead.name}, please find our quotation ${q.quoteNumber} for '
      '${(lead.workType ?? '').isEmpty ? 'the work' : lead.workType}: ${rupees(q.total, paise: true)} with GST.$valid '
      '- $companyName';
}

Future<void> shareQuote({
  required CrmQuote quote,
  required CrmLead lead,
  required String companyName,
  BillingProfile profile = const BillingProfile(),
  PdfBranding branding = const PdfBranding(),
}) async {
  final bytes =
      await buildQuotePdf(quote: quote, lead: lead, companyName: companyName, profile: profile, branding: branding);
  final dir = await getTemporaryDirectory();
  final safe = quote.quoteNumber.replaceAll(RegExp(r'[^A-Za-z0-9\-]+'), '_');
  final file = File('${dir.path}/Quotation_$safe.pdf');
  await file.writeAsBytes(bytes);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: 'application/pdf')],
    text: quoteShareText(quote, lead, companyName),
  ));
}
