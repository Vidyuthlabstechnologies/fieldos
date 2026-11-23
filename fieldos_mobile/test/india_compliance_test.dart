/// The November 2026 India compliance pass: proof of consent is queued for
/// the server (DPDP Act s.6(10)), the rules are shown once a year (IT
/// Rules 2021 rule 3(1)(c)), only adults are added as workers in the India
/// app (child and adolescent labour law), and tax invoices carry the
/// client's address (CGST rule 46(e), (f)).
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/attendance/attendance_consent.dart';
import 'package:fieldos_mobile/features/legal/consent_record.dart';
import 'package:fieldos_mobile/features/legal/legal_texts.dart';
import 'package:fieldos_mobile/features/legal/privacy_notice.dart';
import 'package:fieldos_mobile/features/legal/rules_reminder.dart';
import 'package:fieldos_mobile/features/workers/workers_screen.dart';
import 'package:fieldos_mobile/sync/sync_mappers.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  group('proof of consent', () {
    test('every give and withdraw is queued with the time and the policy version', () async {
      await setAiConsent(db, 'u1', true);
      await setAttendanceConsent(db, 'u1', true);
      await setAiConsent(db, 'u1', false);
      final q = await pendingConsentRecords(db, 'u1');
      expect(q.map((e) => (e['purpose'], e['granted'])), [
        ('ai_assistant', true),
        ('attendance_photo_location', true),
        ('ai_assistant', false),
      ]);
      for (final e in q) {
        expect(e['notice_version'], privacyPolicy.updated);
        expect(DateTime.parse(e['given_at'] as String).isUtc, isTrue);
      }
      // The local switches still answer as before.
      expect(await aiConsentGiven(db, 'u1'), isFalse);
      expect(await attendanceConsentGiven(db, 'u1'), isTrue);
    });

    test('queues are per local account, so a shared phone never mixes people', () async {
      await setAiConsent(db, 'u1', true);
      await setAiConsent(db, 'u2', false);
      expect((await pendingConsentRecords(db, 'u1')).single['granted'], isTrue);
      expect((await pendingConsentRecords(db, 'u2')).single['granted'], isFalse);
    });

    test('without a cloud the choices stay queued on the phone', () async {
      await setAiConsent(db, 'u1', true);
      final sent = await ConsentRecorder(db: db, client: null).flush('u1');
      expect(sent, 0);
      expect(await pendingConsentRecords(db, 'u1'), hasLength(1));
    });

    test('the queue keeps at most the newest 200 choices', () async {
      for (var i = 0; i < 205; i++) {
        await queueConsentRecord(db, 'u1', ConsentPurpose.aiAssistant, i.isEven);
      }
      final q = await pendingConsentRecords(db, 'u1');
      expect(q, hasLength(200));
      expect(q.last['granted'], isTrue); // i = 204
    });
  });

  group('yearly rules reminder', () {
    final start = DateTime.utc(2026, 11, 23);

    test('the first look starts the clock and shows nothing', () async {
      expect(await rulesReminderDue(db, 'u1', start), isFalse);
      expect(await rulesReminderDue(db, 'u1', start.add(const Duration(days: 364))), isFalse);
      expect(await rulesReminderDue(db, 'u1', start.add(const Duration(days: 365))), isTrue);
    });

    test('"Got it" starts the next year', () async {
      await rulesReminderDue(db, 'u1', start);
      final due = start.add(const Duration(days: 400));
      expect(await rulesReminderDue(db, 'u1', due), isTrue);
      await markRulesReminderSeen(db, 'u1', due);
      expect(await rulesReminderDue(db, 'u1', due.add(const Duration(days: 30))), isFalse);
    });

    test('the terms say the reminder happens', () {
      expect(termsOfUse.sections.map((s) => s.body).join(' '), contains('Once a year the app reminds everyone'));
    });
  });

  testWidgets('adding a worker waits for the 18-or-older tick', (tester) async {
    var value = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => WorkerAgeCheck(value: value, onChanged: (v) => setState(() => value = v)),
        ),
      ),
    ));
    expect(find.text('This worker is 18 or older'), findsOneWidget);
    expect(find.textContaining('under 18'), findsOneWidget);
    await tester.tap(find.byKey(const Key('worker-age-check')));
    await tester.pump();
    expect(value, isTrue);
  });

  test('the client address syncs both ways and is left out when empty', () async {
    ClientBill bill(String? address) => ClientBill(
          id: 'b1',
          projectId: 'p1',
          kind: 'tax_invoice',
          billNumber: 'INV-0001',
          billDate: DateTime(2026, 11, 23),
          clientName: 'Sri Sai Developers',
          clientGstin: '36AAACS1234A1Z5',
          clientAddress: address,
          sac: '995411',
          linesJson: '[]',
          gstRate: 18,
          interState: false,
          retentionPct: 0,
          tdsPct: 0,
          gross: 100000,
          netPayable: 118000,
          status: 'issued',
          recordedBy: 'u1',
          createdAt: DateTime(2026, 11, 23),
        );
    expect(clientBillToSupabaseJson(bill(null)).containsKey('client_address'), isFalse);
    final json = clientBillToSupabaseJson(bill('Plot 12, Madhapur, Hyderabad 500081'));
    expect(json['client_address'], 'Plot 12, Madhapur, Hyderabad 500081');
    final back = clientBillFromSupabaseJson(json);
    expect(back.clientAddress, const Value('Plot 12, Madhapur, Hyderabad 500081'));
  });
}
