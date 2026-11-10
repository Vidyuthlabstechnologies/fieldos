/// The company's own look on the PDFs it sends (bills, vouchers, daily
/// reports): its logo, and whether "Made with FieldOS" is printed. Onsite
/// users ask for their logo on bills and for the app's branding to be
/// optional. Kept on this phone (in settings), so it works offline; the
/// logo is shrunk to keep every PDF small.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart' show PdfColor;

import 'package:fieldos_mobile/data/app_database.dart';

class PdfBranding {
  const PdfBranding({this.logo, this.showFooter = true, this.footerText = '', this.accent});

  /// PNG bytes, at most [logoMaxSide] pixels on the long side.
  final Uint8List? logo;
  final bool showFooter;

  /// The company's own line at the foot of every PDF: phone, website,
  /// registration, a tagline.
  final String footerText;

  /// The company's colour (0xAARRGGBB) for headings and table heads, or
  /// null for FieldOS navy.
  final int? accent;

  /// What goes at the foot: the company's line, then "Made with FieldOS"
  /// unless it was turned off.
  String get footerLine => [
        if (footerText.trim().isNotEmpty) footerText.trim(),
        if (showFooter) 'Made with FieldOS',
      ].join('  |  ');

  bool get hasFooter => footerLine.isNotEmpty;
}

/// Colours a company can pick for its PDFs, FieldOS navy first.
const brandColours = <int>[
  0xFF1B2733, 0xFF0B5CAD, 0xFF0E7C66, 0xFF2E7D32, 0xFFB45309, 0xFFC2410C, 0xFFB91C1C, 0xFF7C3AED, 0xFF6D4C41, 0xFF374151,
];

const footerTextMax = 120;

/// The company's colour for a PDF's headings, or [fallback].
PdfColor brandInk(PdfBranding b, [PdfColor fallback = const PdfColor.fromInt(0xFF1B2733)]) =>
    b.accent == null ? fallback : PdfColor.fromInt(b.accent!);

const logoMaxSide = 360;

String logoKey(String companyId) => 'company_logo:$companyId';
String footerKey(String companyId) => 'pdf_footer_hidden:$companyId';
String footerTextKey(String companyId) => 'pdf_footer_text:$companyId';
String accentKey(String companyId) => 'pdf_accent:$companyId';

Future<PdfBranding> loadBranding(AppDatabase db, String? companyId) async {
  if (companyId == null) return const PdfBranding();
  final raw = await db.settingsDao.get(logoKey(companyId));
  Uint8List? logo;
  if (raw != null && raw.isNotEmpty) {
    try {
      logo = base64Decode(raw);
    } catch (_) {
      logo = null;
    }
  }
  final hidden = await db.settingsDao.get(footerKey(companyId)) == '1';
  final accent = int.tryParse(await db.settingsDao.get(accentKey(companyId)) ?? '');
  return PdfBranding(
    logo: logo,
    showFooter: !hidden,
    footerText: await db.settingsDao.get(footerTextKey(companyId)) ?? '',
    accent: accent == null || accent == brandColours.first ? null : accent,
  );
}

/// Shrinks [bytes] (any common image format) to a small PNG. Null when
/// the bytes aren't an image.
Uint8List? shrinkLogo(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final long = decoded.width > decoded.height ? decoded.width : decoded.height;
  final small = long <= logoMaxSide
      ? decoded
      : img.copyResize(decoded,
          width: decoded.width >= decoded.height ? logoMaxSide : null,
          height: decoded.height > decoded.width ? logoMaxSide : null,
          interpolation: img.Interpolation.average);
  return Uint8List.fromList(img.encodePng(small));
}

/// Saves the logo; false when the picked file wasn't an image.
Future<bool> saveLogo(AppDatabase db, String companyId, Uint8List bytes) async {
  final png = shrinkLogo(bytes);
  if (png == null) return false;
  await db.settingsDao.set(logoKey(companyId), base64Encode(png));
  return true;
}

Future<void> removeLogo(AppDatabase db, String companyId) => db.settingsDao.set(logoKey(companyId), '');

Future<void> setShowFooter(AppDatabase db, String companyId, bool show) =>
    db.settingsDao.set(footerKey(companyId), show ? '0' : '1');

Future<void> setFooterText(AppDatabase db, String companyId, String text) {
  final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  return db.settingsDao.set(footerTextKey(companyId), t.length > footerTextMax ? t.substring(0, footerTextMax) : t);
}

/// [argb] null goes back to FieldOS navy.
Future<void> setAccent(AppDatabase db, String companyId, int? argb) =>
    db.settingsDao.set(accentKey(companyId), argb == null ? '' : '$argb');
