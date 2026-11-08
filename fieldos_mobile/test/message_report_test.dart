import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/chat/project_chat_view.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/message_report_service.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

class _FakeReports extends MessageReportService {
  _FakeReports(AppDatabase db, {this.fail = false, Set<String>? reported})
    : _reported = reported ?? {},
      super(db: db, client: null);
  final bool fail;
  final Set<String> _reported;
  final sent = <(String, ReportReason, String?)>[];

  @override
  Future<Set<String>> reportedIds() async => _reported;

  @override
  Future<void> report({required String messageId, required ReportReason reason, String? details}) async {
    if (fail) throw MessageReportException('The report did not go through. Check the internet and try again.');
    sent.add((messageId, reason, details));
    _reported.add(messageId);
  }
}

SupabaseClient _offlineClient() => SupabaseClient(
  'http://localhost:1',
  'anon',
  authOptions: const AuthClientOptions(autoRefreshToken: false, authFlowType: AuthFlowType.implicit),
);

void main() {
  test('reporting without Team & sync says to sign in', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final service = MessageReportService(db: db, client: null);
    expect(
      () => service.report(messageId: 'm1', reason: ReportReason.spam),
      throwsA(
        isA<MessageReportException>().having(
          (e) => e.message,
          'message',
          'Sign in under Team & sync to report a message.',
        ),
      ),
    );
    expect(await service.reportedIds(), isEmpty);
  });

  Future<_FakeReports> pumpDialog(WidgetTester tester, {bool fail = false}) async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final fake = _FakeReports(db, fail: fail);
    bool? result;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [messageReportServiceProvider.overrideWithValue(fake)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showDialog<bool>(
                context: context,
                builder: (_) => const ReportMessageDialog(messageId: 'm1'),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Report stays off until a reason is picked.
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Report')).onPressed, isNull);
    await tester.tap(find.text('Spam or fraud'));
    await tester.enterText(find.byType(TextField), 'Asks for money');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Report'));
    await tester.pumpAndSettle();
    if (!fail) expect(result, isTrue);
    return fake;
  }

  testWidgets('a report sends the reason and details', (tester) async {
    final fake = await pumpDialog(tester);
    expect(fake.sent, [('m1', ReportReason.spam, 'Asks for money')]);
    expect(find.byType(ReportMessageDialog), findsNothing);
  });

  testWidgets('a failed report stays open with the reason', (tester) async {
    final fake = await pumpDialog(tester, fail: true);
    expect(fake.sent, isEmpty);
    expect(find.text('The report did not go through. Check the internet and try again.'), findsOneWidget);
  });

  testWidgets('a reported message is folded away for the reporter', (tester) async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await tester.runAsync(
      () => db.messageDao.upsertFromRemote(
        ProjectMessagesCompanion.insert(
          id: 'm1',
          projectId: 'p1',
          senderId: 'someone',
          senderName: 'Ravi',
          body: 'rude words',
          createdAt: Value(DateTime.utc(2026, 11, 8)),
        ),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          cloudSyncClientProvider.overrideWithValue(_offlineClient()),
          messageReportServiceProvider.overrideWithValue(_FakeReports(db, reported: {'m1'})),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ProjectChatView(projectId: 'p1')),
        ),
      ),
    );
    // Drift's watch stream runs on real async; pump a bounded number of
    // frames rather than settling (the chat view keeps a progress bar).
    for (var i = 0; i < 10 && find.text('You reported this message.').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text('You reported this message.'), findsOneWidget);
    expect(find.text('rude words'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
