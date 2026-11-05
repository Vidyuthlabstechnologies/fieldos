import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/reports/dpr_report.dart';
import 'package:fieldos_mobile/services/notification_service.dart';

void main() {
  group('describeRemoteRow', () {
    test('a colleague\'s chat message alerts with their name', () {
      final a = describeRemoteRow('project_messages', {'sender_id': 'them', 'sender_name': 'Ravi', 'body': 'Truck late'},
          myUserId: 'me');
      expect(a?.title, 'Ravi');
      expect(a?.body, 'Truck late');
    });

    test('my own message never alerts me', () {
      expect(describeRemoteRow('project_messages', {'sender_id': 'me', 'sender_name': 'Me', 'body': 'x'}, myUserId: 'me'),
          isNull);
    });

    test('new issue shows severity and description', () {
      final a = describeRemoteRow('issues', {'severity': 'high', 'description': 'Crack in column C4'}, myUserId: 'me');
      expect(a?.title, 'New high-severity issue');
      expect(a?.body, 'Crack in column C4');
    });

    test('only pending approvals that someone else requested alert', () {
      expect(
        describeRemoteRow('approvals', {'requested_by': 'them', 'status': 'pending', 'entity_type': 'purchase_order'},
            myUserId: 'me')?.body,
        'A purchase order is waiting for a decision',
      );
      expect(describeRemoteRow('approvals', {'requested_by': 'me', 'status': 'pending'}, myUserId: 'me'), isNull);
      expect(describeRemoteRow('approvals', {'requested_by': 'them', 'status': 'approved'}, myUserId: 'me'), isNull);
    });

    test('long text is trimmed and other tables stay quiet', () {
      final a = describeRemoteRow('project_messages', {'sender_id': 'x', 'sender_name': 'A', 'body': 'z' * 500},
          myUserId: 'me');
      expect(a!.body.length, 120);
      expect(describeRemoteRow('tasks', {'title': 't'}, myUserId: 'me'), isNull);
    });
  });

  group('buildDprPdf', () {
    final project = Project(
      id: 'p1',
      companyId: 'c1',
      name: 'Narapally Block A',
      clientName: 'Client Ltd',
      status: 'active',
      createdAt: DateTime.utc(2026, 1, 1),
    );
    DprEntry dpr(String summary) => DprEntry(
          id: 'd1',
          projectId: 'p1',
          createdBy: 'u1',
          entryDate: DateTime.utc(2026, 11, 5),
          workSummary: summary,
          manpowerCount: 24,
          weather: 'Sunny',
          status: 'confirmed',
          source: 'manual',
          createdAt: DateTime.utc(2026, 11, 5),
        );

    test('produces a PDF with issues, skipping a missing photo', () async {
      final bytes = await buildDprPdf(
        companyName: 'Sri Sai Constructions',
        project: project,
        dpr: dpr('Slab shuttering, 2nd floor'),
        photoPaths: ['/nonexistent/photo.jpg'],
        issues: [
          Issue(
            id: 'i1',
            projectId: 'p1',
            description: 'Steel delivery short by 2 t',
            severity: 'high',
            status: 'open',
            createdAt: DateTime.utc(2026, 11, 5),
          ),
        ],
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(1000));
    });

    test('local-script detection', () {
      expect(needsLocalScript('Slab work done — 24 workers'), isFalse);
      expect(needsLocalScript('స్లాబ్ పని'), isTrue);
      expect(needsLocalScript('स्लैब का काम'), isTrue);
    });

    test('does not crash on an Indic-language summary', () async {
      final bytes = await buildDprPdf(
        companyName: 'Co',
        project: project,
        dpr: dpr('రెండవ అంతస్తు స్లాబ్ పని పూర్తయింది'),
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      final tmp = File('${Directory.systemTemp.path}/dpr_test.pdf');
      await tmp.writeAsBytes(bytes);
      expect(tmp.lengthSync(), bytes.length);
    });
  });
}
