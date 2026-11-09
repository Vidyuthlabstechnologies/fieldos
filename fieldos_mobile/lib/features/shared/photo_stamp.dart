/// Burns the date, time and GPS position into a site photo, the way
/// contractors' "timestamp camera" apps do, so a photo forwarded on
/// WhatsApp still proves when and where it was taken.
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

String stampTime(DateTime t) {
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}

/// Lines for the stamp. Only Latin-1 text is drawn (the bundled bitmap font
/// has no Indic glyphs), so a Telugu or Hindi project name is left out
/// rather than drawn as boxes.
List<String> stampLines({required DateTime takenAt, String? place, double? lat, double? lng, double? accuracyM}) {
  final first = [stampTime(takenAt), if (place != null && place.runes.every((r) => r < 0x100)) place].join('  ');
  final second = lat == null || lng == null
      ? 'GPS not available'
      : '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}${accuracyM == null ? '' : '  (+/-${accuracyM.round()} m)'}';
  return [first, second, 'FieldOS'];
}

/// Returns the JPEG with the stamp drawn along the bottom, or null if the
/// bytes aren't an image the decoder understands (the original is kept).
/// With [below] the stamp goes on a strip added under the photo instead of
/// over it, so a bill's total at the bottom is never covered.
Uint8List? stampJpeg(Uint8List bytes, List<String> lines, {bool below = false, int quality = 85}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var photo = img.bakeOrientation(decoded);
  final font = photo.width >= 1200 ? img.arial48 : (photo.width >= 600 ? img.arial24 : img.arial14);
  final lineH = font.lineHeight + 6;
  final bandH = lineH * lines.length + 16;
  if (below) {
    final taller = img.Image(width: photo.width, height: photo.height + bandH);
    img.fill(taller, color: img.ColorRgb8(0, 0, 0));
    img.compositeImage(taller, photo, dstX: 0, dstY: 0);
    photo = taller;
  } else {
    img.fillRect(photo,
        x1: 0, y1: photo.height - bandH, x2: photo.width, y2: photo.height, color: img.ColorRgba8(0, 0, 0, 150));
  }
  for (var i = 0; i < lines.length; i++) {
    img.drawString(photo, lines[i],
        font: font, x: 14, y: photo.height - bandH + 8 + i * lineH, color: img.ColorRgb8(255, 255, 255));
  }
  return img.encodeJpg(photo, quality: quality);
}

/// [stampJpeg] off the UI thread (decoding a 2048 px photo takes a moment).
Future<Uint8List?> stampJpegInBackground(Uint8List bytes, List<String> lines, {bool below = false, int quality = 85}) =>
    Isolate.run(() => stampJpeg(bytes, lines, below: below, quality: quality));
