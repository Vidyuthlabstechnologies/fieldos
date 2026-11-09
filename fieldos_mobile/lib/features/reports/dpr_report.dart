/// A daily progress report as a one-file PDF, shared through the phone's
/// share sheet -- straight into the client's or the office's WhatsApp
/// group, which is where site reports actually travel today. Built on the
/// phone, so it works offline.
///
/// The PDF's built-in font only has Latin letters, and the pdf package
/// cannot shape Telugu, Hindi or other Indian scripts. So any text in those
/// scripts (a company name, a summary, an issue) is drawn by the phone's own
/// text engine, which shapes them correctly with the phone's fonts, and
/// placed in the PDF as a picture.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'package:fieldos_mobile/core/brand.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/company/branding.dart';

const _navy = PdfColor.fromInt(0xFF112A4A);
const _amber = PdfColor.fromInt(0xFFF5A524);
const _amberDark = PdfColor.fromInt(0xFFD6860E);
const _ink = PdfColor.fromInt(0xFF13233A);
const _muted = PdfColor.fromInt(0xFF5B6B80);
const _line = PdfColor.fromInt(0xFFDDE3EB);
const _paper = PdfColor.fromInt(0xFFF4F6F9);

/// Most photos put in one report; the rest stay in the app.
const maxReportPhotos = 12;

/// Punctuation people type that the built-in font lacks, swapped for what
/// it has, so plain English stays real (searchable) text.
String _latin(String s) => s
    .replaceAll(RegExp('[–—−]'), '-')
    .replaceAll(RegExp('[‘’‚′]'), "'")
    .replaceAll(RegExp('[“”„″]'), '"')
    .replaceAll('•', '-')
    .replaceAll('…', '...')
    .replaceAll('₹', 'Rs. ')
    .replaceAll(' ', ' ');

/// True when [text] has characters the PDF's built-in font cannot draw
/// (Telugu, Hindi and other Indian scripts, emoji), even after swapping
/// common punctuation.
bool needsLocalScript(String text) => _latin(text).runes.any((r) => r > 0xFF);

/// Text drawn as a picture: [png] at 3x, [width] and [height] in PDF points.
class TextPicture {
  const TextPicture(this.png, this.width, this.height);
  final Uint8List png;
  final double width;
  final double height;
}

typedef TextPicturePainter = Future<TextPicture?> Function(
  String text, {
  required double fontSize,
  required bool bold,
  required int argb,
  required double maxWidth,
});

/// Draws [text] with the phone's text engine and fonts (Inter, then the
/// phone's own fonts for other scripts).
Future<TextPicture?> paintWithPhoneFonts(
  String text, {
  required double fontSize,
  required bool bold,
  required int argb,
  required double maxWidth,
}) async {
  const scale = 3.0;
  ui.Paragraph layout(double width) {
    final b = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontFamily: Brand.fontFamily,
      fontSize: fontSize * scale,
      fontWeight: bold ? ui.FontWeight.w700 : ui.FontWeight.w400,
      height: 1.35,
    ))
      // Named again on the run itself: a pushed style does not inherit the
      // paragraph's family.
      ..pushStyle(ui.TextStyle(
        color: ui.Color(argb),
        fontFamily: Brand.fontFamily,
        fontSize: fontSize * scale,
        fontWeight: bold ? ui.FontWeight.w700 : ui.FontWeight.w400,
      ))
      ..addText(text);
    return b.build()..layout(ui.ParagraphConstraints(width: width));
  }

  var p = layout(maxWidth * scale);
  // Lay out again at the text's own width so right-to-left lines are not
  // cut off when the picture is trimmed.
  final own = p.maxIntrinsicWidth.ceilToDouble();
  if (own < maxWidth * scale) p = layout(own);
  final w = p.width.ceil(), h = p.height.ceil();
  if (w <= 0 || h <= 0) return null;
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawParagraph(p, ui.Offset.zero);
  final image = await recorder.endRecording().toImage(w, h);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data == null ? null : TextPicture(data.buffer.asUint8List(), w / scale, h / scale);
  } finally {
    image.dispose();
  }
}

/// Splits long local-script text into pieces short enough that no picture
/// is taller than a page.
List<String> _pieces(String text) {
  final out = <String>[];
  for (final para in text.split(RegExp(r'\n\s*\n|\n'))) {
    var rest = para.trim();
    while (rest.length > 500) {
      var cut = rest.lastIndexOf(RegExp(r'[.।!?]\s'), 500);
      if (cut < 200) cut = rest.lastIndexOf(' ', 500);
      if (cut < 200) cut = 500;
      out.add(rest.substring(0, cut + 1).trim());
      rest = rest.substring(cut + 1).trim();
    }
    if (rest.isNotEmpty) out.add(rest);
  }
  return out;
}

String _sentence(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1).replaceAll('_', ' ')}';

/// Builds the PDF bytes. Photos that are missing or unreadable are skipped
/// rather than failing the whole report. [paintText] draws local-script
/// text; tests pass a stand-in.
Future<Uint8List> buildDprPdf({
  required String companyName,
  required Project project,
  required DprEntry dpr,
  List<String> photoPaths = const [],
  List<Issue> issues = const [],
  TextPicturePainter paintText = paintWithPhoneFonts,
  PdfBranding branding = const PdfBranding(),
}) async {
  final date = fmtDate(dpr.entryDate);
  // No company name (should not happen): the project heads the report.
  if (companyName.trim().isEmpty) companyName = project.name;
  final doc = pw.Document(
    title: 'Daily progress report, ${_latin(project.name)}, $date',
    author: needsLocalScript(companyName) ? null : _latin(companyName),
    creator: 'FieldOS',
  );

  // Pictures for local-script text, made before the (synchronous) layout.
  final pictures = <String, TextPicture?>{};
  String key(String s, double size, bool bold, PdfColor c, double w) => '$size|$bold|${c.toInt()}|$w|$s';
  Future<void> prepare(String? s, {double size = 11, bool bold = false, PdfColor color = _ink, double width = 500}) async {
    if (s == null || s.trim().isEmpty || !needsLocalScript(s)) return;
    for (final piece in _pieces(s).where(needsLocalScript)) {
      final k = key(piece, size, bold, color, width);
      if (pictures.containsKey(k)) continue;
      try {
        pictures[k] = await paintText(piece, fontSize: size, bold: bold, argb: color.toInt(), maxWidth: width);
      } catch (_) {
        pictures[k] = null;
      }
    }
  }

  /// [s] as real text when the built-in font can draw it, otherwise as
  /// pictures (one per paragraph), all prepared above.
  List<pw.Widget> text(String s, {double size = 11, bool bold = false, PdfColor color = _ink, double width = 500}) {
    pw.Widget plain(String t) => pw.Text(_latin(t),
        style: pw.TextStyle(fontSize: size, color: color, fontWeight: bold ? pw.FontWeight.bold : null, lineSpacing: 2));
    if (!needsLocalScript(s)) return [plain(s)];
    return [
      for (final piece in _pieces(s))
        if (!needsLocalScript(piece))
          pw.Padding(padding: const pw.EdgeInsets.only(bottom: 3), child: plain(piece))
        else if (pictures[key(piece, size, bold, color, width)] case final p?)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Image(pw.MemoryImage(p.png), width: p.width, height: p.height),
          )
        else
          pw.Text('(written in a local language: see the message this report came with)',
              style: pw.TextStyle(fontSize: size - 1, color: _muted)),
    ];
  }

  pw.Widget one(String s, {double size = 11, bool bold = false, PdfColor color = _ink, double width = 500}) {
    final parts = text(s, size: size, bold: bold, color: color, width: width);
    return parts.length == 1
        ? parts.single
        : pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: parts);
  }

  final client = project.clientName?.trim() ?? '';
  final weather = dpr.weather?.trim() ?? '';
  await prepare(companyName, size: 16, bold: true, color: PdfColors.white, width: 330);
  await prepare(companyName, size: 8, color: _muted, width: 300);
  await prepare(project.name, size: 11, bold: true, width: 240);
  await prepare(client, size: 11, bold: true, width: 240);
  await prepare(weather, size: 11, bold: true, width: 240);
  await prepare(dpr.workSummary);
  for (final i in issues) {
    await prepare(i.description, size: 10, width: 330);
  }

  final images = <pw.MemoryImage>[];
  for (final path in photoPaths.take(maxReportPhotos)) {
    try {
      final f = File(path);
      if (f.existsSync()) images.add(pw.MemoryImage(f.readAsBytesSync()));
    } catch (_) {}
  }
  final morePhotos = photoPaths.length - maxReportPhotos;

  // Two to a row across the page's 531 points.
  pw.Widget infoCell(String label, String value) => pw.Container(
        width: 261,
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: pw.BoxDecoration(color: _paper, borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(label.toUpperCase(), style: const pw.TextStyle(fontSize: 7, color: _muted, letterSpacing: 0.6)),
          pw.SizedBox(height: 2),
          one(value, bold: true, width: 240),
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

  final headcount = dpr.manpowerCount > 0
      ? (dpr.manpowerCount == 1 ? '1 worker' : '${dpr.manpowerCount} workers')
      : 'Not recorded';

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 28),
    header: (ctx) => ctx.pageNumber == 1
        ? pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 14),
            padding: const pw.EdgeInsets.fromLTRB(14, 12, 16, 12),
            decoration: pw.BoxDecoration(color: _navy, borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
              if (branding.logo != null)
                pw.Container(
                  padding: const pw.EdgeInsets.all(3),
                  decoration: pw.BoxDecoration(color: PdfColors.white, borderRadius: pw.BorderRadius.circular(4)),
                  child: pw.Image(pw.MemoryImage(branding.logo!), height: 34, fit: pw.BoxFit.contain),
                )
              else
                pw.CustomPaint(size: const PdfPoint(34, 34), painter: (c, s) => _paintHat(c, s.x, line: PdfColors.white)),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  one(companyName, size: 16, bold: true, color: PdfColors.white, width: 330),
                  pw.SizedBox(height: 2),
                  pw.Text('Daily progress report', style: const pw.TextStyle(fontSize: 10, color: _amber)),
                ]),
              ),
              pw.Text(date, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
            ]),
          )
        : pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 10),
            padding: const pw.EdgeInsets.only(bottom: 4),
            decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line))),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              one(companyName, size: 8, color: _muted, width: 300),
              pw.Text('Daily progress report, $date', style: const pw.TextStyle(fontSize: 8, color: _muted)),
            ]),
          ),
    footer: (ctx) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 8),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        if (branding.showFooter)
          pw.Row(children: [
            pw.CustomPaint(size: const PdfPoint(11, 11), painter: (c, s) => _paintHat(c, s.x, line: _navy)),
            pw.SizedBox(width: 4),
            pw.Text('Made with FieldOS', style: const pw.TextStyle(fontSize: 8, color: _muted)),
          ])
        else
          pw.SizedBox(),
        pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: _muted)),
      ]),
    ),
    build: (_) => [
      pw.Wrap(spacing: 8, runSpacing: 8, children: [
        infoCell('Project', project.name),
        if (client.isNotEmpty) infoCell('Client', client),
        infoCell('Workers on site', headcount),
        if (weather.isNotEmpty) infoCell('Weather', weather),
      ]),
      heading('Work done'),
      ...text(dpr.workSummary.trim().isEmpty ? 'Nothing written for this day.' : dpr.workSummary),
      if (issues.isNotEmpty) ...[
        heading('Issues raised'),
        pw.Table(
          border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.6)),
          columnWidths: const {
            0: pw.FixedColumnWidth(70),
            1: pw.FlexColumnWidth(),
            2: pw.FixedColumnWidth(70),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _paper),
              children: [
                for (final h in ['Severity', 'Issue', 'Status'])
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(h, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _muted)),
                  ),
              ],
            ),
            for (final i in issues)
              pw.TableRow(children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(_sentence(i.severity),
                      style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: i.severity == 'high' || i.severity == 'critical' ? PdfColors.red800 : _ink)),
                ),
                pw.Padding(padding: const pw.EdgeInsets.all(6), child: one(i.description, size: 10, width: 330)),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(_sentence(i.status), style: const pw.TextStyle(fontSize: 10)),
                ),
              ]),
          ],
        ),
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
        if (morePhotos > 0)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6),
            child: pw.Text('$morePhotos more photo${morePhotos == 1 ? '' : 's'} in the FieldOS app.',
                style: const pw.TextStyle(fontSize: 9, color: _muted)),
          ),
      ],
    ],
  ));
  return doc.save();
}

/// The FieldOS hard hat (lib/core/brand.dart's painter), in PDF
/// coordinates: the origin is the bottom-left corner and y goes up.
void _paintHat(PdfGraphics c, double s, {required PdfColor line}) {
  double y(double flutterY) => s - flutterY;
  void rrect(double l, double t, double r, double b, double radius, PdfColor color) {
    c
      ..setFillColor(color)
      ..drawRRect(l, y(b), r - l, b - t, radius, radius)
      ..fillPath();
  }

  final cx = s / 2, cy = s * 0.56, w = s * 0.72, r = w * 0.36;
  const k = 0.5523;
  // Dome: the upper half circle, as two quarter-circle curves.
  c
    ..setFillColor(_amber)
    ..moveTo(cx - r, y(cy))
    ..curveTo(cx - r, y(cy - k * r), cx - k * r, y(cy - r), cx, y(cy - r))
    ..curveTo(cx + k * r, y(cy - r), cx + r, y(cy - k * r), cx + r, y(cy))
    ..closePath()
    ..fillPath();
  final rw = r * 0.22;
  rrect(cx - rw / 2, cy - r * 0.97, cx + rw / 2, cy, rw / 2, _amberDark);
  final bh = r * 0.16;
  rrect(cx - r, cy - bh, cx + r, cy, 0, _amberDark);
  final bw = w / 2, brh = r * 0.26;
  rrect(cx - bw, cy, cx + bw, cy + brh, brh / 2, _amber);
  final lw = w * 0.34, lh = r * 0.1, gap = r * 0.34;
  rrect(cx - lw, cy + brh + gap, cx + lw, cy + brh + gap + lh, lh / 2, line);
}

/// File-name date: 2026-11-06.
String _fileDate(DateTime d) {
  final l = d.toLocal();
  return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
}

/// The text that goes with the PDF in WhatsApp, where any language reads
/// properly.
String dprShareText(Project project, DprEntry dpr) {
  final head = [
    'Daily progress report',
    project.name,
    fmtDate(dpr.entryDate),
  ].join(' · ');
  final facts = [
    if (dpr.manpowerCount > 0) dpr.manpowerCount == 1 ? '1 worker on site' : '${dpr.manpowerCount} workers on site',
    if ((dpr.weather ?? '').trim().isNotEmpty) dpr.weather!.trim(),
  ].join(' · ');
  return [head, if (facts.isNotEmpty) facts, '', dpr.workSummary.trim()].join('\n');
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
    branding: await loadBranding(db, project.companyId),
  );
  final dir = await getTemporaryDirectory();
  final safeProject = project.name.replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\-]+', unicode: true), '_');
  final file = File('${dir.path}/DPR_${safeProject}_${_fileDate(dpr.entryDate)}.pdf');
  await file.writeAsBytes(bytes);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: 'application/pdf')],
    text: dprShareText(project, dpr),
  ));
}
