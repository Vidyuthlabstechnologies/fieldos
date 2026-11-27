/// A supplier sees what an order is made of (quantity, rate, GST, transport),
/// not only its total (customer review: a total was a figure to trust).
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

final _quoted = SupplierOrder(
    id: 'po-1', site: 'Narapally', companyName: 'Sai Constructions', status: 'issued', poNumber: 'PO-0007', item: 'TMT 12mm',
    total: 150000, quantity: 2.5, unit: 'tonne', rate: 52000, gstPct: 18, transport: 3000);
const _old = SupplierOrder(id: 'po-2', site: 'Narapally', companyName: 'Sai Constructions', status: 'issued', poNumber: 'PO-0008', total: 900);

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));

  test('an order from a newer server carries its make-up; from an older one it does not', () {
    final o = SupplierOrder.fromJson({
      'id': 'a', 'site': 'S', 'company_name': 'C', 'status': 'issued', 'total': 150000, 'quantity': 2.5, 'unit': 'tonne',
      'rate': 52000, 'gst_pct': 18, 'transport': 3000,
    });
    expect((o.quantity, o.unit, o.rate, o.gstPct, o.transport), (2.5, 'tonne', 52000.0, 18.0, 3000.0));
    final old = SupplierOrder.fromJson({'id': 'b', 'site': 'S', 'company_name': 'C', 'status': 'issued', 'total': 900});
    expect((old.quantity, old.rate), (null, null));
  });

  Future<void> pump(WidgetTester tester, {Size size = const Size(412, 915)}) async {
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      cloudSyncClientProvider.overrideWith((ref) {
        final c = _offline();
        ref.onDispose(c.dispose);
        return c;
      }),
      portalServiceProvider.overrideWithValue(_Portal()),
      supplierPortalProvider.overrideWith((ref) async => SupplierPortalData(companies: const ['Sai Constructions'], requests: const [], orders: [_quoted, _old])),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: const SupplierHomeScreen()),
    ));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text(tr('Orders')));
    await tester.pumpAndSettle();
  }

  testWidgets('the order shows quantity, rate, GST and transport; one with no quote shows none', (tester) async {
    await pump(tester);
    final line = tester.widget<Text>(find.byKey(const Key('order-breakup-po-1'))).data!;
    expect(line, contains('2.5 tonne'));
    expect(line, contains('52,000'));
    expect(line, contains('GST 18%'));
    expect(line, contains('3,000'));
    expect(find.byKey(const Key('order-breakup-po-2')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Telugu on a 320 px phone fits the line', (tester) async {
    setCurrentLanguage(AppLanguage.te);
    await pump(tester, size: const Size(320, 640));
    expect(find.byKey(const Key('order-breakup-po-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
