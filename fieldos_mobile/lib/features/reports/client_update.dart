/// The client's progress update: a branded PDF for the person paying for
/// the building, with the stage, how far along it is, what was finished,
/// what comes next, the best photos and, when the owner chooses, what has
/// been billed, paid and is still due. Every client who receives one sees
/// the contractor as organised (and sees FieldOS on the footer).
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
import 'package:fieldos_mobile/features/money/bill_pdf.dart' show pdfSafe;
import 'package:fieldos_mobile/features/project/project_status.dart';
import 'package:fieldos_mobile/features/project/task_plan.dart';
import 'package:fieldos_mobile/features/reports/dpr_report.dart';
import 'package:fieldos_mobile/features/reports/period_report.dart';

const _navy = PdfColor.fromInt(0xFF112A4A);
const _amber = PdfColor.fromInt(0xFFF5A524);
const _muted = PdfColor.fromInt(0xFF5B6B80);
const _line = PdfColor.fromInt(0xFFDDE3EB);
const _paper = PdfColor.fromInt(0xFFF4F6F9);
const _ok = PdfColor.fromInt(0xFF1E8E5A);

const maxUpdatePhotos = 8;

/// Billed to the client so far, received, and what is still due.
class ClientDues {
  const ClientDues({required this.billed, required this.received});
  final double billed;
  final double received;
  double get due => billed - received > 0 ? billed - received : 0;
  bool get isEmpty => billed <= 0 && received <= 0;
}

Future<ClientDues> clientDues(AppDatabase db, String projectId) async {
  final bills = await db.billDao.forProject(projectId);
  final pays = await db.paymentDao.forProject(projectId);
  return ClientDues(
    billed: bills.fold(0, (s, b) => s + b.netPayable),
    received: pays.fold(0, (s, p) => s + p.amount),
  );
}

Future<Uint8List> buildClientUpdatePdf({
  required String companyName,
  required PeriodReport report,
  List<String> photoPaths = const [],
  List<String> comingUp = const [],
  ClientDues? dues,
  TextPicturePainter paintText = paintWithPhoneFonts,
  PdfBranding branding = const PdfBranding(),
}) async {
  final project = report.project;
  final range = periodRange(report.period);
  if (companyName.trim().isEmpty) companyName = project.name;
  final kit = PdfTextKit(paintText);
  final client = project.clientName?.trim() ?? '';
  await kit.prepare(companyName, size: 16, bold: true, color: PdfColors.white, width: 330);
  await kit.prepare(companyName, size: 8, color: _muted, width: 300);
  await kit.prepare(project.name, size: 11, bold: true, width: 240);
  await kit.prepare(client, size: 11, bold: true, width: 240);
  for (final t in [...report.tasksFinished, ...comingUp]) {
    await kit.prepare(t, size: 10, width: 480);
  }
  for (final d in report.days) {
    await kit.prepare(d.text, size: 10, width: 420);
  }

  final images = <pw.MemoryImage>[];
  for (final path in photoPaths.take(maxUpdatePhotos)) {
    try {
      final f = File(path);
      if (f.existsSync()) images.add(pw.MemoryImage(f.readAsBytesSync()));
    } catch (_) {}
  }

  pw.Widget infoCell(String label, String value, {double width = 124}) => pw.Container(
        width: width,
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: pw.BoxDecoration(color: _paper, borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(label.toUpperCase(), style: const pw.TextStyle(fontSize: 7, color: _muted, letterSpacing: 0.6)),
          pw.SizedBox(height: 2),
          kit.one(value, bold: true, width: width - 20),
        ]),
      );

  pw.Widget heading(String title) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
        child: pw.Row(children: [
          pw.Container(width: 3, height: 13, color: _amber),
          pw.SizedBox(width: 6),
          pw.Text(title, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _navy)),
        ]),
      );

  pw.Widget bullet(String t, {PdfColor dot = _ok}) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Container(
              margin: const pw.EdgeInsets.only(top: 4, right: 8),
              width: 5,
              height: 5,
              decoration: pw.BoxDecoration(color: dot, shape: pw.BoxShape.circle)),
          pw.Expanded(child: kit.one(t, size: 10, width: 480)),
        ]),
      );

  final pct = report.progressNow.clamp(0, 100);
  final doc = pw.Document(title: 'Progress update, ${project.name}, $range', creator: 'FieldOS');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 28),
    header: (ctx) => ctx.pageNumber == 1
        ? pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 14),
            padding: const pw.EdgeInsets.fromLTRB(14, 12, 16, 12),
            decoration: pw.BoxDecoration(color: brandInk(branding, _navy), borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Row(children: [
              if (branding.logo != null)
                pw.Container(
                  padding: const pw.EdgeInsets.all(3),
                  decoration: pw.BoxDecoration(color: PdfColors.white, borderRadius: pw.BorderRadius.circular(4)),
                  child: pw.Image(pw.MemoryImage(branding.logo!), height: 34, fit: pw.BoxFit.contain),
                )
              else
                pw.CustomPaint(size: const PdfPoint(34, 34), painter: (c, s) => paintFieldOsHat(c, s.x, line: PdfColors.white)),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  kit.one(companyName, size: 16, bold: true, color: PdfColors.white, width: 330),
                  pw.SizedBox(height: 2),
                  pw.Text('Progress update for the client', style: const pw.TextStyle(fontSize: 10, color: _amber)),
                ]),
              ),
              pw.Text(range, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
            ]),
          )
        : pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 10),
            padding: const pw.EdgeInsets.only(bottom: 4),
            decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line))),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              kit.one(companyName, size: 8, color: _muted, width: 300),
              pw.Text('Progress update, $range', style: const pw.TextStyle(fontSize: 8, color: _muted)),
            ]),
          ),
    footer: (ctx) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 8),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        if (branding.hasFooter)
          pw.Row(children: [
            if (branding.showFooter) ...[
              pw.CustomPaint(size: const PdfPoint(11, 11), painter: (c, s) => paintFieldOsHat(c, s.x, line: _navy)),
              pw.SizedBox(width: 4),
            ],
            pw.Text(pdfSafe(branding.footerLine), style: const pw.TextStyle(fontSize: 8, color: _muted)),
          ])
        else
          pw.SizedBox(),
        pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: _muted)),
      ]),
    ),
    build: (_) => [
      pw.Wrap(spacing: 8, runSpacing: 8, children: [
        infoCell('Project', project.name, width: 261),
        if (client.isNotEmpty) infoCell('Client', client, width: 261),
        infoCell('Stage', projectStatusLabel(project.status)),
        infoCell('Work done', '$pct%'),
        infoCell('Days reported', '${report.reportsFiled} of ${report.workingDays}'),
        infoCell('Worker-days', '${report.labourDays}'),
      ]),
      pw.SizedBox(height: 12),
      pw.Text('Overall progress', style: const pw.TextStyle(fontSize: 9, color: _muted)),
      pw.SizedBox(height: 4),
      pw.Stack(children: [
        pw.Container(height: 10, decoration: pw.BoxDecoration(color: _line, borderRadius: pw.BorderRadius.circular(5))),
        pw.Container(
          height: 10,
          width: 531 * pct / 100,
          decoration: pw.BoxDecoration(color: _amber, borderRadius: pw.BorderRadius.circular(5)),
        ),
      ]),
      if (report.tasksFinished.isNotEmpty) ...[
        heading('Finished in this period'),
        for (final t in report.tasksFinished) bullet(t),
      ],
      if (report.days.isNotEmpty) ...[
        heading('Day by day'),
        for (final d in report.days)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.SizedBox(
                width: 80,
                child: pw.Text('${fmtDay(d.day)} ${fmtDate(d.day, short: true)}',
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _muted)),
              ),
              pw.Expanded(child: kit.one(d.text, size: 10, width: 420)),
            ]),
          ),
      ],
      if (comingUp.isNotEmpty) ...[
        heading('Coming up next'),
        for (final t in comingUp) bullet(t, dot: _amber),
      ],
      if (images.isNotEmpty) ...[
        heading('Photos'),
        pw.Wrap(spacing: 8, runSpacing: 8, children: [
          for (final img in images)
            pw.ClipRRect(
              horizontalRadius: 4,
              verticalRadius: 4,
              child: pw.SizedBox(width: 260, height: 195, child: pw.Image(img, fit: pw.BoxFit.cover)),
            ),
        ]),
      ],
      if (dues != null && !dues.isEmpty) ...[
        heading('Payments'),
        pw.Wrap(spacing: 8, runSpacing: 8, children: [
          infoCell('Billed so far', rupees(dues.billed), width: 171),
          infoCell('Received', rupees(dues.received), width: 171),
          infoCell('Balance due', rupees(dues.due), width: 171),
        ]),
      ],
    ],
  ));
  return doc.save();
}

/// Builds the update for [report] from the local database and opens the
/// share sheet with it.
Future<void> shareClientUpdate({
  required AppDatabase db,
  required String companyName,
  required PeriodReport report,
  required bool includeDues,
  DateTime? now,
}) async {
  final project = report.project;
  final dprs = (await db.dprDao.forProject(project.id)).where((d) => report.period.contains(d.entryDate)).toList()
    ..sort((a, b) => b.entryDate.compareTo(a.entryDate));
  final photos = <String>[];
  for (final d in dprs) {
    photos.addAll((await db.dprDao.photosFor(d.id)).map((p) => p.photoPath));
    if (photos.length >= maxUpdatePhotos) break;
  }
  final tasks = await db.taskDao.forProject(project.id);
  final next = [for (final t in lookAhead(tasks, now ?? DateTime.now(), 14).take(6)) t.title];
  final bytes = await buildClientUpdatePdf(
    companyName: companyName,
    report: report,
    photoPaths: photos,
    comingUp: next,
    dues: includeDues ? await clientDues(db, project.id) : null,
    branding: await loadBranding(db, project.companyId),
  );
  final dir = await getTemporaryDirectory();
  final safe = project.name.replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\-]+', unicode: true), '_');
  final file = File('${dir.path}/Progress_${safe}_${report.period.start.year}-${report.period.start.month.toString().padLeft(2, '0')}-${report.period.start.day.toString().padLeft(2, '0')}.pdf');
  await file.writeAsBytes(bytes);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: 'application/pdf')],
    text: '${project.name}: progress update, ${periodRange(report.period)}. ${report.progressNow}% done overall.',
  ));
}
