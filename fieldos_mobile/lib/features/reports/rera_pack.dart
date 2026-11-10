/// The RERA quarterly progress pack (Telangana first): each block and
/// floor's stage and % complete at the quarter's end, the work done in the
/// quarter from the daily reports, and dated site photos, in one PDF in the
/// order the quarterly progress report asks for. The architect's, engineer's
/// and CA's certificates, the escrow statement and the booking register are
/// listed as still to attach: they are not FieldOS's to make.
///
/// TS-RERA wants the report within 15 days of each quarter's end
/// (quarters end 31 Mar, 30 Jun, 30 Sep and 31 Dec).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/company/branding.dart';
import 'package:fieldos_mobile/features/money/bill_pdf.dart' show pdfSafe;
import 'package:fieldos_mobile/features/money/money_view.dart' show isoDay;

String reraNumberKey(String projectId) => 'rera_no:$projectId';

/// A calendar quarter, [start] to [end] inclusive.
class Quarter {
  const Quarter(this.start, this.end);
  final DateTime start;
  final DateTime end;

  factory Quarter.of(DateTime d) {
    final q = (d.month - 1) ~/ 3;
    final start = DateTime(d.year, q * 3 + 1, 1);
    return Quarter(start, DateTime(d.year, q * 3 + 4, 0));
  }

  Quarter get previous => Quarter.of(start.subtract(const Duration(days: 1)));
  Quarter get next => Quarter.of(end.add(const Duration(days: 1)));

  /// The last day to upload the report: 15 days after the quarter ends.
  DateTime get dueBy => end.add(const Duration(days: 15));

  String get startDay => isoDay(start);
  String get endDay => isoDay(end);

  /// "Jul to Sep 2026".
  String get label {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${m[start.month - 1]} to ${m[end.month - 1]} ${end.year}';
  }

  bool contains(DateTime t) {
    final d = DateTime(t.year, t.month, t.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  @override
  bool operator ==(Object other) => other is Quarter && other.start == start;
  @override
  int get hashCode => start.hashCode;
}

/// The quarter whose report is being written on [today]: the one just
/// ended while its 15 days run, else the current one.
Quarter reportingQuarter(DateTime today) {
  final current = Quarter.of(today);
  final prev = current.previous;
  final d = DateTime(today.year, today.month, today.day);
  return d.isAfter(prev.dueBy) ? current : prev;
}

/// The stage each floor is at and its usual % complete, for a quick pick.
const stagePct = {
  'not_started': 0,
  'excavation': 5,
  'foundation': 15,
  'plinth': 20,
  'columns': 30,
  'slab': 45,
  'masonry': 60,
  'plastering': 75,
  'flooring': 85,
  'finishing': 95,
  'complete': 100,
};

const stageNames = {
  'not_started': 'Not started',
  'excavation': 'Excavation',
  'foundation': 'Foundation',
  'plinth': 'Plinth',
  'columns': 'Columns',
  'slab': 'Slab cast',
  'masonry': 'Brickwork',
  'plastering': 'Plastering',
  'flooring': 'Flooring',
  'finishing': 'Finishing',
  'complete': 'Complete',
};

/// Sorts floors the way a building reads: basements, ground, stilt, then
/// numbers, then terrace and anything else by name.
int floorOrder(String a, String b) {
  int rank(String f) {
    final l = f.trim().toLowerCase();
    if (l.startsWith('b') && int.tryParse(l.replaceAll(RegExp(r'[^0-9]'), '')) != null && l.contains('basement') ||
        RegExp(r'^b\d+$').hasMatch(l)) {
      return -100 - (int.tryParse(l.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0);
    }
    if (l == 'ground' || l == 'g' || l.startsWith('ground')) return 0;
    if (l == 'stilt' || l.startsWith('stilt') || l == 'parking') return -1;
    final n = int.tryParse(l.replaceAll(RegExp(r'[^0-9]'), ''));
    if (n != null && RegExp(r'^\d+').hasMatch(l)) return n;
    if (l.startsWith('terrace') || l.startsWith('roof')) return 1000;
    return 500;
  }

  final r = rank(a).compareTo(rank(b));
  return r != 0 ? r : a.compareTo(b);
}

/// Each block and floor's latest update on or before [day] (yyyy-mm-dd).
List<FloorProgressData> progressAsOf(List<FloorProgressData> rows, String day) {
  final latest = <String, FloorProgressData>{};
  for (final r in rows) {
    if (r.asOf.compareTo(day) > 0) continue;
    final key = '${r.block}\u0000${r.floor}';
    final had = latest[key];
    if (had == null ||
        r.asOf.compareTo(had.asOf) > 0 ||
        (r.asOf == had.asOf && !r.createdAt.isBefore(had.createdAt))) {
      latest[key] = r;
    }
  }
  final out = latest.values.toList()
    ..sort((a, b) {
      final c = a.block.compareTo(b.block);
      return c != 0 ? c : floorOrder(a.floor, b.floor);
    });
  return out;
}

/// The average % of a set of floors (each floor counts the same).
double averagePct(Iterable<FloorProgressData> floors) {
  final xs = floors.toList();
  return xs.isEmpty ? 0 : xs.fold<int>(0, (s, f) => s + f.pct) / xs.length;
}

class ReraPack {
  const ReraPack({
    required this.site,
    required this.quarter,
    required this.reraNumber,
    required this.floors,
    required this.floorsAtStart,
    required this.work,
    required this.photos,
  });
  final Project site;
  final Quarter quarter;
  final String? reraNumber;

  /// Each floor at the quarter's end, and at the day before it began.
  final List<FloorProgressData> floors;
  final List<FloorProgressData> floorsAtStart;

  /// The quarter's confirmed daily reports, oldest first.
  final List<DprEntry> work;

  /// Up to [maxPhotos] photos from those reports, spread over the quarter.
  final List<({DprPhoto photo, DateTime takenOn})> photos;

  double get overallPct => averagePct(floors);
  double get overallPctAtStart => averagePct(floorsAtStart);

  Map<String, List<FloorProgressData>> get byBlock {
    final m = <String, List<FloorProgressData>>{};
    for (final f in floors) {
      (m[f.block] ??= []).add(f);
    }
    return m;
  }
}

const maxPhotos = 12;

/// Picks up to [n] items spread evenly over [xs].
List<T> spread<T>(List<T> xs, int n) {
  if (xs.length <= n) return xs;
  return [for (var i = 0; i < n; i++) xs[(i * xs.length) ~/ n]];
}

Future<ReraPack> buildReraPack(AppDatabase db, Project site, Quarter quarter) async {
  final rows = await db.floorProgressDao.forProject(site.id);
  final dprs = (await db.dprDao.forProject(site.id))
      .where((d) => d.status == 'confirmed' && quarter.contains(d.entryDate.toLocal()))
      .toList()
    ..sort((a, b) => a.entryDate.compareTo(b.entryDate));
  final photos = <({DprPhoto photo, DateTime takenOn})>[];
  for (final d in dprs) {
    for (final p in await db.dprDao.photosFor(d.id)) {
      if (File(p.photoPath).existsSync()) photos.add((photo: p, takenOn: d.entryDate.toLocal()));
    }
  }
  return ReraPack(
    site: site,
    quarter: quarter,
    reraNumber: (await db.settingsDao.get(reraNumberKey(site.id)))?.trim(),
    floors: progressAsOf(rows, quarter.endDay),
    floorsAtStart: progressAsOf(rows, isoDay(quarter.start.subtract(const Duration(days: 1)))),
    work: dprs,
    photos: spread(photos, maxPhotos),
  );
}

/// A photo made small enough for the PDF (1000 px wide, JPEG 70).
Future<Uint8List?> pdfPhoto(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final small = decoded.width > 1000 ? img.copyResize(decoded, width: 1000) : decoded;
    return Uint8List.fromList(img.encodeJpg(small, quality: 70));
  } catch (_) {
    return null;
  }
}

const _ink = PdfColor.fromInt(0xFF1B2733);
const _muted = PdfColor.fromInt(0xFF5B6B80);
const _line = PdfColor.fromInt(0xFFDDE3EB);
const _paper = PdfColor.fromInt(0xFFF4F6F9);

Future<Uint8List> buildReraPackPdf(ReraPack pack,
    {required String companyName, PdfBranding branding = const PdfBranding(), DateTime? now}) async {
  final doc = pw.Document(title: 'RERA quarterly progress ${pack.site.name} ${pack.quarter.label}', creator: 'FieldOS');
  final accent = brandInk(branding);
  pw.Widget t(String s, {double size = 9, bool bold = false, PdfColor color = _ink, pw.TextAlign? align}) => pw.Text(
        pdfSafe(s),
        textAlign: align,
        style: pw.TextStyle(fontSize: size, color: color, fontWeight: bold ? pw.FontWeight.bold : null),
      );
  pw.Widget h(String s) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
        child: t(s, size: 11, bold: true, color: accent),
      );
  pw.Widget cell(String s, {bool bold = false, PdfColor color = _ink, bool right = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: t(s, size: 8, bold: bold, color: color, align: right ? pw.TextAlign.right : null),
      );

  final images = <({pw.MemoryImage image, DateTime on, String? caption})>[];
  for (final p in pack.photos) {
    final b = await pdfPhoto(p.photo.photoPath);
    if (b != null) images.add((image: pw.MemoryImage(b), on: p.takenOn, caption: p.photo.caption));
  }
  final atStart = {for (final f in pack.floorsAtStart) '${f.block}\u0000${f.floor}': f.pct};

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(30),
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
            t(pack.site.name, color: _muted),
            t('RERA registration: ${pack.reraNumber?.isNotEmpty == true ? pack.reraNumber! : '(add it in FieldOS)'}',
                color: _muted),
          ]),
        ),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          t('QUARTERLY PROGRESS', size: 13, bold: true, color: accent),
          t('Quarter: ${pack.quarter.label}', color: _muted),
          t('To upload by ${fmtDate(pack.quarter.dueBy)}', color: _muted),
          t('Made on ${fmtDate(now ?? DateTime.now())}', size: 7, color: _muted),
        ]),
      ]),
      pw.Container(height: 2, color: accent, margin: const pw.EdgeInsets.symmetric(vertical: 8)),
      h('1. Construction progress at ${fmtDate(pack.quarter.end)}'),
      if (pack.floors.isEmpty)
        t('No floor progress recorded yet.', color: _muted)
      else ...[
        t('Overall: ${pack.overallPct.round()}% complete'
            '${pack.floorsAtStart.isEmpty ? '' : ' (was ${pack.overallPctAtStart.round()}% at the start of the quarter)'}.'),
        pw.SizedBox(height: 6),
        pw.Table(
          border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.5), bottom: pw.BorderSide(color: _line)),
          children: [
            pw.TableRow(decoration: pw.BoxDecoration(color: accent), children: [
              for (final head in ['Block', 'Floor', 'Stage', 'At start', 'Now', 'Updated'])
                cell(head, bold: true, color: PdfColors.white),
            ]),
            for (final f in pack.floors)
              pw.TableRow(children: [
                cell(f.block),
                cell(f.floor),
                cell(stageNames[f.stage] ?? f.stage),
                cell(atStart.containsKey('${f.block}\u0000${f.floor}') ? '${atStart['${f.block}\u0000${f.floor}']}%' : '-'),
                cell('${f.pct}%', bold: true),
                cell(fmtDate(DateTime.parse(f.asOf))),
              ]),
            for (final e in pack.byBlock.entries)
              pw.TableRow(decoration: const pw.BoxDecoration(color: _paper), children: [
                cell(e.key, bold: true),
                cell('All floors', bold: true),
                cell(''),
                cell(''),
                cell('${averagePct(e.value).round()}%', bold: true),
                cell(''),
              ]),
          ],
        ),
      ],
      h('2. Work done in the quarter'),
      if (pack.work.isEmpty)
        t('No daily reports in this quarter.', color: _muted)
      else
        for (final d in pack.work.length > 60 ? spread(pack.work, 60) : pack.work)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.SizedBox(width: 62, child: t(fmtDate(d.entryDate.toLocal()), size: 8, color: _muted)),
              pw.Expanded(child: t(d.workSummary.replaceAll('\n', ' '), size: 8)),
            ]),
          ),
      if (pack.work.length > 60)
        t('${pack.work.length} daily reports in the quarter; 60 shown, spread over it.', size: 7, color: _muted),
      h('3. Site photographs'),
      if (images.isEmpty)
        t('No photos on the daily reports of this quarter.', color: _muted)
      else
        pw.Wrap(spacing: 8, runSpacing: 8, children: [
          for (final i in images)
            pw.SizedBox(
              width: 255,
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Image(i.image, height: 170, fit: pw.BoxFit.cover),
                t('${fmtDate(i.on)}${i.caption == null || i.caption!.isEmpty ? '' : '  ${i.caption}'}', size: 7, color: _muted),
              ]),
            ),
        ]),
      h('4. To attach before uploading'),
      for (final line in const [
        "Architect's certificate of the stage of completion (Form 1)",
        "Engineer's certificate of the cost incurred (Form 2)",
        "Chartered accountant's certificate and the RERA account statement (Form 3)",
        'Booking register: units sold, booked and available',
      ])
        pw.Padding(padding: const pw.EdgeInsets.only(bottom: 3), child: t('[  ]  $line')),
      pw.SizedBox(height: 6),
      t('Progress is as recorded on site in FieldOS. The architect certifies the stage of completion for RERA.',
          size: 7, color: _muted),
    ],
  ));
  return doc.save();
}
