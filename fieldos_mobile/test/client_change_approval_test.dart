/// The client approves or declines a change before it is built, and the
/// builder sends and withdraws them (customer review: the homeowner's biggest
/// fear is extras she never agreed to).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/portals/change_approval.dart';
import 'package:fieldos_mobile/features/portals/portal_screens.dart';
import 'package:fieldos_mobile/features/portals/portal_service.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

SupabaseClient _offline() => SupabaseClient('http://localhost:1', 'anon',
    authOptions: const AuthClientOptions(autoRefreshToken: false, authFlowType: AuthFlowType.implicit));

class _Portal extends PortalService {
  _Portal({List<ChangeRequest>? sent}) : super(_offline()) {
    this.sent = [...?sent];
  }
  late List<ChangeRequest> sent;
  final decisions = <(String, bool, String?)>[];
  final requests = <Map<String, Object?>>[];
  final withdrawn = <String>[];
  bool failDecision = false;

  @override
  Future<void> decideChange(String id, {required bool approve, String? note}) async {
    if (failDecision) throw StateError('offline');
    decisions.add((id, approve, note));
  }

  @override
  Future<void> requestChange(String projectId,
      {required String title, String? description, required double amount, int extraDays = 0}) async {
    requests.add({'project': projectId, 'title': title, 'description': description, 'amount': amount, 'days': extraDays});
  }

  @override
  Future<List<ChangeRequest>> changesFor(String projectId) async => sent;

  @override
  Future<void> withdrawChange(String id) async => withdrawn.add(id);
}

ChangeRequest _change(int n, String status, {double amount = 85000, int days = 0, String? note, String? what}) => ChangeRequest(
      id: 'c-$n',
      number: n,
      title: n == 1 ? 'Extra bathroom' : 'Teak door',
      description: what,
      amount: amount,
      extraDays: days,
      status: status,
      decidedOn: status == 'pending' ? null : DateTime(2026, 11, 20),
      note: note,
    );

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));

  test('a server that sends no changes still parses, and one that does is read in full', () {
    final base = {'id': 'p', 'name': 'V', 'company_name': 'C', 'tasks_total': 0, 'tasks_done': 0};
    expect(ClientSite.fromJson(base).changes, isEmpty);
    final site = ClientSite.fromJson({
      ...base,
      'changes': [
        {'id': 'c1', 'number': 2, 'title': 'Teak door', 'description': null, 'amount': 32000, 'extra_days': -2, 'status': 'declined',
          'requested_on': '2026-11-10T10:00:00Z', 'decided_on': '2026-11-12T10:00:00Z', 'note': 'Too dear'},
        {'id': 'c0', 'number': 1, 'title': 'Extra bathroom', 'amount': 85000.5, 'extra_days': 6, 'status': 'pending'},
      ],
    });
    expect(site.changes.map((c) => (c.number, c.status, c.amount, c.extraDays)), [(2, 'declined', 32000.0, -2), (1, 'pending', 85000.5, 6)]);
    expect(site.changes.first.note, 'Too dear');
    expect(site.changes.last.pending, isTrue);
  });

  Future<void> pumpWidgetScreen(WidgetTester tester, Widget home, _Portal portal, {Size size = const Size(412, 915)}) async {
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      cloudSyncClientProvider.overrideWith((ref) {
        final c = _offline();
        ref.onDispose(c.dispose);
        return c;
      }),
      portalServiceProvider.overrideWithValue(portal),
      clientPortalProvider.overrideWith((ref) async => [
            ClientSite(
              id: 'p-1',
              name: 'Narapally villa',
              companyName: 'Sai Constructions',
              tasksTotal: 10,
              tasksDone: 4,
              updates: const [],
              bills: const [],
              payments: const [],
              changes: portal.sent,
            ),
          ]),
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
      child: MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: home),
    ));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }
  }

  Future<void> scrollTo(WidgetTester tester, Finder f) =>
      tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);

  group('the client', () {
    testWidgets('sees what waits for her, with its price and days, and answers it', (tester) async {
      final portal = _Portal(sent: [_change(2, 'pending', amount: 32000), _change(1, 'pending', days: 6, what: 'Attached to bedroom 2')]);
      await pumpWidgetScreen(tester, const ClientHomeScreen(), portal);
      await scrollTo(tester, find.byKey(const Key('client-changes-header')));
      expect(find.text('Changes to approve: 2'), findsOneWidget);
      expect(find.text('Adds 6 days'), findsOneWidget);
      expect(find.text('Attached to bedroom 2'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('change-amount-1'))).data, contains('85,000'));

      await scrollTo(tester, find.byKey(const Key('change-approve-1')));
      await tester.tap(find.byKey(const Key('change-approve-1')));
      await tester.pumpAndSettle();
      expect(find.text('Approve this change?'), findsOneWidget);
      expect(find.textContaining('cannot be changed afterwards'), findsOneWidget);
      expect(portal.decisions, isEmpty, reason: 'asked first, nothing sent yet');
      await tester.enterText(find.byKey(const Key('change-note')), 'Finish before Diwali');
      await tester.tap(find.byKey(const Key('change-confirm')));
      await tester.pumpAndSettle();
      expect(portal.decisions, [('c-1', true, 'Finish before Diwali')]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('can decline, with no note, and backing out of the question sends nothing', (tester) async {
      final portal = _Portal(sent: [_change(1, 'pending')]);
      await pumpWidgetScreen(tester, const ClientHomeScreen(), portal);
      await scrollTo(tester, find.byKey(const Key('change-decline-1')));
      await tester.tap(find.byKey(const Key('change-decline-1')));
      await tester.pumpAndSettle();
      expect(find.text('Decline this change?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(portal.decisions, isEmpty);

      await tester.tap(find.byKey(const Key('change-decline-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('change-confirm')));
      await tester.pumpAndSettle();
      expect(portal.decisions, [('c-1', false, null)]);
    });

    testWidgets('a failed answer says so and sends nothing twice', (tester) async {
      final portal = _Portal(sent: [_change(1, 'pending')])..failDecision = true;
      await pumpWidgetScreen(tester, const ClientHomeScreen(), portal);
      await scrollTo(tester, find.byKey(const Key('change-approve-1')));
      await tester.tap(find.byKey(const Key('change-approve-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('change-confirm')));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(portal.decisions, isEmpty);
    });

    testWidgets('answered changes show how, when and why, and have no buttons', (tester) async {
      final portal = _Portal(sent: [_change(2, 'declined', note: 'Too dear', amount: 32000), _change(1, 'approved')]);
      await pumpWidgetScreen(tester, const ClientHomeScreen(), portal);
      await scrollTo(tester, find.byKey(const Key('client-changes-header')));
      expect(find.text('Changes'), findsOneWidget, reason: 'nothing waiting, so no count');
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('Declined'), findsOneWidget);
      expect(find.text('"Too dear"'), findsOneWidget);
      expect(find.byKey(const Key('change-approve-1')), findsNothing);
      expect(find.byKey(const Key('change-decline-2')), findsNothing);
    });

    testWidgets('with no changes the section is not there at all', (tester) async {
      await pumpWidgetScreen(tester, const ClientHomeScreen(), _Portal());
      expect(find.byKey(const Key('client-changes-header')), findsNothing);
    });

    testWidgets('Telugu on a 320 px phone fits the question', (tester) async {
      setCurrentLanguage(AppLanguage.te);
      final portal = _Portal(sent: [_change(1, 'pending', days: 6, what: 'Attached to bedroom 2')]);
      await pumpWidgetScreen(tester, const ClientHomeScreen(), portal, size: const Size(320, 640));
      await scrollTo(tester, find.byKey(const Key('change-approve-1')));
      await tester.tap(find.byKey(const Key('change-approve-1')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('change-confirm')), findsOneWidget);
    });
  });

  group('the builder', () {
    late Project project;
    Future<void> open(WidgetTester tester, _Portal portal) async {
      project = Project(
          id: 'p-1', companyId: 'c', name: 'Narapally villa', status: 'active', createdAt: DateTime(2026, 11, 1));
      await pumpWidgetScreen(tester, ClientChangesScreen(project: project), portal);
    }

    testWidgets('sees what was sent and what came back, and can withdraw only what is waiting', (tester) async {
      final portal = _Portal(sent: [_change(2, 'pending', amount: 32000), _change(1, 'approved', note: 'Go ahead')]);
      await open(tester, portal);
      expect(find.text('Waiting for the client'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('"Go ahead"'), findsOneWidget);
      expect(find.byKey(const Key('change-withdraw-1')), findsNothing, reason: 'an answered change is final');
      await tester.tap(find.byKey(const Key('change-withdraw-2')));
      await tester.pumpAndSettle();
      expect(portal.withdrawn, isEmpty, reason: 'asked first');
      await tester.tap(find.byKey(const Key('change-withdraw-confirm')));
      await tester.pumpAndSettle();
      expect(portal.withdrawn, ['c-2']);
    });

    testWidgets('Telugu on a 320 px phone fits the list and the form', (tester) async {
      setCurrentLanguage(AppLanguage.te);
      project = Project(id: 'p-1', companyId: 'c', name: 'Narapally villa', status: 'active', createdAt: DateTime(2026, 11, 1));
      await pumpWidgetScreen(tester, ClientChangesScreen(project: project), _Portal(sent: [_change(1, 'pending', days: 6, what: 'Attached to bedroom 2')]),
          size: const Size(320, 640));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('change-ask')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('change-send')), findsOneWidget);
    });

    testWidgets('an empty list explains what it is for', (tester) async {
      await open(tester, _Portal());
      expect(find.text('Nothing sent yet'), findsOneWidget);
    });

    testWidgets('sends a change with its price and days, and refuses one with no title or no price', (tester) async {
      final portal = _Portal();
      await open(tester, portal);
      await tester.tap(find.byKey(const Key('change-ask')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('change-price')), '85000');
      await tester.tap(find.byKey(const Key('change-send')));
      await tester.pumpAndSettle();
      expect(find.text('Give the change a title.'), findsOneWidget);
      expect(portal.requests, isEmpty);

      await tester.tap(find.byKey(const Key('change-ask')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('change-title')), 'Extra bathroom');
      await tester.tap(find.byKey(const Key('change-send')));
      await tester.pumpAndSettle();
      expect(find.text('Enter the price for the client.'), findsOneWidget);
      expect(portal.requests, isEmpty);

      await tester.tap(find.byKey(const Key('change-ask')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('change-title')), 'Extra bathroom');
      await tester.enterText(find.byKey(const Key('change-what')), 'Attached to bedroom 2');
      await tester.enterText(find.byKey(const Key('change-price')), '85,000');
      await tester.enterText(find.byKey(const Key('change-days')), '6');
      await tester.tap(find.byKey(const Key('change-send')));
      await tester.pumpAndSettle();
      expect(portal.requests, [
        {'project': 'p-1', 'title': 'Extra bathroom', 'description': 'Attached to bedroom 2', 'amount': 85000.0, 'days': 6}
      ]);
    });
  });
}
