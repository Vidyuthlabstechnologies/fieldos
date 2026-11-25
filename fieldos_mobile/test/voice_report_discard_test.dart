/// A spoken report is not lost to a stray tap or the back button (customer
/// review: a junior engineer speaks for two or three minutes, one hand free,
/// and tapping outside the sheet threw it all away).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/project/voice_report_sheet.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/speech_service.dart';

/// Stands in for the phone's recognizer: nothing touches the microphone.
class _FakeDictation extends DictationController {
  _FakeDictation(this.heard);
  String heard;
  @override
  String get text => heard;
  @override
  Future<void> start(SpeechLanguage language) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<String> finish() async => heard;
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late GlobalKey<NavigatorState> nav;
  Object? closedWith = 'still open';

  Future<void> openSheet(WidgetTester tester, _FakeDictation fake) async {
    closedWith = 'still open';
    db = AppDatabase.memory();
    container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    nav = GlobalKey<NavigatorState>();
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(navigatorKey: nav, theme: buildFieldOsTheme(Brightness.light), home: const Scaffold()),
    ));
    final future = showModalBottomSheet<Object?>(
      context: nav.currentContext!,
      isScrollControlled: true,
      enableDrag: false,
      builder: (_) => VoiceReportSheet(dictation: fake),
    );
    future.then((v) => closedWith = v);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Speak your report'), findsOneWidget);
  }

  testWidgets('nothing said yet: back closes the sheet without asking', (tester) async {
    await openSheet(tester, _FakeDictation(''));
    await nav.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Speak your report'), findsNothing);
    expect(find.text('Throw away what you said?'), findsNothing);
  });

  testWidgets('something said: back asks first, and Keep it leaves the report where it was', (tester) async {
    await openSheet(tester, _FakeDictation('Slab shuttering done, twelve masons on site'));
    await nav.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Throw away what you said?'), findsOneWidget);
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();
    expect(find.text('Throw away what you said?'), findsNothing);
    expect(find.text('Speak your report'), findsOneWidget, reason: 'the sheet is still open');
  });

  testWidgets('something said: Throw it away closes the sheet', (tester) async {
    await openSheet(tester, _FakeDictation('Slab shuttering done'));
    await nav.currentState!.maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Throw it away'));
    await tester.pumpAndSettle();
    expect(find.text('Speak your report'), findsNothing);
    expect(closedWith, isNull, reason: 'closed without a report');
  });

  testWidgets('tapping outside the sheet is asked about too', (tester) async {
    await openSheet(tester, _FakeDictation('Slab shuttering done'));
    await tester.tapAt(const Offset(200, 40)); // the dimmed area above the sheet
    await tester.pumpAndSettle();
    expect(find.text('Throw away what you said?'), findsOneWidget);
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();
    expect(find.text('Speak your report'), findsOneWidget);
  });

  testWidgets('Done is deliberate: it hands the report back and never asks', (tester) async {
    await openSheet(tester, _FakeDictation('Slab shuttering done'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Throw away what you said?'), findsNothing);
    expect(closedWith, isA<VoiceReport>());
    expect((closedWith as VoiceReport).text, 'Slab shuttering done');
  });
}
