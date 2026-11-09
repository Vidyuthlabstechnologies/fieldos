import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/reports/client_update.dart';
import 'package:fieldos_mobile/features/reports/dpr_report.dart';
import 'package:fieldos_mobile/features/reports/period_report.dart';

/// The client's progress update PDF: stage, progress, finished work, what
/// comes next, photos and, when chosen, what is still due.
void main() {
  final now = DateTime(2026, 11, 12, 18);

  test('dues are what was billed less what was received, never below zero', () async {
    final db = AppDatabase.memory();
    await db.projectDao.create(ProjectsCompanion.insert(id: 'p', companyId: 'c', name: 'Villa'));
    expect((await clientDues(db, 'p')).isEmpty, isTrue);
    await db.billDao.create(ClientBillsCompanion.insert(
      id: 'b1', projectId: 'p', kind: 'ra', billNumber: 'RA-1', billDate: DateTime(2026, 10, 1), clientName: 'Mr. Reddy',
      linesJson: '[]', gross: 300000, netPayable: 295000, recordedBy: 'u'));
    await db.paymentDao.create(PaymentsReceivedCompanion.insert(
        id: 'm1', projectId: 'p', amount: 200000, receivedOn: DateTime(2026, 10, 5), fromParty: 'Mr. Reddy', mode: 'bank', recordedBy: 'u'));
    final d = await clientDues(db, 'p');
    expect((d.billed, d.received, d.due), (295000.0, 200000.0, 95000.0));
    await db.paymentDao.create(PaymentsReceivedCompanion.insert(
        id: 'm2', projectId: 'p', amount: 100000, receivedOn: DateTime(2026, 10, 9), fromParty: 'Mr. Reddy', mode: 'bank', recordedBy: 'u'));
    expect((await clientDues(db, 'p')).due, 0);
    await db.close();
  });

  test('builds a PDF with local-language text drawn by the phone', () async {
    final project = Project(
        id: 'p', companyId: 'c', name: 'గ్రీన్ వ్యాలీ', clientName: 'Mr. Reddy', status: 'active', createdAt: DateTime(2026));
    final report = PeriodReport(
      project: project,
      period: periodFor(PeriodKind.thisWeek, now),
      days: [DayNote(DateTime(2026, 11, 10), 'స్లాబ్ షట్టరింగ్', 12)],
      reportsFiled: 1,
      workingDays: 4,
      labourDays: 30,
      tasksFinished: ['Plinth beam'],
      progressNow: 42,
      lateTasks: 0,
      issuesRaised: const [],
      issuesFixed: 0,
      issuesOpen: 0,
      materials: const [],
      spent: 0,
      spentByCategory: const {},
      received: 0,
    );
    final painted = <String>[];
    final bytes = await buildClientUpdatePdf(
      companyName: 'Sri Sai Constructions',
      report: report,
      photoPaths: ['/nonexistent.jpg'],
      comingUp: ['First slab'],
      dues: const ClientDues(billed: 295000, received: 200000),
      paintText: (text, {required fontSize, required bold, required argb, required maxWidth}) async {
        painted.add(text);
        return TextPicture(
            Uint8List.fromList(base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=')),
            100,
            14);
      },
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(painted, containsAll(['గ్రీన్ వ్యాలీ', 'స్లాబ్ షట్టరింగ్']));
    expect(painted.where((t) => t.contains('Reddy')), isEmpty);
  });
}
