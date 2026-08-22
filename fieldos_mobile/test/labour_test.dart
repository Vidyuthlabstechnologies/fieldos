import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/labour/labour_screen.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

final _uuid = Uuid();

void main() {
  test('haversine distance is sane', () {
    // ~111 km per degree of latitude near the equator.
    final m = haversineMeters(0, 0, 1, 0);
    expect(m / 1000, closeTo(111.0, 1.0));
  });

  test('punch inside vs outside geofence', () async {
    final db = AppDatabase.memory();
    final projectId = _uuid.v4();
    await db.geofenceDao.set(projectId, 17.0, 78.0, 100);

    // within ~10 m
    final inside = await db.attendanceDao.punchIn(LabourAttendanceCompanion.insert(
      id: _uuid.v4(),
      projectId: projectId,
      workerName: 'A',
      recordedBy: 'u1',
      punchIn: DateTime.now(),
      lat: const Value(17.00009),
      lng: const Value(78.0),
      withinGeofence: const Value(null),
    ));
    // far away (~111 km)
    final outside = await db.attendanceDao.punchIn(LabourAttendanceCompanion.insert(
      id: _uuid.v4(),
      projectId: projectId,
      workerName: 'B',
      recordedBy: 'u1',
      punchIn: DateTime.now(),
      lat: const Value(18.0),
      lng: const Value(78.0),
      withinGeofence: const Value(null),
    ));

    // recompute with the geofence (mirrors the UI logic)
    final g = await db.geofenceDao.forProject(projectId);
    expect(haversineMeters(inside.lat!, inside.lng!, g!.centerLat, g.centerLng) <= g.radiusMeters, isTrue);
    expect(haversineMeters(outside.lat!, outside.lng!, g.centerLat, g.centerLng) <= g.radiusMeters, isFalse);

    await db.attendanceDao.punchOut(inside.id);
    final after = (await db.attendanceDao.forProject(projectId)).firstWhere((a) => a.id == inside.id);
    expect(after.punchOut != null, isTrue);
  });
}
