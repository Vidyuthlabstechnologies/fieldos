/// Settings > Webhooks on a small phone in Hindi: the owner adds a webhook
/// for chosen records (a private or http address is refused before saving),
/// sees the secret once, sends a test, switches it off and deletes it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/features/settings/webhooks_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';

class _FakeHooks implements WebhooksService {
  @override
  SupabaseClient get client => throw UnimplementedError();
  final hooks = <Webhook>[];
  final calls = <String>[];
  final secret = 'whsec_${'cd' * 24}';

  @override
  Future<List<Webhook>> list(String companyId) async => [...hooks];

  @override
  Future<String> create(String companyId, {required String url, required List<String> events, String? description}) async {
    hooks.add(Webhook(id: 'w${hooks.length}', url: url, events: events, enabled: true, createdAt: DateTime(2026, 11, 21), description: description));
    return secret;
  }

  @override
  Future<void> setEnabled(String id, bool enabled) async {
    calls.add('enabled $id $enabled');
    final i = hooks.indexWhere((w) => w.id == id);
    final w = hooks[i];
    hooks[i] = Webhook(id: w.id, url: w.url, events: w.events, enabled: enabled, createdAt: w.createdAt, description: w.description,
        disabledReason: enabled ? null : 'Switched off by the owner');
  }

  @override
  Future<String> rotateSecret(String id) async => secret;

  @override
  Future<void> delete(String id) async => hooks.removeWhere((w) => w.id == id);

  @override
  Future<void> sendTest(String id) async => calls.add('test $id');

  @override
  Future<List<WebhookDelivery>> deliveries(String id) async => [
        WebhookDelivery(eventType: 'tasks.changed', status: 'pending', attempts: 2, createdAt: DateTime(2026, 11, 21), lastError: 'HTTP 500'),
      ];
}

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));

  test('addresses: public https only', () {
    expect(webhookAddressLooksRight('https://hooks.zapier.com/hooks/catch/1/x'), isTrue);
    expect(webhookAddressLooksRight('https://hook.eu1.make.com/abc'), isTrue);
    for (final bad in ['http://hooks.zapier.com/x', 'https://192.168.1.5/x', 'https://localhost/x', 'https://erp.local/x',
        'https://a:b@hooks.zapier.com/x', 'https://hooks.zapier.com:8080/x', 'hooks.zapier.com', '']) {
      expect(webhookAddressLooksRight(bad), isFalse, reason: bad);
    }
  });

  testWidgets('add, see the secret once, test, switch off, delete (Hindi, small phone)', (tester) async {
    final fake = _FakeHooks();
    setCurrentLanguage(AppLanguage.hi);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [webhooksServiceProvider.overrideWithValue(fake)],
      child: MaterialApp(
        theme: buildFieldOsTheme(Brightness.light),
        locale: AppLanguage.hi.locale,
        supportedLocales: [for (final l in AppLanguage.offered) l.locale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const WebhooksScreen(companyId: 'c1'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text(tr('No webhooks yet')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('webhook-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('webhook-url')), 'http://10.0.0.4/hook');
    await tester.pump();
    expect(find.text(tr('Use a public https:// address')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('webhook-create'))).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('webhook-url')), 'https://hooks.zapier.com/hooks/catch/1/x');
    await tester.enterText(find.byKey(const Key('webhook-name')), 'Zapier');
    await tester.tap(find.byKey(const Key('webhook-everything')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('webhook-event-approvals')));
    await tester.tap(find.byKey(const Key('webhook-event-approvals')));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('webhook-create')));
    await tester.pumpAndSettle();
    expect(find.text(fake.secret), findsOneWidget, reason: 'shown once');
    await tester.tap(find.byKey(const Key('webhook-done')));
    await tester.pumpAndSettle();
    expect(find.text(fake.secret), findsNothing);
    expect(fake.hooks.single.events, ['approvals']);
    expect(find.text('Zapier'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('webhook-menu-w0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tr('Send a test')));
    await tester.pumpAndSettle();
    expect(fake.calls, ['test w0']);

    await tester.tap(find.byKey(const Key('webhook-menu-w0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tr('Recent deliveries')));
    await tester.pumpAndSettle();
    expect(find.textContaining('HTTP 500'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('webhook-menu-w0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tr('Switch off')));
    await tester.pumpAndSettle();
    expect(fake.hooks.single.enabled, isFalse);

    await tester.tap(find.byKey(const Key('webhook-menu-w0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tr('Delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('webhook-confirm')));
    await tester.pumpAndSettle();
    expect(fake.hooks, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
