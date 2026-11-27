/// A new client or supplier has nothing yet, and the first thing they see is
/// the empty screen. It used to be a list inside a list and failed to lay out
/// ("Vertical viewport was given unbounded height").
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/portals/portal_screens.dart';
import 'package:fieldos_mobile/features/portals/portal_service.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

SupabaseClient _offline() => SupabaseClient('http://localhost:1', 'anon',
    authOptions: const AuthClientOptions(autoRefreshToken: false, authFlowType: AuthFlowType.implicit));

class _Portal extends PortalService {
  _Portal() : super(_offline());
}

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));

  Future<void> pump(WidgetTester tester, Widget home) async {
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      cloudSyncClientProvider.overrideWith((ref) {
        final c = _offline();
        ref.onDispose(c.dispose);
        return c;
      }),
      portalServiceProvider.overrideWithValue(_Portal()),
      supplierPortalProvider.overrideWith((ref) async => const SupplierPortalData(companies: ['Sai Constructions'], requests: [], orders: [])),
      clientPortalProvider.overrideWith((ref) async => const <ClientSite>[]),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: home),
    ));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('a client with no site yet is told what to do', (tester) async {
    await pump(tester, const ClientHomeScreen());
    expect(find.text('No site yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a supplier with no requests or orders yet is told what will show here', (tester) async {
    await pump(tester, const SupplierHomeScreen());
    expect(find.text('No price requests yet'), findsOneWidget);
    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();
    expect(find.text('No orders yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
