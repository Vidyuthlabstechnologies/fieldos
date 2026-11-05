/// A daily progress report as a one-file PDF, shared through Android's
/// share sheet -- straight into the client's or the office's WhatsApp
/// group, which is where site reports actually travel today. Works fully
/// offline (the PDF is built on the phone).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'package:fieldos_mobile/data/app_database.dart';

String _date(DateTime d) {
  final l = d.toLocal();
  return '${l.day.toString().padLeft(2, '0')}-${l.month.toString().padLeft(2, '0')}-${l.year}';
}

/// True when [text] has characters outside Latin-1, which the PDF's built-in
/// font cannot draw (Telugu, Hindi and other Indic scripts). The pdf
/// package also has no Indic text shaping, so bundling a Noto font would
/// still render conjuncts wrongly -- instead the report says where the
/// original text is, and the share message carries it verbatim, where
/// WhatsApp renders it properly.
bool needsLocalScript(String text) => text.runes.any((r) => r > 0xFF && r != 0x2014 && r != 0x2022 && r != 0x00B7);

/// Builds the PDF bytes. Pure apart from reading the photo files, so it is
/// testable in the Dart VM. Photos that are missing or unreadable are
/// skipped rather than failing the whole report.
Future<Uint8List> buildDprPdf({
  required String companyName,
  required Project project,
  required DprEntry dpr,
  List<String> photoPaths = const [],
  List<Issue> issues = const [],
}) async {
  final doc = pw.Document(title: 'DPR ${project.name} ${_date(dpr.entryDate)}', author: companyName);

  final images = <pw.MemoryImage>[];
  for (final path in photoPaths) {
    try {
      final f = File(path);
      if (f.existsSync()) images.add(pw.MemoryImage(f.readAsBytesSync()));
    } catch (_) {}
  }

  pw.Widget field(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 90, child: pw.Text(label, style: const pw.TextStyle(color: PdfColors.grey700))),
          pw.Expanded(child: pw.Text(value)),
        ]),
      );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    header: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(companyName, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
      pw.Text('Daily Progress Report', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.Divider(),
    ]),
    footer: (ctx) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('Generated with FieldOS - page ${ctx.pageNumber} of ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
    ),
    build: (_) => [
      field('Project', project.name),
      if (project.clientName != null && project.clientName!.isNotEmpty) field('Client', project.clientName!),
      field('Date', _date(dpr.entryDate)),
      field('Manpower', '${dpr.manpowerCount} workers'),
      if (dpr.weather != null && dpr.weather!.isNotEmpty) field('Weather', dpr.weather!),
      pw.SizedBox(height: 12),
      pw.Text('Work done', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      if (needsLocalScript(dpr.workSummary))
        pw.Text('Written in a local language: the full text is in the message this report was shared with.',
            style: const pw.TextStyle(color: PdfColors.grey700))
      else
        pw.Text(dpr.workSummary),
      if (issues.isNotEmpty) ...[
        pw.SizedBox(height: 16),
        pw.Text('Issues raised', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.TableHelper.fromTextArray(
          headers: ['Severity', 'Issue', 'Status'],
          data: [for (final i in issues) [i.severity, i.description, i.status]],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellAlignment: pw.Alignment.centerLeft,
          columnWidths: {0: const pw.FixedColumnWidth(60), 2: const pw.FixedColumnWidth(60)},
        ),
      ],
      if (images.isNotEmpty) ...[
        pw.SizedBox(height: 16),
        pw.Text('Photos', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Wrap(spacing: 8, runSpacing: 8, children: [
          for (final img in images) pw.SizedBox(width: 250, height: 190, child: pw.Image(img, fit: pw.BoxFit.cover)),
        ]),
      ],
    ],
  ));
  return doc.save();
}

/// Builds the PDF for [dpr] from the local database and opens the share
/// sheet with it.
Future<void> shareDprReport({
  required AppDatabase db,
  required String companyName,
  required Project project,
  required DprEntry dpr,
}) async {
  final photos = await db.dprDao.photosFor(dpr.id);
  final issues = (await db.issueDao.forProject(project.id)).where((i) => i.dprEntryId == dpr.id).toList();
  final bytes = await buildDprPdf(
    companyName: companyName,
    project: project,
    dpr: dpr,
    photoPaths: [for (final p in photos) p.photoPath],
    issues: issues,
  );
  final dir = await getTemporaryDirectory();
  final safeProject = project.name.replaceAll(RegExp(r'[^\w\-]+'), '_');
  final file = File('${dir.path}/DPR_${safeProject}_${_date(dpr.entryDate)}.pdf');
  await file.writeAsBytes(bytes);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: 'application/pdf')],
    text: 'DPR · ${project.name} · ${_date(dpr.entryDate)}\n'
        '${dpr.manpowerCount} workers${dpr.weather == null ? '' : ' · ${dpr.weather}'}\n\n${dpr.workSummary}',
  ));
}
