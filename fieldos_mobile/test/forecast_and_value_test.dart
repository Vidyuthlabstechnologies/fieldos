import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/dashboard/project_cost_summary.dart';
import 'package:fieldos_mobile/features/dashboard/value_summary.dart';

void main() {
  test('forecast scales spending up by the share of work done, once there is enough to go on', () {
    expect(forecastAtCompletion(400000, 40), 1000000);
    expect(forecastAtCompletion(400000, 5), isNull);
    expect(forecastAtCompletion(0, 50), isNull);
    expect(forecastAtCompletion(900000, 100), 900000);
  });

  test('this month counts real sites only and estimates the time saved', () async {
    final db = AppDatabase.memory();
    final now = DateTime(2026, 11, 20);
    await db.projectDao.create(ProjectsCompanion.insert(id: 'p', companyId: 'c', name: 'Villa'));
    for (var i = 0; i < 4; i++) {
      await db.dprDao.create(DprEntriesCompanion.insert(
          id: 'd$i', projectId: 'p', createdBy: 'u', entryDate: DateTime(2026, 11, 1 + i), workSummary: 'x'));
    }
    await db.dprDao.create(DprEntriesCompanion.insert(
        id: 'old', projectId: 'p', createdBy: 'u', entryDate: DateTime(2026, 10, 30), workSummary: 'x'));
    for (var i = 0; i < 60; i++) {
      await db.attendanceDao.punchIn(LabourAttendanceCompanion.insert(
          id: 'a$i', projectId: 'p', workerName: 'w$i', recordedBy: 'u', punchIn: DateTime(2026, 11, 3, 8)));
    }
    final v = await buildValueSummary(db, 'c', now: now);
    expect((v.reports, v.attendance), (4, 60));
    expect(v.hoursSaved, (4 * 15 + 60 * 0.5) / 60);
    expect(hoursLabel(v.hoursSaved), 'about 2 hours');
    expect(hoursLabel(0.4), 'under an hour');
    await db.close();
  });

  test('the count line says 1 expense, not 1 expenses', () {
    expect(valueFacts(const ValueSummary(reports: 1, attendance: 1, vouchers: 1, deliveries: 1, bills: 1)),
        '1 daily report · 1 attendance entry · 1 expense · 1 delivery checked · 1 client bill');
    expect(valueFacts(const ValueSummary(reports: 0, attendance: 2, vouchers: 3, deliveries: 0, bills: 0)),
        '2 attendance entries · 3 expenses');
  });
}
