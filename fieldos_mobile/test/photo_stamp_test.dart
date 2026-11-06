import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:fieldos_mobile/features/shared/photo_stamp.dart';

void main() {
  test('stamp lines: time, place, GPS; Indic place names left out instead of drawn as boxes', () {
    final t = DateTime(2026, 11, 5, 9, 7);
    expect(stampLines(takenAt: t, place: 'Block A', lat: 17.4012345, lng: 78.5, accuracyM: 7.6),
        ['05/11/2026 09:07  Block A', '17.401235, 78.500000  (+/-8 m)', 'FieldOS']);
    expect(stampLines(takenAt: t, place: 'నారపల్లి').first, '05/11/2026 09:07');
    expect(stampLines(takenAt: t)[1], 'GPS not available');
  });

  test('stamp darkens a band along the bottom and keeps the size', () {
    final white = img.Image(width: 800, height: 600)..clear(img.ColorRgb8(255, 255, 255));
    final jpeg = Uint8List.fromList(img.encodeJpg(white));
    final out = stampJpeg(jpeg, stampLines(takenAt: DateTime(2026, 11, 5), lat: 1, lng: 2));
    expect(out, isNotNull);
    final back = img.decodeJpg(out!)!;
    expect(back.width, 800);
    expect(back.height, 600);
    expect(back.getPixel(790, 595).r, lessThan(200), reason: 'band is darkened');
    expect(back.getPixel(400, 20).r, greaterThan(240), reason: 'top of the photo untouched');
  });

  test('bytes that are not an image are left alone', () {
    expect(stampJpeg(Uint8List.fromList([1, 2, 3]), ['x']), isNull);
  });
}
