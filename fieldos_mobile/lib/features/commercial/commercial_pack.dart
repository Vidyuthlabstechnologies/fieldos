/// What accounts and the commercial manager get: the trace of one claim
/// from the agreement to the payment, and a work order statement (PDF and
/// CSV) with every certificate, the variations and the amount payable.
/// English, like the bill, voucher and weekly close PDFs: it goes to the
/// office.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/commercial/commercial_rules.dart';
import 'package:fieldos_mobile/features/company/branding.dart';
import 'package:fieldos_mobile/features/money/bill_pdf.dart' show pdfSafe;

enum TraceKind { agreed, claimed, certified, variationRaised, variationDecided }

/// One step from the agreement to the payment.
class TraceStep {
  TraceStep({
    required this.kind,
    required this.at,
    required this.who,
    required this.english,
    this.photos = 0,
    this.photoParentId,
    this.note,
  });
  final TraceKind kind;
  final DateTime at;

  /// A user id (or null for the agreement itself).
  final String? who;

  /// The step in plain English (the screen translates its own labels).
  final String english;
  final int photos;
  final String? photoParentId;
  final String? note;
}

String _q(double v, String? unit) => '${fmtQty(v)} ${unit ?? ''}'.trim();
String _money(num v) => pdfSafe(rupees(v, paise: true));

/// The trace of one claim, oldest first: the order as agreed, the claim
/// and its photos, each certification, the variation it raised and the
/// decision on it.
List<TraceStep> traceClaim(CommercialData d, WorkClaim claim) {
  final order = d.orderById(claim.workOrderId)!;
  final unit = order.unit;
  final steps = <TraceStep>[
    TraceStep(
      kind: TraceKind.agreed,
      at: order.createdAt,
      who: null,
      english: 'Work order agreed: ${_q(order.contractQty ?? 0, unit)} at ${_money(workOrderRate(order) ?? 0)} '
          '= ${_money(order.agreedAmount ?? 0)}',
    ),
    TraceStep(
      kind: TraceKind.claimed,
      at: claim.createdAt,
      who: claim.submittedBy,
      english: 'Claimed ${_q(claim.qty, unit)}${claim.location == null ? '' : ' at ${claim.location}'}',
      photos: d.photosOf(claim.id).length,
      photoParentId: claim.id,
      note: claim.note,
    ),
  ];
  final certs = d.certifications.where((c) => c.claimId == claim.id).toList();
  final variation = d.claim(claim).variation;
  for (final c in certs) {
    final parts = [
      if (c.acceptedQty > 0) 'accepted ${_q(c.acceptedQty, unit)}',
      if (c.rejectedQty > 0) 'rejected ${_q(c.rejectedQty, unit)}',
    ];
    final v = d.variationById(c.variationId);
    // The certification that sent the rest of the claim to the register.
    final raised = v != null && v.sourceClaimId == claim.id && certs.firstWhere((x) => x.variationId == v.id) == c;
    if (parts.isNotEmpty) {
      steps.add(TraceStep(
        kind: TraceKind.certified,
        at: c.createdAt,
        who: c.certifiedBy,
        english: '${d.certificateNo(c)}: ${parts.join(', ')}'
            '${c.acceptedQty > 0 ? ' (${_money(c.acceptedQty * (workOrderRate(order) ?? 0))})' : ''}'
            '${v != null && !raised ? ' against ${d.variationNo(v)}' : ''}',
        photos: d.photosOf(c.id).length,
        photoParentId: c.id,
        note: c.note,
      ));
    }
    if (raised) {
      steps.add(TraceStep(
        kind: TraceKind.variationRaised,
        at: v.createdAt,
        who: v.raisedBy,
        english: '${d.variationNo(v)} raised for ${_q(v.qty ?? 0, unit)} beyond the order, '
            'estimated ${_money(v.estimatedCost)}',
        photos: d.photosOf(v.id).length,
        photoParentId: v.id,
        note: v.note,
      ));
      final dec = d.decisionByVariation[v.id];
      if (dec != null) {
        steps.add(TraceStep(
          kind: TraceKind.variationDecided,
          at: dec.createdAt,
          who: dec.decidedBy,
          english: dec.decision == 'approved'
              ? '${d.variationNo(v)} approved: ${_q(dec.approvedQty ?? 0, unit)}, ${_money(dec.approvedCost ?? 0)}'
              : '${d.variationNo(v)} rejected',
          note: dec.note,
        ));
      }
    }
  }
  if (variation != null && !steps.any((s) => s.kind == TraceKind.variationRaised)) {
    // A variation raised outside a certification (from the register).
    steps.add(TraceStep(
      kind: TraceKind.variationRaised,
      at: variation.createdAt,
      who: variation.raisedBy,
      english: '${d.variationNo(variation)} raised: ${variation.title}',
      photos: d.photosOf(variation.id).length,
      photoParentId: variation.id,
      note: variation.note,
    ));
  }
  // In the order things happened, without sorting by clock: phones keep
  // times to the second, and a certification, the variation it raised and
  // a decision can share one.
  return steps;
}

String _csv(Object? v) {
  final s = '${v ?? ''}';
  return s.contains(RegExp(r'[,"\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
}

String _iso(DateTime d) => d.toLocal().toIso8601String().substring(0, 16).replaceFirst('T', ' ');

/// One work order's statement as CSV: certificates with amounts, then the
/// variations, then the totals.
String workOrderStatementCsv(CommercialData d, WorkOrder order, {Map<String, String> names = const {}}) {
  final pos = d.position(order);
  final b = StringBuffer()
    ..writeln('Work order,${_csv(order.description)}')
    ..writeln('Subcontractor,${_csv(d.subcontractorNames[order.subcontractorId] ?? '')}')
    ..writeln('Unit,${_csv(order.unit)}')
    ..writeln('Rate,${pos.rate.toStringAsFixed(2)}')
    ..writeln('Agreed quantity (baseline),${fmtQty(pos.baselineQty)}')
    ..writeln('Approved variations,${fmtQty(pos.approvedVariationQty)}')
    ..writeln('Current quantity,${fmtQty(pos.currentQty)}')
    ..writeln()
    ..writeln('Certificate,Date,Claim date,Claimed,Accepted,Rejected,Amount,Variation,Certified by,Note');
  for (final c in d.certifications.where((c) => c.workOrderId == order.id)) {
    final claim = d.claimById(c.claimId);
    final v = d.variationById(c.variationId);
    b.writeln([
      d.certificateNo(c),
      _iso(c.createdAt),
      claim == null ? '' : _iso(claim.createdAt),
      claim == null ? '' : fmtQty(claim.qty),
      fmtQty(c.acceptedQty),
      fmtQty(c.rejectedQty),
      (c.acceptedQty * pos.rate).toStringAsFixed(2),
      v == null ? '' : d.variationNo(v),
      names[c.certifiedBy] ?? '',
      c.note ?? '',
    ].map(_csv).join(','));
  }
  b
    ..writeln()
    ..writeln('Variation,Raised,Title,Quantity,Estimated,Decision,Approved quantity,Approved amount,Note');
  for (final v in d.variations.where((v) => v.workOrderId == order.id)) {
    final dec = d.decisionByVariation[v.id];
    b.writeln([
      d.variationNo(v),
      _iso(v.createdAt),
      v.title,
      v.qty == null ? '' : fmtQty(v.qty!),
      v.estimatedCost.toStringAsFixed(2),
      dec?.decision ?? 'pending',
      dec?.approvedQty == null ? '' : fmtQty(dec!.approvedQty!),
      dec?.approvedCost?.toStringAsFixed(2) ?? '',
      dec?.note ?? '',
    ].map(_csv).join(','));
  }
  b
    ..writeln()
    ..writeln('Certified quantity,${fmtQty(pos.certifiedQty)}')
    ..writeln('Certified amount,${pos.certifiedValue.toStringAsFixed(2)}')
    ..writeln('Remaining quantity,${fmtQty(pos.remainingQty)}')
    ..writeln('Open commitment,${pos.openCommitment.toStringAsFixed(2)}');
  return b.toString();
}

/// The statement as a PDF, with the claim photos at the end.
Future<Uint8List> buildWorkOrderStatement({
  required CommercialData data,
  required WorkOrder order,
  required String companyName,
  required String siteName,
  Map<String, String> names = const {},
  PdfBranding branding = const PdfBranding(),
  int photoLimit = 24,
}) async {
  const ink = PdfColor.fromInt(0xFF1B2733);
  const muted = PdfColor.fromInt(0xFF5B6B80);
  const line = PdfColor.fromInt(0xFFDDE3EB);
  const paper = PdfColor.fromInt(0xFFF4F6F9);
  final d = data;
  final pos = d.position(order);
  final unit = order.unit;
  final doc = pw.Document(title: 'Work order statement ${order.description}', creator: 'FieldOS');
  pw.Widget t(String s, {double size = 9, bool bold = false, PdfColor color = ink}) => pw.Text(pdfSafe(s),
      style: pw.TextStyle(fontSize: size, color: color, fontWeight: bold ? pw.FontWeight.bold : null));
  pw.Widget table(List<String> head, List<List<String>> rows) => rows.isEmpty
      ? t('None.', color: muted)
      : pw.TableHelper.fromTextArray(
          headers: [for (final h in head) pdfSafe(h)],
          data: [for (final r in rows) [for (final c in r) pdfSafe(c)]],
          headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: ink),
          cellStyle: const pw.TextStyle(fontSize: 8, color: ink),
          headerDecoration: const pw.BoxDecoration(color: paper),
          border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: line, width: 0.5)),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        );
  pw.Widget heading(String s) =>
      pw.Padding(padding: const pw.EdgeInsets.only(top: 14, bottom: 6), child: t(s, size: 12, bold: true));
  String who(String? id) => id == null ? '' : names[id] ?? 'Team member';

  final claims = d.claims.where((c) => c.workOrderId == order.id).toList();
  final images = <(pw.MemoryImage, String)>[];
  for (final c in claims) {
    for (final a in [...d.photosOf(c.id), for (final x in d.certifications.where((x) => x.claimId == c.id)) ...d.photosOf(x.id)]) {
      if (images.length >= photoLimit) break;
      final f = File(a.filePath);
      final lower = a.filePath.toLowerCase();
      if (!f.existsSync() || !(lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png'))) continue;
      try {
        images.add((pw.MemoryImage(f.readAsBytesSync()),
            '${a.parentKind == 'claim' ? 'Claim' : 'Certification'} of ${fmtDate(c.createdAt)}: ${_q(c.qty, unit)}'));
      } catch (_) {}
    }
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    footer: (ctx) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      t(branding.showFooter ? 'Made with FieldOS' : '', size: 7, color: muted),
      t('Page ${ctx.pageNumber} of ${ctx.pagesCount}', size: 7, color: muted),
    ]),
    build: (ctx) => [
      t(companyName, size: 10, color: muted),
      t('Work order statement', size: 16, bold: true),
      t('$siteName - ${order.description}', size: 10),
      t('Subcontractor: ${d.subcontractorNames[order.subcontractorId] ?? ''}', size: 10),
      heading('What was agreed'),
      table(['', 'Quantity', 'Amount'], [
        ['Agreed (baseline)', _q(pos.baselineQty, unit), _money(pos.baselineValue)],
        ['Approved variations', _q(pos.approvedVariationQty, unit), _money(pos.approvedVariationValue)],
        ['Current order', _q(pos.currentQty, unit), _money(pos.currentValue)],
        ['Rate', '', _money(pos.rate)],
      ]),
      heading('What was accepted'),
      table(['No.', 'Date', 'Claimed', 'Accepted', 'Rejected', 'Amount', 'By', 'Note'], [
        for (final c in d.certifications.where((c) => c.workOrderId == order.id))
          [
            d.certificateNo(c),
            fmtDate(c.createdAt),
            _q(d.claimById(c.claimId)?.qty ?? 0, unit),
            _q(c.acceptedQty, unit),
            _q(c.rejectedQty, unit),
            _money(c.acceptedQty * pos.rate),
            who(c.certifiedBy),
            [if (d.variationById(c.variationId) != null) d.variationNo(d.variationById(c.variationId)!), c.note ?? '']
                .where((s) => s.isNotEmpty)
                .join(' - '),
          ],
      ]),
      heading('Variations'),
      table(['No.', 'Title', 'Quantity', 'Estimated', 'Decision', 'Note'], [
        for (final v in d.variations.where((v) => v.workOrderId == order.id))
          [
            d.variationNo(v),
            v.title,
            _q(v.qty ?? 0, unit),
            _money(v.estimatedCost),
            switch (d.decisionByVariation[v.id]?.decision) {
              'approved' => 'Approved ${_money(d.decisionByVariation[v.id]!.approvedCost ?? 0)}',
              'rejected' => 'Rejected',
              _ => 'Pending',
            },
            d.decisionByVariation[v.id]?.note ?? v.note ?? '',
          ],
      ]),
      heading('Position'),
      table(['', 'Quantity', 'Amount'], [
        ['Certified to date', _q(pos.certifiedQty, unit), _money(pos.certifiedValue)],
        ['Still on the order', _q(pos.remainingQty, unit), _money(pos.openCommitment)],
      ]),
      for (final c in claims) ...[
        heading('Trace: claim of ${fmtDate(c.createdAt)}'),
        for (final s in traceClaim(d, c))
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: t('${fmtDateTime(s.at)}  ${s.english}${s.who == null ? '' : ' - ${who(s.who)}'}'
                '${s.photos > 0 ? ' [${s.photos} photo${s.photos == 1 ? '' : 's'}]' : ''}'
                '${(s.note ?? '').isEmpty ? '' : ' "${s.note}"'}'),
          ),
      ],
      if (images.isNotEmpty) ...[
        heading('Site evidence'),
        pw.Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (img, caption) in images)
            pw.SizedBox(
              width: 165,
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.SizedBox(height: 120, child: pw.Image(img, fit: pw.BoxFit.cover)),
                t(caption, size: 7, color: muted),
              ]),
            ),
        ]),
      ],
    ],
  ));
  return doc.save();
}
