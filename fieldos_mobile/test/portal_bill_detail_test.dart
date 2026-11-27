/// A client sees how a bill is made up (gross, GST, retention, TDS, net), and
/// can open a site photo full screen (customer review: a homeowner who
/// distrusts extras and deductions was given one net figure and 84 px
/// thumbnails).
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
  @override
  Future<String> photoUrl(String path) async => 'http://localhost:1/$path';
}

ClientSite _site({List<SiteBill>? bills}) => ClientSite(
      id: 'p-1',
      name: 'Narapally villa',
      companyName: 'Sai Constructions',
      tasksTotal: 10,
      tasksDone: 4,
      updates: [
        SiteUpdate(id: 'd-1', date: DateTime(2026, 11, 9), summary: 'Slab shuttering', manpower: 14, photos: const ['p-1/slab.jpg']),
      ],
      bills: bills ?? const [],
      payments: const [],
    );

final _breakdown = SiteBill(
    number: 'RA-1', date: DateTime(2026, 11, 1), amount: 106200, status: 'issued', kind: 'ra', gross: 118000, gstRate: 18, retentionPct: 5, tdsPct: 1);
final _plain = SiteBill(
    number: 'RA-2', date: DateTime(2026, 11, 8), amount: 5900, status: 'paid', kind: 'ra', gross: 5000, gstRate: 18, retentionPct: 0, tdsPct: 0);
final _old = SiteBill(number: 'RA-0', date: DateTime(2026, 10, 1), amount: 7000, status: 'issued', kind: 'ra');

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));

  Future<void> pump(WidgetTester tester, List<SiteBill> bills, {Size size = const Size(412, 915)}) async {
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      cloudSyncClientProvider.overrideWith((ref) {
        final c = _offline();
        ref.onDispose(c.dispose);
        return c;
      }),
      portalServiceProvider.overrideWithValue(_Portal()),
      clientPortalProvider.overrideWith((ref) async => [_site(bills: bills)]),
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
      child: MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: const ClientHomeScreen()),
    ));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }
  }

  test('the server\'s bill carries its breakdown; an older server\'s does not and still reads', () {
    final site = ClientSite.fromJson({
      'id': 'p', 'name': 'V', 'company_name': 'C', 'tasks_total': 0, 'tasks_done': 0,
      'bills': [
        {'number': 'RA-1', 'date': '2026-11-01', 'kind': 'ra', 'amount': 106200, 'status': 'issued', 'gross': 118000, 'gst_rate': 18, 'retention_pct': 5, 'tds_pct': 1},
        {'number': 'RA-0', 'date': '2026-10-01', 'kind': 'ra', 'amount': 7000, 'status': 'issued'},
      ],
    });
    final b = site.bills.first;
    expect((b.gross, b.gstRate, b.retentionPct, b.tdsPct), (118000, 18, 5, 1));
    expect(site.bills.last.gross, isNull);
    expect(site.billed, 113200, reason: 'the billed total is still the sum of what is payable');
  });

  testWidgets('opening a bill shows what it is made up of', (tester) async {
    await pump(tester, [_breakdown]);
    await tester.scrollUntilVisible(find.byKey(const Key('client-bill-RA-1')), 200, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('client-bill-RA-1-Gross')), findsNothing, reason: 'closed until opened');
    await tester.tap(find.byKey(const Key('client-bill-RA-1')));
    await tester.pumpAndSettle();
    String text(String label) => tester.widget<Text>(find.byKey(Key('client-bill-RA-1-$label'))).data!;
    expect(text('Gross'), contains('1,18,000'));
    expect(text('GST %'), '18%');
    expect(text('Retention %'), '5%');
    expect(text('TDS %'), '1%');
    expect(text('Net payable'), contains('1,06,200'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a bill with no retention or TDS does not list them', (tester) async {
    await pump(tester, [_plain]);
    await tester.scrollUntilVisible(find.byKey(const Key('client-bill-RA-2')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('client-bill-RA-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('client-bill-RA-2-Gross')), findsOneWidget);
    expect(find.byKey(const Key('client-bill-RA-2-GST %')), findsOneWidget);
    expect(find.byKey(const Key('client-bill-RA-2-Retention %')), findsNothing);
    expect(find.byKey(const Key('client-bill-RA-2-TDS %')), findsNothing);
    expect(find.byKey(const Key('client-bill-RA-2-Net payable')), findsOneWidget);
  });

  testWidgets('an older server sends only the net amount: the bill still reads, with nothing to open', (tester) async {
    await pump(tester, [_old]);
    await tester.scrollUntilVisible(find.text('RA-0 · 1 Oct'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('To pay'), findsOneWidget);
    expect(find.byKey(const Key('client-bill-RA-0')), findsNothing);
  });

  testWidgets('a photo opens full screen to look at, and closes', (tester) async {
    await pump(tester, [_breakdown]);
    await tester.tap(find.byKey(const Key('client-photo-p-1/slab.jpg')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('client-photo-zoom')), findsOneWidget);
    await tester.tap(find.byKey(const Key('client-photo-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('client-photo-zoom')), findsNothing);
  });

  testWidgets('Telugu on a 320 px phone fits an opened bill', (tester) async {
    setCurrentLanguage(AppLanguage.te);
    await pump(tester, [_breakdown], size: const Size(320, 640));
    await tester.scrollUntilVisible(find.byKey(const Key('client-bill-RA-1')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('client-bill-RA-1')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(Key('client-bill-RA-1-${tr('Gross')}')), findsOneWidget);
  });
}
