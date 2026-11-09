/// A small Excel (.xlsx) writer: sheets of rows with a bold, frozen header
/// row, numbers kept as numbers and dates as real Excel dates, so totals,
/// filters and pivots work the moment the file opens. Pure Dart and offline
/// (an .xlsx is a zip of XML files), so it needs no paid library and no
/// internet.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// One worksheet. [rows] hold String, num, DateTime, bool or null cells.
class XlsxSheet {
  XlsxSheet(this.name, this.headers, this.rows);

  final String name;
  final List<String> headers;
  final List<List<Object?>> rows;
}

/// Excel allows 31 characters and none of `\ / ? * [ ] :` in a sheet name,
/// and every name in a workbook must be different (ignoring case).
List<String> safeSheetNames(List<String> names) {
  final used = <String>{};
  final out = <String>[];
  for (final raw in names) {
    var base = raw.replaceAll(RegExp(r'[\\/?*\[\]:]'), ' ').trim();
    if (base.isEmpty) base = 'Sheet';
    if (base.length > 31) base = base.substring(0, 31).trim();
    var name = base;
    var n = 2;
    while (used.contains(name.toLowerCase())) {
      final suffix = ' ($n)';
      name = '${base.length + suffix.length > 31 ? base.substring(0, 31 - suffix.length) : base}$suffix';
      n++;
    }
    used.add(name.toLowerCase());
    out.add(name);
  }
  return out;
}

/// "A", "B", ... "Z", "AA" for a 0-based column index.
String columnLetter(int index) {
  var i = index + 1;
  final sb = StringBuffer();
  while (i > 0) {
    final r = (i - 1) % 26;
    sb.write(String.fromCharCode(65 + r));
    i = (i - 1) ~/ 26;
  }
  return sb.toString().split('').reversed.join();
}

/// Excel's serial day number (days since 30 Dec 1899) for a local date and
/// time, as Excel stores dates.
double excelSerial(DateTime d) {
  final utc = DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second);
  return utc.difference(DateTime.utc(1899, 12, 30)).inSeconds / 86400.0;
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    // Control characters other than tab and newline are not allowed in XML.
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

// Style ids in styles.xml below: 0 plain, 1 bold header, 2 date, 3 date+time,
// 4 number with two decimals and thousands separators.
const _styleHeader = 1;
const _styleDate = 2;
const _styleDateTime = 3;
const _styleNumber = 4;

String _cell(String ref, Object? v, {bool header = false}) {
  if (v == null) return '';
  if (v is num) {
    if (v.isNaN || v.isInfinite) return '';
    final style = v is double && v != v.roundToDouble() ? ' s="$_styleNumber"' : '';
    return '<c r="$ref"$style><v>$v</v></c>';
  }
  if (v is DateTime) {
    final hasTime = v.hour != 0 || v.minute != 0 || v.second != 0;
    return '<c r="$ref" s="${hasTime ? _styleDateTime : _styleDate}"><v>${excelSerial(v)}</v></c>';
  }
  if (v is bool) return '<c r="$ref" t="b"><v>${v ? 1 : 0}</v></c>';
  final s = v.toString();
  if (s.isEmpty) return '';
  // Excel caps a cell at 32,767 characters.
  final text = s.length > 32767 ? s.substring(0, 32767) : s;
  return '<c r="$ref" t="inlineStr"${header ? ' s="$_styleHeader"' : ''}>'
      '<is><t xml:space="preserve">${_esc(text)}</t></is></c>';
}

String _sheetXml(XlsxSheet sheet) {
  final sb = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
    ..write(
      '<sheetViews><sheetView workbookViewId="0">'
      '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
      '</sheetView></sheetViews>',
    );
  // Width from the longest value in each column (first 200 rows), within reason.
  final widths = List<int>.generate(sheet.headers.length, (i) => sheet.headers[i].length + 2);
  for (final row in sheet.rows.take(200)) {
    for (var i = 0; i < row.length && i < widths.length; i++) {
      final v = row[i];
      final len = v is DateTime ? 12 : (v?.toString().length ?? 0) + 2;
      if (len > widths[i]) widths[i] = len;
    }
  }
  sb.write('<cols>');
  for (var i = 0; i < widths.length; i++) {
    final w = widths[i].clamp(8, 60);
    sb.write('<col min="${i + 1}" max="${i + 1}" width="$w" customWidth="1"/>');
  }
  sb.write('</cols><sheetData>');
  sb.write('<row r="1">');
  for (var c = 0; c < sheet.headers.length; c++) {
    sb.write(_cell('${columnLetter(c)}1', sheet.headers[c], header: true));
  }
  sb.write('</row>');
  for (var r = 0; r < sheet.rows.length; r++) {
    final rowNum = r + 2;
    sb.write('<row r="$rowNum">');
    final row = sheet.rows[r];
    for (var c = 0; c < row.length; c++) {
      sb.write(_cell('${columnLetter(c)}$rowNum', row[c]));
    }
    sb.write('</row>');
  }
  sb.write('</sheetData>');
  if (sheet.headers.isNotEmpty) {
    final last = '${columnLetter(sheet.headers.length - 1)}${sheet.rows.length + 1}';
    sb.write('<autoFilter ref="A1:$last"/>');
  }
  sb.write('</worksheet>');
  return sb.toString();
}

const _stylesXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<numFmts count="2"><numFmt numFmtId="164" formatCode="dd/mm/yyyy"/>'
    '<numFmt numFmtId="165" formatCode="dd/mm/yyyy hh:mm"/></numFmts>'
    '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
    '<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
    '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFFFE8B0"/><bgColor indexed="64"/></patternFill></fill></fills>'
    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="5">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>'
    '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
    '<xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
    '<xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
    '</cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
    '</styleSheet>';

/// The workbook as .xlsx bytes. An empty [sheets] list still gives a valid
/// file with one empty sheet, since Excel refuses a workbook with none.
Uint8List buildXlsx(List<XlsxSheet> sheets) {
  final list = sheets.isEmpty ? [XlsxSheet('Sheet1', const [], const [])] : sheets;
  final names = safeSheetNames(list.map((s) => s.name).toList());
  final archive = Archive();
  void add(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  final overrides = StringBuffer();
  for (var i = 0; i < list.length; i++) {
    overrides.write(
      '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
    );
  }
  add(
    '[Content_Types].xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '$overrides</Types>',
  );
  add(
    '_rels/.rels',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
        'Target="xl/workbook.xml"/></Relationships>',
  );
  final sheetEntries = StringBuffer();
  final rels = StringBuffer();
  for (var i = 0; i < list.length; i++) {
    sheetEntries.write('<sheet name="${_esc(names[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>');
    rels.write(
      '<Relationship Id="rId${i + 1}" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
      'Target="worksheets/sheet${i + 1}.xml"/>',
    );
  }
  rels.write(
    '<Relationship Id="rId${list.length + 1}" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>',
  );
  add(
    'xl/workbook.xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets>$sheetEntries</sheets></workbook>',
  );
  add(
    'xl/_rels/workbook.xml.rels',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">$rels</Relationships>',
  );
  add('xl/styles.xml', _stylesXml);
  for (var i = 0; i < list.length; i++) {
    add('xl/worksheets/sheet${i + 1}.xml', _sheetXml(list[i]));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
