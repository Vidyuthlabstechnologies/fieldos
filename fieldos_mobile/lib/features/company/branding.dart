/// The company's own look on the PDFs it sends (bills, vouchers, daily
/// reports): its logo, and whether "Made with FieldOS" is printed. Onsite
/// users ask for their logo on bills and for the app's branding to be
/// optional. Kept on this phone (in settings), so it works offline; the
/// logo is shrunk to keep every PDF small.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:fieldos_mobile/data/app_database.dart';

class PdfBranding {
  const PdfBranding({this.logo, this.showFooter = true});

  /// PNG bytes, at most [logoMaxSide] pixels on the long side.
  final Uint8List? logo;
  final bool showFooter;
}

const logoMaxSide = 360;

String logoKey(String companyId) => 'company_logo:$companyId';
String footerKey(String companyId) => 'pdf_footer_hidden:$companyId';

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
  return PdfBranding(logo: logo, showFooter: !hidden);
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
