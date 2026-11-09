/// Leaving the Procure tab (or the project) used to throw "Cannot use ref
/// after the widget was disposed": the view read a provider in dispose().
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/procurement/procurement_screen.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

void main() {
  testWidgets('the Procure view can be closed without an error', (tester) async {
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      cloudSyncClientProvider.overrideWith((ref) {
        final c = SupabaseClient('http://localhost:1', 'anon',
            authOptions: const AuthClientOptions(autoRefreshToken: false, authFlowType: AuthFlowType.implicit));
        ref.onDispose(c.dispose);
        return c;
      }),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildFieldOsTheme(Brightness.light),
        home: const Scaffold(body: ProcurementView(projectId: 'p', companyId: 'c', userId: 'u')),
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
