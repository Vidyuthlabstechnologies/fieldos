import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:fieldos_mobile/features/shared/photo_viewer.dart';

/// A saved report's photos could not be seen again, or shared on their
/// own: only the PDF carried them.
void main() {
  late Directory dir;
  late List<String> paths;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('photos');
    paths = [
      for (var i = 0; i < 3; i++)
        (File('${dir.path}/p$i.jpg')..writeAsBytesSync(img.encodeJpg(img.Image(width: 8, height: 8)))).path,
    ];
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('photos taken on another phone are left out', () {
    expect(photosOnThisPhone([...paths, '/nowhere/teammate.jpg']), paths);
  });

  testWidgets('the strip opens a swipeable full-screen viewer with share', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PhotoStrip(paths: paths))));
    expect(find.text('Share all photos'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Open photo').at(1));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.byTooltip('Share photo'), findsOneWidget);
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
  });

  testWidgets('one photo has no "share all"', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PhotoStrip(paths: paths.take(1).toList()))));
    expect(find.text('Share all photos'), findsNothing);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PhotoStrip(paths: []))));
    expect(find.bySemanticsLabel('Open photo'), findsNothing);
  });
}
