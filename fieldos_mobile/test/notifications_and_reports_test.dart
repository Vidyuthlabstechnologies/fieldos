import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
      name: 'Green Valley Block A',
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
      expect(needsLocalScript('“Curing” started… ₹500 paid'), isFalse, reason: 'punctuation and ₹ are swapped, not pictured');
      expect(needsLocalScript('స్లాబ్ పని'), isTrue);
      expect(needsLocalScript('स्लैब का काम'), isTrue);
    });

    test('Telugu company, summary and issue are drawn as pictures, English stays text', () async {
      final painted = <String>[];
      Future<TextPicture?> fake(String text,
          {required double fontSize, required bool bold, required int argb, required double maxWidth}) async {
        painted.add(text);
        // A 1x1 transparent PNG.
        return TextPicture(
            Uint8List.fromList(base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=')),
            100,
            14);
      }

      final bytes = await buildDprPdf(
        companyName: 'శ్రీ సాయి కన్స్ట్రక్షన్స్',
        project: project,
        dpr: dpr('రెండవ అంతస్తు స్లాబ్ పని పూర్తయింది'),
        issues: [
          Issue(
            id: 'i1',
            projectId: 'p1',
            description: 'స్టీల్ తక్కువ వచ్చింది',
            severity: 'high',
            status: 'open',
            createdAt: DateTime.utc(2026, 11, 5),
          ),
        ],
        paintText: fake,
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(painted, containsAll(['శ్రీ సాయి కన్స్ట్రక్షన్స్', 'రెండవ అంతస్తు స్లాబ్ పని పూర్తయింది', 'స్టీల్ తక్కువ వచ్చింది']));
      expect(painted.where((t) => t.contains('Green Valley')), isEmpty);
    });

    test('a long local-language summary is split so no picture is taller than a page', () async {
      final lengths = <int>[];
      final long = [for (var i = 1; i <= 60; i++) 'బ్లాక్ $i లో స్లాబ్ పని పూర్తయింది.'].join(' ');
      await buildDprPdf(
        companyName: 'Co',
        project: project,
        dpr: dpr(long),
        paintText: (text, {required fontSize, required bold, required argb, required maxWidth}) async {
          lengths.add(text.length);
          return null; // falls back to the note
        },
      );
      expect(lengths.length, greaterThan(2));
      expect(lengths.every((l) => l <= 501), isTrue);
    });

    test('the phone text engine really produces a picture', () async {
      final p = await paintWithPhoneFonts('స్లాబ్ పని', fontSize: 11, bold: false, argb: 0xFF13233A, maxWidth: 300);
      expect(p, isNotNull);
      expect(p!.png.sublist(1, 4), 'PNG'.codeUnits);
      expect(p.width, greaterThan(0));
      expect(p.width, lessThanOrEqualTo(300));
    });

    test('the share message has the date in words and no "0 workers"', () {
      final text = dprShareText(project, DprEntry(
        id: 'd2',
        projectId: 'p1',
        createdBy: 'u1',
        entryDate: DateTime(2026, 11, 5, 18),
        workSummary: 'Brickwork on the 3rd floor',
        manpowerCount: 0,
        status: 'confirmed',
        source: 'manual',
        createdAt: DateTime(2026, 11, 5),
      ));
      expect(text, startsWith('Daily progress report · Green Valley Block A · 5 Nov 2026'));
      expect(text, isNot(contains('0 workers')));
      expect(text, endsWith('Brickwork on the 3rd floor'));
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
