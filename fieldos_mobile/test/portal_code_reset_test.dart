/// The builder can change a portal code, and remove the people who joined with
/// it (customer review: a code was permanent, so a forwarded or old one gave
/// access for ever).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/features/portals/portal_share.dart';
import 'package:fieldos_mobile/l10n/language.dart';

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));

  Future<List<bool>> pump(WidgetTester tester, {bool failReset = false, Size size = const Size(412, 915)}) async {
    final calls = <bool>[];
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildFieldOsTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const Key('open'),
              onPressed: () => showPortalCode(
                context,
                title: 'Share Villa with the client',
                code: 'OLDCODE1',
                about: 'About',
                share: (c) => 'join with $c',
                reset: ({required removeAccess}) async {
                  calls.add(removeAccess);
                  if (failReset) throw StateError('offline');
                  return 'NEWCODE2';
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    return calls;
  }

  String shown(WidgetTester tester) => tester.widget<SelectableText>(find.byKey(const Key('portal-code-shown'))).data!;

  testWidgets('changing the code and keeping those who joined asks the server for exactly that', (tester) async {
    final calls = await pump(tester);
    expect(shown(tester), 'OLDCODE1');
    await tester.tap(find.byKey(const Key('portal-code-change')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('portal-code-keep')));
    await tester.pumpAndSettle();
    expect(calls, [false]);
    expect(shown(tester), 'NEWCODE2', reason: 'the new code is shown at once, ready to share');
  });

  testWidgets('removing those who joined says so to the server, and the dialog warns what it does', (tester) async {
    final calls = await pump(tester);
    await tester.tap(find.byKey(const Key('portal-code-change')));
    await tester.pumpAndSettle();
    expect(find.textContaining('everyone who joined loses access'), findsOneWidget);
    await tester.tap(find.byKey(const Key('portal-code-remove')));
    await tester.pumpAndSettle();
    expect(calls, [true]);
    expect(shown(tester), 'NEWCODE2');
  });

  testWidgets('cancelling the choice changes nothing', (tester) async {
    final calls = await pump(tester);
    await tester.tap(find.byKey(const Key('portal-code-change')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(find.byKey(const Key('portal-code-shown')), findsNothing, reason: 'back out of the whole flow');
  });

  testWidgets('a failed change leaves the old code, which is still the one in force', (tester) async {
    final calls = await pump(tester, failReset: true);
    await tester.tap(find.byKey(const Key('portal-code-change')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('portal-code-remove')));
    await tester.pumpAndSettle();
    expect(calls, [true]);
    expect(find.byKey(const Key('portal-code-shown')), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('Telugu on a 320 px phone fits both dialogs', (tester) async {
    setCurrentLanguage(AppLanguage.te);
    await pump(tester, size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('portal-code-change')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('portal-code-remove')), findsOneWidget);
  });
}
